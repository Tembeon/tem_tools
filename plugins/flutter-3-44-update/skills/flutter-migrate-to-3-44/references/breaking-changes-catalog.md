# Flutter 3.44 - breaking changes catalog

Ten breaking changes shipped in Flutter 3.44 - eight on the official `docs.flutter.dev/release/breaking-changes` index plus two CLI-tool deprecations (`plugin_ffi` template and `--web-hot-reload` flag). Each entry below cites the per-change migration page or PR.

Source index: <https://docs.flutter.dev/release/breaking-changes>

---

## 1. RawMenuAnchor close order changed

Source: <https://docs.flutter.dev/release/breaking-changes/raw-menu-anchor-close-order>

What changed:

- `onCloseRequested` now fires top-down (parent first, then descendants). The framework auto-calls it on descendants.
- `onClose` now fires bottom-up (deepest descendant completes its `onClose` before the parent).
- `MenuController.close` and `MenuController.closeChildren` do NOT trigger `onCloseRequested` on a menu that is already closed.

Migration:

- Remove any manual `controller.closeChildren()` from `onCloseRequested` - it is now redundant.
- If parent `onClose` logic assumed it ran before children, refactor for bottom-up order.

`dart fix` is not supported - manual updates only.

Before:

```dart
RawMenuAnchor(
  controller: menuController,
  onCloseRequested: (hideOverlay) {
    if (!animationController.isForwardOrCompleted) return;
    menuController.closeChildren();
    animationController.reverse().whenComplete(hideOverlay);
  },
  onClose: () {
    _handleMenuClosed();
  },
)
```

After:

```dart
RawMenuAnchor(
  controller: menuController,
  onCloseRequested: (hideOverlay) {
    if (!animationController.isForwardOrCompleted) return;
    animationController.reverse().whenComplete(hideOverlay);
  },
  onClose: () {
    _handleMenuClosed();
  },
)
```

---

## 2. `ReorderableListView.onReorder` deprecated -> `onReorderItem`

Source: <https://docs.flutter.dev/release/breaking-changes/deprecate-onreorder-callback>

Applies to: `ReorderableListView`, `ReorderableListView.builder`, `ReorderableList`, `SliverReorderableList`.

The signature is identical: `void Function(int oldIndex, int newIndex)`. The semantics of `newIndex` changed.

| Callback | `newIndex` behavior |
|---|---|
| `onReorder` (deprecated) | Raw index. Caller must subtract 1 when `oldIndex < newIndex`. |
| `onReorderItem` (new) | Corrected index. The framework already applied the `-1`. |

Migration - simple case:

Before:

```dart
ReorderableListView(
  onReorder: (int oldIndex, int newIndex) {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    // handle reorder
  },
)
```

After:

```dart
ReorderableListView(
  onReorderItem: (int oldIndex, int newIndex) {
    // newIndex is already corrected - no -1 needed
    // handle reorder
  },
)
```

Migration - existing complex function that expected old semantics:

```dart
ReorderableListView(
  onReorderItem: (int oldIndex, int newIndex) {
    if (oldIndex < newIndex) {
      newIndex += 1;
    }
    return handleSomeComplexReorder(oldIndex, newIndex);
  },
)
```

`dart fix` is not supported - manual updates only.

---

## 3. `TextInputConnection.setStyle` deprecated -> `updateStyle`

Source: <https://docs.flutter.dev/release/breaking-changes/deprecate-text-input-connection-set-style>

`updateStyle` accepts a `TextInputStyle` object and supports `letterSpacing`, `wordSpacing`, `lineHeight`. The old `setStyle` lacked these, causing visual misalignment between selection highlight, IME caret, and rendered text when those properties were used.

Before:

```dart
connection.setStyle(
  fontFamily: 'Roboto',
  fontSize: 14.0,
  fontWeight: FontWeight.normal,
  textDirection: TextDirection.ltr,
  textAlign: TextAlign.start,
);
```

After:

```dart
connection.updateStyle(
  TextInputStyle(
    fontFamily: 'Roboto',
    fontSize: 14.0,
    fontWeight: FontWeight.normal,
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.start,
    letterSpacing: 1.2,
    wordSpacing: 1.0,
    lineHeight: 1.5,
  ),
);
```

---

## 4. `cacheExtent` + `cacheExtentStyle` deprecated -> `scrollCacheExtent: ScrollCacheExtent`

