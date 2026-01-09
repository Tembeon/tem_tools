# scope_generator

Analysis server plugin that generates Flutter Scope boilerplate from `Listenable`-based controller classes.

## Features

- Quick Assist: "Generate Scope wrapper"
- Works with any `Listenable` subclass (`ValueNotifier`, `ChangeNotifier`, custom)
- Generates complete Scope pattern with `stateOf`/`controllerOf` methods
- IDE integration (VS Code, Android Studio, IntelliJ)

## Installation

Add to your project's `analysis_options.yaml`:

```yaml
plugins:
  scope_generator:
    path: /path/to/scope_generator
```

Or from pub.dev (when published):

```yaml
plugins:
  scope_generator: ^1.0.0
```

**Important:** Restart the Analysis Server after adding the plugin.

## Usage

1. Write a controller class:

```dart
class JamsStateController extends ValueNotifier<JamsState> {
  JamsStateController() : super(const JamsInitial());

  // ... methods
}
```

2. Place cursor on the class name
3. Open Quick Actions (Cmd+. / Ctrl+.)
4. Select "Generate Scope wrapper"

## Generated Code

The plugin generates:

```dart
/// {@template JamsScope}
/// Scope for [JamsStateController].
/// {@endtemplate}
class JamsScope extends StatefulWidget {
  /// {@macro JamsScope}
  const JamsScope({required this.child, super.key});

  /// Child widget.
  final Widget child;

  /// Returns current state (rebuilds on change).
  static JamsState stateOf(BuildContext context) =>
      controllerOf(context, listen: true).value;

  /// Returns controller for calling methods.
  static JamsStateController controllerOf(BuildContext context, {bool listen = false}) {
    final inherited = listen
        ? context.dependOnInheritedWidgetOfExactType<_JamsScopeInherited>()
        : context.getInheritedWidgetOfExactType<_JamsScopeInherited>();
    if (inherited == null) {
      throw StateError('JamsScope not found in context');
    }
    return inherited.notifier!;
  }

  @override
  State<JamsScope> createState() => _JamsScopeState();
}

class _JamsScopeState extends State<JamsScope> {
  late final JamsStateController _controller;

  @override
  void initState() {
    super.initState();
    _controller = JamsStateController(/* TODO: add dependencies */);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _JamsScopeInherited(notifier: _controller, child: widget.child);
}

class _JamsScopeInherited extends InheritedNotifier<JamsStateController> {
  const _JamsScopeInherited({required super.notifier, required super.child});
}
```

## Supported Controllers

The plugin recognizes classes extending:

- `Listenable`
- `ValueListenable<T>`
- `ChangeNotifier`
- `ValueNotifier<T>`
- Any custom subclass of the above

## Name Derivation

| Controller Name | Generated Scope |
|-----------------|-----------------|
| `JamsStateController` | `JamsScope` |
| `AuthController` | `AuthScope` |
| `UserNotifier` | `UserScope` |
| `ThemeListenable` | `ThemeScope` |

## Requirements

- Dart SDK: `>=3.10.0`
- Flutter: `>=3.38.0`

## License

MIT
