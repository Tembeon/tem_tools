# Flutter 3.44 - new APIs catalog (verified)

Every entry verified against `api.flutter.dev` or `docs.flutter.dev`. URLs are inline.

## Dart 3.12 - language

- **Private named initializing formals** (stable) - <https://dart.dev/blog/announcing-dart-3-12>
- **Primary constructors** (experimental, `--enable-experiment=primary-constructors`) - <https://dart.dev/blog/announcing-dart-3-12>

## Cupertino additions

### `CupertinoMenuAnchor` + `CupertinoMenuItem`

Source: <https://api.flutter.dev/flutter/cupertino/CupertinoMenuAnchor-class.html>.

Native-feeling iOS menus built on `RawMenuAnchor`.

### `CupertinoFocusHalo` named constructors

Source: <https://api.flutter.dev/flutter/cupertino/CupertinoFocusHalo-class.html>.

Three shape choices via named constructors:

```dart
CupertinoFocusHalo.withRect(child: ...);
CupertinoFocusHalo.withRRect(borderRadius: ..., child: ...);
CupertinoFocusHalo.withRoundedSuperellipse(borderRadius: ..., child: ...);
```

### `CupertinoSheetRoute.scrollableBuilder`

Source: <https://api.flutter.dev/flutter/cupertino/CupertinoSheetRoute/scrollableBuilder.html>.

```dart
final ScrollableWidgetBuilder? scrollableBuilder;
```

Builds the primary contents with a provided `ScrollController` so the sheet drag and inner scroll coordinate.

```dart
CupertinoSheetRoute(
  scrollableBuilder: (context, scrollController) => ListView(
    controller: scrollController,
    children: [...],
  ),
);
```

## Material - menus

### `MenuAnchor.animated`

Source: <https://api.flutter.dev/flutter/material/MenuAnchor/animated.html>.

`final bool animated` defaulting to `false`. Controls submenu open/close animation.

### `SubmenuButton.hoverOpenDelay`

Source: <https://api.flutter.dev/flutter/material/SubmenuButton/hoverOpenDelay.html>.

`final Duration hoverOpenDelay` defaulting to `Duration.zero`. Delay before opening submenu on hover.

## Material - input borders

### `ShapedInputBorder`

Source: <https://api.flutter.dev/flutter/material/ShapedInputBorder-class.html>.

```dart
const ShapedInputBorder({
  BorderSide borderSide = const BorderSide(),
  required ShapeBorder shape,
  double gapPadding = 4.0,
})
```

Accepts any `ShapeBorder` as the input outline. Maintains the floating-label gap behaviour.

### `RoundedSuperellipseBorder` (painting library)

Source: <https://api.flutter.dev/flutter/painting/RoundedSuperellipseBorder-class.html>.

```dart
const RoundedSuperellipseBorder({
  BorderSide side = BorderSide.none,
  BorderRadiusGeometry? borderRadius,
})
```

iOS squircle geometry as a `ShapeBorder`. Combine with `ShapedInputBorder` for iOS-style input borders:

```dart
TextField(
  decoration: InputDecoration(
    border: ShapedInputBorder(
      shape: RoundedSuperellipseBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),
  ),
);
```

## Material - list tiles `statesController`

All three list-tile variants accept a `WidgetStatesController` for programmatic interactive-state control:

- `RadioListTile.statesController` - <https://api.flutter.dev/flutter/material/RadioListTile/statesController.html>
- `CheckboxListTile.statesController` - <https://api.flutter.dev/flutter/material/CheckboxListTile/statesController.html>
- `SwitchListTile.statesController` - <https://api.flutter.dev/flutter/material/SwitchListTile/statesController.html>

All three signatures: `final WidgetStatesController? statesController;`.

