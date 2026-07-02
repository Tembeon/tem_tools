---
name: scope-pattern
description: This skill should be used when implementing or explaining the scope-based Flutter architecture (a Listenable controller such as StateController from package:control + Scope widget with InheritedModel and aspects + Screen), when the user asks to "create a feature with scope pattern", "explain aspects in InheritedModel", "granular rebuilds without a state management package", "my whole screen rebuilds when one field changes", "only rebuild the widget that uses a field", "StateController conventions", or reviews/writes code in a lib/features/<name>/ structure with *_scope.dart and *_state_controller.dart files. Do NOT use for bloc, riverpod or provider architectures.
version: 1.0.0
---

# Scope-based Flutter architecture

A three-layer feature architecture built on Flutter's `InheritedModel`, without a heavyweight state management framework:

1. **Controller** - any `Listenable` owning immutable state. `StateController` from `package:control` is the recommended implementation (handler mixins, setState discipline; its `IController implements Listenable`), but `ChangeNotifier` or `ValueNotifier<State>` satisfy the same contract - the Scope layer only needs "notifies + exposes current state".
2. **Scope** - StatefulWidget exposing state and controller via `InheritedModel` with aspects for granular rebuilds.
3. **Screen** - UI consuming the scope.

The examples below use `package:control`; with a plain `Listenable` controller replace `StateConsumer` with `ListenableBuilder` and read the state from the controller.

## When the full pattern applies

Required when a feature loads data (API/database), has loading/error/loaded states, async business logic, or needs granular rebuild control over multiple fields.

NOT required for simple UI state: navigation index (`ValueNotifier` + `InheritedNotifier`), a single boolean (`InheritedWidget`), or presentation-only widgets receiving data via constructor. Do not over-apply.

## Directory layout

```
lib/features/<feature>/
├── controllers/
│   └── <feature>_state_controller.dart   # controller + state
├── widgets/
│   ├── <feature>_scope.dart              # Scope widget
│   └── <feature>_screen.dart             # UI
```

Imports are always `package:<app_name>/...` (take the name from pubspec.yaml), never relative.

## StateController and State

```dart
import 'package:control/control.dart';
import 'package:flutter/foundation.dart';

enum ProfileStateType { idle, loading, error }

final class ProfileState {
  const ProfileState({this.stateType = ProfileStateType.idle, this.error});

  final ProfileStateType stateType;
  final Object? error;

  bool get isLoading => stateType == ProfileStateType.loading;
  bool get hasError => stateType == ProfileStateType.error;

  // CRITICAL: never `?.call() ?? this.x` - the ?? form makes it impossible
  // to set a nullable field back to null. Two correct forms:
  //
  // 1. With package:copy (preferred when available):
  //      stateType: stateType.or(this.stateType),
  //      error: error.or(this.error),
  //    Import it as `import 'package:copy/copy.dart' hide ValueGetter;`
  //    alongside foundation.dart - keeps listEquals and other foundation
  //    symbols available with no ambiguous_import (copy's ValueGetter is
  //    interchangeable with Flutter's; details in the use-copy skill).
  //
  // 2. Zero-dependency ternary:
  ProfileState copyWith({
    ValueGetter<ProfileStateType>? stateType,
    ValueGetter<Object?>? error,
  }) => ProfileState(
    stateType: stateType != null ? stateType() : this.stateType,
    error: error != null ? error() : this.error,
  );

  // == and hashCode over ALL fields are mandatory: aspect-based rebuilds
  // compare states. For List fields use listEquals / Object.hashAll.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProfileState &&
          stateType == other.stateType &&
          error == other.error;

  @override
  int get hashCode => Object.hash(stateType, error);
}

base class ProfileStateController extends StateController<ProfileState>
    with SequentialControllerHandler {
  ProfileStateController() : super(initialState: const ProfileState());

  Future<void> load() => handle(
        () async {
          setState(state.copyWith(stateType: () => ProfileStateType.loading));
          // ... load data ...
          setState(state.copyWith(
            stateType: () => ProfileStateType.idle,
            error: () => null,
          ));
        },
        error: (error, stackTrace) async => setState(state.copyWith(
          stateType: () => ProfileStateType.error,
          error: () => error,
        )),
      );
}
```

Conventions: when using `package:control`, a handler mixin is mandatory (`SequentialControllerHandler` for ordered ops, `DroppableControllerHandler` to ignore re-entry, `ConcurrentControllerHandler` for independent ops); with a plain `ChangeNotifier` controller, wrap async work in try/catch yourself where `handle()`'s `error:` callback would have been. Only `package:flutter/foundation.dart` from Flutter in controllers; catch `Exception`, never `Error`.

