# scope_generator

Dart analyzer plugin that generates Flutter Scope boilerplate in seconds.

No code generation. No build_runner. Just Quick Actions.

## Quick Start

**1. Add to `analysis_options.yaml`:**
```yaml
plugins:
  scope_generator:
    git:
      url: https://github.com/Tembeon/tem_tools.git
      path: scope_generator
      ref: 2025.01.09
```

**2. Restart Analysis Server**

**3. Use Quick Actions (Cmd+. / Ctrl+.)**

## Features

### Generate Scope wrapper

Write a controller → get a complete Scope with InheritedModel.

```dart
// Put cursor here, press Cmd+.
class JamsStateController extends ValueNotifier<JamsState> {
  ...
}
```

**Creates 2 files:**

| File | Contains |
|------|----------|
| `jams_scope.dart` | Scope widget, InheritedModel, aspects |
| `jams_scope_controller.dart` | IScopeController interface |

**Generated API:**
```dart
JamsScope.stateOf(context)           // Rebuilds on state change
JamsScope.stateControllerOf(context) // Access controller
JamsScope.scopeControllerOf(context) // Access scope actions
```

### Expose as Scope aspect

Need selective rebuilds? Expose individual state fields as aspects.

```dart
final class JamsState {
  final bool isPlaying;  // ← Cursor here, Cmd+.
  final Track? track;
}
```

**Adds:**
```dart
JamsScope.isPlayingOf(context)  // Rebuilds ONLY when isPlaying changes
```

No data duplication — uses existing state, just smarter comparison.

## Supported Controllers

Works with any `Listenable`:

- `ValueNotifier<T>`
- `ChangeNotifier`
- `StateController<T>` (package:control)
- Custom subclasses

## File Organization

Put files anywhere in your feature folder:

```
lib/features/jams/
├── controllers/
│   └── jams_state_controller.dart  ← Controller here
├── widgets/
│   └── jams_scope.dart             ← Scope here (auto-detected)
└── jams_screen.dart
```

The plugin searches recursively within `lib/features/xxx/` or `lib/xxx/`.

## Generated Pattern

Uses `InheritedModel` with aspects for selective rebuilds:

```dart
// Full state — rebuilds on ANY change
final state = JamsScope.stateOf(context);

// Specific field — rebuilds only when that field changes
final isPlaying = JamsScope.isPlayingOf(context);
```

## Requirements

- Dart `>=3.10` / Flutter `>=3.38` (analysis_server_plugin support)