Source: <https://docs.flutter.dev/release/breaking-changes/scroll-cache-extent>

Affected widgets: `ListView`, `GridView`, `CustomScrollView`, `Viewport`. Also `RenderViewport` render object.

The new `ScrollCacheExtent` class merges value + strategy into one type-safe object. Two factories:

- `ScrollCacheExtent.pixels(double)` - pixel-based
- `ScrollCacheExtent.viewport(double)` - fraction of viewport

Before (pixels):

```dart
ListView(
  cacheExtent: 500.0,
  children: [...],
)
```

After:

```dart
ListView(
  scrollCacheExtent: const ScrollCacheExtent.pixels(500.0),
  children: [...],
)
```

Before (viewport-fraction):

```dart
Viewport(
  cacheExtent: 0.5,
  cacheExtentStyle: CacheExtentStyle.viewport,
  slivers: [...],
)
```

After:

```dart
Viewport(
  scrollCacheExtent: const ScrollCacheExtent.viewport(0.5),
  slivers: [...],
)
```

Render-object layer:

```dart
// before
renderViewport.cacheExtent = 500.0;
renderViewport.cacheExtentStyle = CacheExtentStyle.pixel;

// after
renderViewport.scrollCacheExtent = const ScrollCacheExtent.pixels(500.0);
```

---

## 5. `IconData` is now `final`

Source: <https://docs.flutter.dev/release/breaking-changes/icondata-class-marked-final>

`IconData` cannot be extended or implemented. Compiler error if any project subclasses or implements it:

```
The class 'IconData' is 'final' and can't be extended or implemented outside of its library.
```

Motivation: a generalized tree-shaking mechanism requires `const` instances without complex type hierarchies. Some `IconData` parameters are also annotated `@mustBeConst`.

Affected pattern: `enum AppIcons implements IconData` or `class CustomIcon extends IconData`.

Migration - wrap, do not extend. Replace the enum/subclass with a wrapper class plus a small widget:

Before (breaks):

```dart
enum AppIcons implements IconData {
  arrowUpward(0xe062),
  arrowDownward(0xe061);

  const AppIcons(this.codePoint)
    : fontFamily = 'MaterialIcons',
      fontPackage = null,
      matchTextDirection = false;

  @override final int codePoint;
  @override final String? fontFamily;
  @override final String? fontPackage;
  @override final bool matchTextDirection;
}
// usage: Icon(AppIcons.arrowUpward)
```

After:

```dart
final class AppIconData {
  final IconData iconData;
  const AppIconData._(this.iconData);

  static const arrowUpward = AppIconData._(
    IconData(0xe062, fontFamily: 'MaterialIcons'),
  );
  static const arrowDownward = AppIconData._(
    IconData(0xe061, fontFamily: 'MaterialIcons'),
  );

  static const values = [arrowUpward, arrowDownward];
}

class AppIcon extends StatelessWidget {
  const AppIcon(this.icon, {super.key});
  final AppIconData icon;

  @override
  Widget build(BuildContext context) => Icon(icon.iconData);
}
// usage: const AppIcon(AppIconData.arrowUpward)
// dot shorthand still works: const AppIcon(.arrowUpward)
```

If a non-const `IconData` is unavoidable and tree-shaking loss is acceptable for that icon, suppress the `mustBeConst` lint:

```dart
// ignore: non_const_argument_for_const_parameter
Icon(myDynamicIconData);
```

---

## 6. `ListTile` debug warning when wrapped in colored widget

Source: <https://docs.flutter.dev/release/breaking-changes/list-tile-color-warning>

Debug-mode only. Fires when an opaque-coloured widget sits between a `ListTile` and the nearest `Material` ancestor. The reason: `ListTile` paints background colour and ink splashes on the nearest `Material`, so an intermediate opaque colour hides them.

Triggers:

- `Container` with a `color` property
- `ColoredBox`

Error text (paraphrased): "ListTile background color or ink splashes may be invisible. The ListTile is wrapped in a Container that has a background color..."

Two fixes:

Option 1 - move colour to `Material`:

```dart
Material(
  color: Colors.pink,
  child: Container(
    child: ListTile(
      title: const Text('Title'),
      onTap: () {},
    ),
  ),
)
```

Option 2 - wrap `ListTile` in a transparent `Material`:

```dart
Container(
  color: Colors.blue,
  child: Material(
    type: MaterialType.transparency,
    child: ListTile(
      title: const Text('Title'),
      onTap: () {},
    ),
  ),
)
```