`ExpansionTile` also got a `statesController` (PR #181238) plus `expandedAlignment` now accepts `AlignmentGeometry` (PR #180814).

## Material - other widget additions

### `SizeTransition.alignment`

Source: PR #177895.

```dart
SizeTransition(
  sizeFactor: animation,
  alignment: Alignment.topCenter,
  child: ...,
)
```

### `AnimatedCrossFade.onEnd`

Source: PR #181455.

### `Hero` - custom animation curves

Source: PR #180100, <https://api.flutter.dev/flutter/widgets/Hero-class.html>.

Two new parameters: `curve` (forward direction, default `Curves.fastOutSlowIn`) and `reverseCurve` (reverse direction).

```dart
Hero(
  tag: 'avatar',
  curve: Curves.easeInOutCubic,
  reverseCurve: Curves.easeOutBack,
  child: ...,
)
```

### `ExpansibleController.toggle()`

Sources: PR #181320, source `packages/flutter/lib/src/widgets/expansible.dart`, <https://api.flutter.dev/flutter/widgets/ExpansibleController-class.html>.

`ExpansibleController` (widgets library) is the new canonical controller. The older `ExpansionTileController` (in material) is now `@Deprecated` and a typedef aliasing `ExpansibleController` (`typedef ExpansionTileController = ExpansibleController;`). Existing `ExpansionTileController()` calls keep working with a deprecation warning.

Methods: `toggle()`, `expand()`, `collapse()`, plus static `of(context)` / `maybeOf(context)`.

### `NavigationRail.mainAxisAlignment`

Source: PR #183514.

### `DropdownMenu.scrollPadding`

Source: PR #183109.

### `SimpleDialog.contentTextStyle`

Source: PR #178824.

### `Stepper.headerPadding` and `contentPadding`

Source: PR #180257.

### `ModalBottomSheet` - AnimationStyle curves

Source: PR #181403. Uses `AnimationStyle.curve` and `AnimationStyle.reverseCurve`.

### `ThemeMode` - boolean getters

Source: PR #181475.

```dart
themeMode.isDark
themeMode.isLight
themeMode.isSystem
```

### `Overlay.alwaysSizeToContent`

Source: PR #182009.

### `SizedBox.square()`

Source: PR #182731.

```dart
SizedBox.square(dimension: 48, child: ...);
```

### `RawTooltip.ignorePointer`

Source: PR #182527.

### `ProgressIndicator` - percentage in SemanticsValue

Source: PR #183670.

Engine-side rendering fix. Screen readers now announce `"50%"` (and similar percentage strings) in `SemanticsValue` as percentages rather than literal text. No API surface change.

### `Form.clearError` / `FormFieldState.clearError` / `FormState.fields`

Sources: PRs #180752, #180815.

```dart
final formKey = GlobalKey<FormState>();

// later, on the form
formKey.currentState!.clearError();

// or per field
formFieldKey.currentState!.clearError();

// iterate over fields
for (final field in formKey.currentState!.fields) {
  // field is a FormFieldState
}
```

### `TabBarScrollController`

Source: <https://api.flutter.dev/flutter/material/TabBarScrollController-class.html>. PR #180389.

Final class extending `ScrollController`. Pass to `TabBar.scrollController` (NOT `TabBar.controller` - that one takes `TabController`).

```dart
final tabController = TabController(length: 3, vsync: this);
final scrollController = TabBarScrollController();

TabBar(
  controller: tabController,
  scrollController: scrollController,
  tabs: [...],
);
```

## Material - `CarouselView` / `CarouselController`

Sources:
- <https://api.flutter.dev/flutter/material/CarouselView-class.html>
- <https://api.flutter.dev/flutter/material/CarouselController-class.html>
- PRs #180667, #175710.

`CarouselView` constructor parameters relevant to selection:

| Parameter | Type | Notes |
|---|---|---|
| `onIndexChanged` | `ValueChanged<int>?` | Fires when leading item is completely out of view |
| `onTap` | `ValueChanged<int>?` | Fires when a child is tapped |
| `controller` | `CarouselController?` | Manages first fully visible item |
| `itemSnapping` | `bool` | Snap to next/previous items |
| `infinite` | `bool` | Infinite scroll |

`CarouselController` properties:

- `initialItem` - final, set on construction
- `leadingItem` - read-only, current leading item index

```dart
final controller = CarouselController(initialItem: 0);

CarouselView(
  controller: controller,
  infinite: true,
  onIndexChanged: (i) { /* leading item changed */ },
  children: [...],
);
```

> Names to NOT use (do not exist): `CarouselView.onItemChanged`, `CarouselView.leadingItem`, `CarouselController.leadingIndex`.

## Scroll cache

### `ScrollCacheExtent` - unified type

Source: <https://docs.flutter.dev/release/breaking-changes/scroll-cache-extent>.

Replaces deprecated `cacheExtent` + `cacheExtentStyle` pair. Two factories:

```dart
ScrollCacheExtent.pixels(double)
ScrollCacheExtent.viewport(double)
```

For new code:

```dart
ListView(scrollCacheExtent: const ScrollCacheExtent.pixels(500), ...);
Viewport(scrollCacheExtent: const ScrollCacheExtent.viewport(0.5), ...);
```

Available on `ListView`, `GridView`, `CustomScrollView`, `Viewport`, and `PageView.scrollCacheExtent` (PR #180411).

## Platform / engine

### `MediaQueryData.displayCornerRadii`

Source: <https://api.flutter.dev/flutter/widgets/MediaQueryData/displayCornerRadii.html>.

```dart
final BorderRadius? displayCornerRadii;
```

Android API 31+ only. Returns the radii of the display corners in logical pixels. `null` on other platforms.

For physical pixel values: `FlutterView.displayCornerRadii`.

### `FragmentShader.getUniformFloat`

Source: <https://api.flutter.dev/flutter/dart-ui/FragmentShader/getUniformFloat.html>.

```dart
UniformFloatSlot getUniformFloat(String name, [int? index])
```

Returns a `UniformFloatSlot`. Call `.set(double)` to write the value. Optional second parameter is component offset (e.g., `0` for `.r`, `1` for `.g`, `2` for `.b`).

```dart
import 'dart:ui' as ui;

void updateShader(ui.FragmentShader shader) {
  shader.getUniformFloat('uScale').set(1.234);
  shader.getUniformFloat('uColor', 0).set(1.0);
  shader.getUniformFloat('uColor', 1).set(0.0);
  shader.getUniformFloat('uColor', 2).set(0.0);
}
```

## Accessibility - `AccessibilityFeatures`

Source: <https://api.flutter.dev/flutter/dart-ui/AccessibilityFeatures-class.html>.

### `autoPlayAnimatedImages`

```dart
final bool autoPlayAnimatedImages;
```

Whether the platform allows auto-playing animated images. Check before auto-playing GIFs.

### `deterministicCursor`

```dart
final bool deterministicCursor;
```

The platform is requesting a deterministic (non-blinking) cursor in editable text fields. The 3.44 announcement blog called this `preferNonBlinkingCursor` - the real property name is `deterministicCursor`.

```dart
final features = MediaQuery.of(context).accessibilityFeatures;
if (!features.autoPlayAnimatedImages) { /* freeze GIF */ }
if (features.deterministicCursor) { /* non-blinking cursor */ }
```

## Cross-reference: breaking changes related to widgets

These entries are NOT additions - they are breaking changes that affect widget code. Full migration text lives in the sibling skill `flutter-3-44-update:flutter-migrate-to-3-44` at `plugins/flutter-3-44-update/skills/flutter-migrate-to-3-44/references/breaking-changes-catalog.md`.

- `IconData` is now `final` (cannot extend/implement). PRs #181345, #181849. Migration page: <https://docs.flutter.dev/release/breaking-changes/icondata-class-marked-final>.
- `WidgetStatesConstraint` is now a `mixin` (PR #181704). Code that did `extends WidgetStatesConstraint` no longer compiles.
- `WidgetTesterCallback` parameter renamed from `widgetTester` to `tester` (PR #180944).
- `DropdownMenu` non-nullable change was REVERTED before 3.44 shipped (PR #181074). Existing nullable usages still compile.