## Scope - InheritedModel with aspects (the load-bearing part)

Without aspects, any state change rebuilds every subscriber. With aspects, a widget depending only on the controller never rebuilds on state changes.

```dart
enum _Aspect { state, controller }

class ProfileScope extends StatefulWidget {
  const ProfileScope({
    super.key,
    required ProfileStateController stateController,
    required this.child,
  }) : _stateController = stateController;

  final ProfileStateController _stateController;
  final Widget child;

  /// State access: listen defaults to TRUE (UI wants rebuilds).
  static ProfileState stateOf(BuildContext context, {bool listen = true}) =>
      _ProfileInherited.of(context, aspect: _Aspect.state, listen: listen).state;

  /// Controller access: listen defaults to FALSE (actions don't rebuild).
  static ProfileStateController controllerOf(BuildContext context, {bool listen = false}) =>
      _ProfileInherited.of(context, aspect: _Aspect.controller, listen: listen).controller;

  @override
  State<ProfileScope> createState() => _ProfileScopeState();
}

class _ProfileScopeState extends State<ProfileScope> {
  @override
  Widget build(BuildContext context) {
    return StateConsumer<ProfileStateController, ProfileState>(
      controller: widget._stateController,
      child: widget.child,
      builder: (context, state, child) => _ProfileInherited(
        state: state,
        controller: widget._stateController,
        child: child!,
      ),
    );
  }
}

class _ProfileInherited extends InheritedModel<_Aspect> {
  const _ProfileInherited({
    required super.child,
    required this.state,
    required this.controller,
  });

  final ProfileState state;
  final ProfileStateController controller;

  static _ProfileInherited of(BuildContext context, {_Aspect? aspect, bool listen = true}) {
    final result = listen
        ? context.dependOnInheritedWidgetOfExactType<_ProfileInherited>(aspect: aspect)
        : context.getElementForInheritedWidgetOfExactType<_ProfileInherited>()?.widget
            as _ProfileInherited?;
    if (result == null) {
      throw FlutterError('No ProfileScope found in context');
    }
    return result;
  }

  @override
  bool updateShouldNotify(_ProfileInherited old) =>
      state != old.state || controller != old.controller;

  @override
  bool updateShouldNotifyDependent(
    covariant _ProfileInherited oldWidget,
    Set<_Aspect> dependencies,
  ) => dependencies.any((aspect) => switch (aspect) {
        _Aspect.state => state != oldWidget.state,
        _Aspect.controller => controller != oldWidget.controller,
      });
}
```

Non-negotiable requirements:
- `InheritedModel`, NOT `InheritedWidget` - the latter loses granular rebuilds.
- Private `_Aspect` enum, one value per exposed field.
- `updateShouldNotifyDependent` with an exhaustive switch over aspects.
- `updateShouldNotify` GATES `updateShouldNotifyDependent`: the framework runs the per-aspect check only after `updateShouldNotify` returns true. Keep it a superset of every field any aspect checks - a field missed there makes its dependents go stale silently.
- `of()` takes `aspect` and `listen`; `listen: false` path uses `getElementForInheritedWidgetOfExactType` (safe in initState).
- Static accessors: state defaults `listen: true`, controllers default `listen: false`.

## Screen

- `Scope.stateOf(context)` for rendering, `Scope.controllerOf(context)` for actions.
- Trigger initial load from `initState` via `controllerOf(context, listen: false)`.
- No `SingleChildScrollView` - use `CustomScrollView` + `SliverFillRemaining`.
- Handle loading / error / data states; localize user-facing strings if the project has localization.

## Companion packages (optional, from the same tem_tools ecosystem)

None of these are required, but when the project uses them, prefer them:

- **copy** - `or()` sugar for the copyWith pattern above; also resolves the
  ValueGetter name for both Flutter and pure Dart.
- **json** - typed manual parsing inside `load()`:
  `final profile = Profile.fromJson(Json.decode(response.body));`
- **http_middleware** - its streamed SWR maps directly onto this pattern:
  subscribe to `client.watchGet(uri)` in the controller and `setState` per
  event - the UI gets the cached state instantly and the fresh state when
  revalidation lands. Details live in the `http-middleware` plugin skill.

## Review shortcuts

When reviewing, check in this order: InheritedModel used? `_Aspect` enum exists? `updateShouldNotifyDependent` with switch? accessors pass `aspect:` and have `listen` with correct defaults? State has `==`/`hashCode` over all fields? copyWith uses `or()` from package:copy or a ternary - never `?.call() ?? `?