This is debug-only - the production rendering is unchanged, but the warning surfaces the latent bug.

---

## 7. Built-in Kotlin (AGP 9.0)

Source: <https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin>
App-developer detail: <https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-app-developers>
Underlying AGP docs: <https://developer.android.com/build/migrate-to-built-in-kotlin>

AGP 9.0 ships Kotlin in-tree. Applying `org.jetbrains.kotlin.android` (aka `kotlin-android`) separately conflicts with the new built-in support.

Flutter 3.44 adds temporary compatibility shims so projects keep building:

- Flutter migrator auto-writes opt-out flags to `android/gradle.properties` on next `flutter run` / `flutter build apk`
- Plugins that still apply KGP keep working through a temporary KGP-on-AGP-9 shim

These shims will be removed in a later release. See `references/agp-9-kotlin-migration.md` for full step-by-step migration.

---

## 8. Page transition builders reorganization

Source: <https://docs.flutter.dev/release/breaking-changes/decouple-page-transition-builders>

`CupertinoPageTransitionsBuilder` moved from `package:flutter/material.dart` to `package:flutter/cupertino.dart`.

If a project uses `CupertinoPageTransitionsBuilder` and only imports `material.dart`, the build now fails. Add the cupertino import.

Before:

```dart
import 'package:flutter/material.dart';

final pageTransitionsTheme = PageTransitionsTheme(
  builders: {
    TargetPlatform.android: ZoomPageTransitionsBuilder(),
    TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
  },
);
```

After:

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

final pageTransitionsTheme = PageTransitionsTheme(
  builders: {
    TargetPlatform.android: ZoomPageTransitionsBuilder(),
    TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
  },
);
```

No code change beyond the import. Projects already importing `cupertino.dart` are unaffected.

For reference, the other transition builders live in Material:

| Builder | Library |
|---|---|
| `FadeUpwardsPageTransitionsBuilder` | material |
| `OpenUpwardsPageTransitionsBuilder` | material |
| `ZoomPageTransitionsBuilder` | material (Material 3 default) |
| `PredictiveBackPageTransitionsBuilder` | material (Android predictive back) |
| `CupertinoPageTransitionsBuilder` | cupertino (moved in 3.44) |

---

## 9. `plugin_ffi` template deprecated

Sources:
- PR <https://github.com/flutter/flutter/pull/181588>
- Tracking issue <https://github.com/flutter/flutter/issues/131209>
- Native code binding docs <https://docs.flutter.dev/platform-integration/bind-native-code>

`flutter create --template=plugin_ffi` is deprecated in 3.44. Replacement:

- `flutter create --template=package_ffi` - recommended for binding to native code via `dart:ffi` (since Flutter 3.38). Uses build hooks (`build.dart`), no OS-specific build files, works in Dart standalone as well.
- `flutter create --template=plugin` - if the project genuinely needs the Flutter Plugin API or to bundle Google Play Services runtime on Android.

Migration: re-create the plugin/package with the new template and port sources. Native assets work removes the previous boilerplate per-OS, so there is no automated migration - the project structure differs.

## 10. `--web-hot-reload` CLI flag removed

Sources:
- Introduction in Flutter 3.32: <https://blog.flutter.dev/whats-new-in-flutter-3-32-40c1086bab6e>
- Hot reload general docs: <https://docs.flutter.dev/tools/hot-reload>

Web hot reload was introduced in Flutter 3.32 as an opt-in feature behind the `--web-hot-reload` flag. In Flutter 3.44, web hot reload is the default behaviour and the flag is removed.

Migration: delete the flag from any `flutter run --web-hot-reload ...` invocations, CI scripts, and IDE run configs.

## Cross-cutting notes

- Two of the eight core breaking changes (`onReorder` and `RawMenuAnchor` close order) explicitly do NOT support `dart fix` - manual changes required.
- The `ListTile` colour warning is debug-only; it does not break production builds but surfaces an actual rendering bug.
- The Kotlin built-in migration is the only one in this list that touches build config, not Dart source. The source-only changes are: `onReorder`, `setStyle`, `cacheExtent`, `IconData`, `ListTile` colour, `CupertinoPageTransitionsBuilder`, `RawMenuAnchor` close order. Tooling deprecations (`plugin_ffi` template, `--web-hot-reload` flag) are CLI-only.
