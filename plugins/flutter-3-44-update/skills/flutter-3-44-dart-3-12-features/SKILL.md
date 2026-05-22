---
name: flutter-3-44-dart-3-12-features
description: This skill should be used when the user asks to "private named parameter", "primary constructor", "CupertinoMenuAnchor", "Cupertino menu", "MenuAnchor animated", "SubmenuButton hoverOpenDelay", "iOS-style input border", "ShapedInputBorder", "RoundedSuperellipseBorder", "CupertinoFocusHalo", "list tile statesController", "ExpansibleController toggle", "ScrollCacheExtent", "CarouselView onIndexChanged", "carousel leading item", "CupertinoSheetRoute scrollableBuilder", "MediaQueryData displayCornerRadii", "FragmentShader getUniformFloat", "autoPlayAnimatedImages", "deterministicCursor", or wants to write new code with APIs introduced in Dart 3.12 / Flutter 3.44.
version: 0.1.0
---

# Flutter 3.44 / Dart 3.12 - new features reference

Reference for syntax and APIs introduced in Dart 3.12 (Nov 2025) and Flutter 3.44 (May 2026). Use this skill when writing new code that could benefit from a feature added in this release. For upgrading an existing project to 3.44, use the sibling skill `flutter-3-44-update:flutter-migrate-to-3-44` instead.

This skill is reference-shaped. Every API name below is verified against api.flutter.dev or dart.dev. Source URLs are inline.

## Authoritative sources

| Topic | Official page |
|---|---|
| Dart 3.12 announcement | <https://dart.dev/blog/announcing-dart-3-12> |
| Flutter 3.44 announcement | <https://blog.flutter.dev/whats-new-in-flutter-3-44-b0cc1ad3c527> |
| Flutter 3.44 release notes | <https://docs.flutter.dev/release/release-notes/release-notes-3.44.0> |
| api.flutter.dev | <https://api.flutter.dev> |

Detailed catalog with sample code: `references/new-apis-catalog.md`.

## Dart 3.12 - language

### Private named initializing formals (stable)

Source: <https://dart.dev/blog/announcing-dart-3-12>.

Named constructor parameters now accept `this._field` for private fields. Previously this was a compile error.

Before:

```dart
class Hummingbird {
  final String _petName;
  final int _wingbeatsPerSecond;

  Hummingbird({required String petName, required int wingbeatsPerSecond})
    : _petName = petName,
      _wingbeatsPerSecond = wingbeatsPerSecond;
}
```

After:

```dart
class Hummingbird {
  final String _petName;
  final int _wingbeatsPerSecond;

  Hummingbird({required this._petName, required this._wingbeatsPerSecond});
}

final bird = Hummingbird(petName: 'Dash', wingbeatsPerSecond: 75);
```

Call site is unchanged. Refactor opportunity: search for `param -> _field` redirect constructors and collapse them.

### Primary constructors (experimental)

Source: <https://dart.dev/blog/announcing-dart-3-12>.

Status: experimental, `--enable-experiment=primary-constructors`. Do not ship in production - syntax may shift before stabilisation.

```dart
class Point(final int x, final int y);

class Pet {
  String name;
  new() : name = 'Fluffy';
  new withName(this.name);
}

class Dog extends Pet;
```

## Flutter 3.44 - widgets

### iOS-style menus

#### `CupertinoMenuAnchor` + `CupertinoMenuItem`

Source: <https://api.flutter.dev/flutter/cupertino/CupertinoMenuAnchor-class.html>.

Native-feeling iOS menus built on `RawMenuAnchor`. Use when a context needs a Cupertino-style popover menu and the project does not already standardise on `super_context_menu`.

#### `CupertinoFocusHalo.withRoundedSuperellipse(...)`

Source: <https://api.flutter.dev/flutter/cupertino/CupertinoFocusHalo-class.html>.

`CupertinoFocusHalo` has three named constructors:

- `CupertinoFocusHalo.withRect(...)` - rectangular halo
- `CupertinoFocusHalo.withRRect(borderRadius: ..., child: ...)` - rounded rectangular halo
- `CupertinoFocusHalo.withRoundedSuperellipse(borderRadius: ..., child: ...)` - superellipse halo (iOS squircle geometry)

```dart
CupertinoFocusHalo.withRoundedSuperellipse(
  borderRadius: BorderRadius.circular(12),
  child: ...,
)
```

### Material menus

#### `MenuAnchor.animated`

Source: <https://api.flutter.dev/flutter/material/MenuAnchor/animated.html>.

```dart
MenuAnchor(
  animated: true,
  menuChildren: [...],
  builder: (context, controller, child) => ...,
);
```

Type: `final bool`. Default `false`. Controls submenu open/close animation.

#### `SubmenuButton.hoverOpenDelay`

Source: <https://api.flutter.dev/flutter/material/SubmenuButton/hoverOpenDelay.html>.

```dart
SubmenuButton(
  hoverOpenDelay: const Duration(milliseconds: 300),
  menuChildren: [...],
  child: const Text('More'),
)
```

Type: `final Duration`. Default `Duration.zero`. Delay before opening submenu on hover.

### Input borders - iOS-style

#### `ShapedInputBorder(shape: RoundedSuperellipseBorder(...))`

Sources:
- <https://api.flutter.dev/flutter/material/ShapedInputBorder-class.html>
- <https://api.flutter.dev/flutter/painting/RoundedSuperellipseBorder-class.html>

`ShapedInputBorder` is a new `InputBorder` that accepts any `ShapeBorder` as the input outline. Combine with `RoundedSuperellipseBorder` from the painting library for iOS-style continuous-curvature corners.

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

Note: `ShapedInputBorder` has its own `borderSide` (default `const BorderSide()`). Do not set a `side:` on the inner `RoundedSuperellipseBorder` as well - that would draw two strokes.

`ShapedInputBorder` constructor:

```dart
const ShapedInputBorder({
  BorderSide borderSide = const BorderSide(),
  required ShapeBorder shape,
  double gapPadding = 4.0,
})
```

`RoundedSuperellipseBorder` constructor:

```dart
const RoundedSuperellipseBorder({
  BorderSide side = BorderSide.none,
  BorderRadiusGeometry? borderRadius,
})
```

### Sheets

#### `CupertinoSheetRoute.scrollableBuilder`

Source: <https://api.flutter.dev/flutter/cupertino/CupertinoSheetRoute/scrollableBuilder.html>.

Type: `final ScrollableWidgetBuilder?`. Builds the primary contents with a provided `ScrollController` so the sheet drag and inner scroll coordinate.

```dart
CupertinoSheetRoute(
  scrollableBuilder: (context, scrollController) => ListView(
    controller: scrollController,
    children: [...],
  ),
);
```

### Expansion

#### `ExpansibleController.toggle()`

Sources: PR #181320, <https://api.flutter.dev/flutter/widgets/ExpansibleController-class.html>, source: `packages/flutter/lib/src/widgets/expansible.dart`.

`ExpansibleController` lives in the `widgets` library. The older `ExpansionTileController` (in material) is now a `@Deprecated` typedef aliasing `ExpansibleController` (`typedef ExpansionTileController = ExpansibleController;`), so existing code keeps compiling with a deprecation warning. Use `ExpansibleController` directly in new code.

```dart
final controller = ExpansibleController();

ExpansionTile(
  controller: controller,
  title: const Text('More'),
  children: [...],
);

// later
controller.toggle();
```

Also available: `expand()`, `collapse()`, `addListener()`, `removeListener()`, `dispose()`, plus static `ExpansibleController.of(context)` and `maybeOf(context)`.

### List tiles - `statesController`

Sources:
- <https://api.flutter.dev/flutter/material/RadioListTile/statesController.html>
- <https://api.flutter.dev/flutter/material/CheckboxListTile/statesController.html>
- <https://api.flutter.dev/flutter/material/SwitchListTile/statesController.html>

All three list-tile variants accept a `final WidgetStatesController? statesController;` that controls the interactive states of the backing `ListTile`.

```dart
final statesController = WidgetStatesController();
RadioListTile(
  statesController: statesController,
  value: option,
  groupValue: selected,
  onChanged: (v) {...},
  title: const Text('Option'),
);
```

### `ExpansionTile` - `WidgetStatesController` + `AlignmentGeometry`

Sources: PRs #181238, #180814, release notes 3.44.0.

`ExpansionTile` accepts a `WidgetStatesController` for programmatic state-driven styling. `expandedAlignment` now accepts `AlignmentGeometry`.

### Scroll cache

#### `ScrollCacheExtent` - unified type

Source: <https://docs.flutter.dev/release/breaking-changes/scroll-cache-extent>.

For new code:

```dart
ListView(
  scrollCacheExtent: const ScrollCacheExtent.pixels(500),
  children: [...],
);

Viewport(
  scrollCacheExtent: const ScrollCacheExtent.viewport(0.5),
  slivers: [...],
);
```

Available on `ListView`, `GridView`, `CustomScrollView`, `Viewport`, and `PageView.scrollCacheExtent` (PR #180411).

### Carousel

Sources:
- <https://api.flutter.dev/flutter/material/CarouselView-class.html>
- <https://api.flutter.dev/flutter/material/CarouselView/onIndexChanged.html>
- <https://api.flutter.dev/flutter/material/CarouselController-class.html>

`CarouselView` constructor parameters relevant to selection:

- `onIndexChanged: ValueChanged<int>?` - fires when the leading item is completely out of view
- `onTap: ValueChanged<int>?` - fires when a child is tapped
- `controller: CarouselController?`
- `itemSnapping: bool`
- `infinite: bool` - infinite carousel scroll

`CarouselController` has `initialItem` (final, set on creation) and `leadingItem` (read-only - the current leading item index).

```dart
final controller = CarouselController(initialItem: 0);

CarouselView(
  controller: controller,
  infinite: true,
  onIndexChanged: (i) { /* leading item changed */ },
  children: [...],
);

// later
final current = controller.leadingItem; // read-only
```

> Note: there is no `CarouselView.onItemChanged` or `CarouselController.leadingIndex`. The correct names are `onIndexChanged` (on view) and `leadingItem` (on controller).

### `TabBar` - `TabBarScrollController`

Sources:
- <https://api.flutter.dev/flutter/material/TabBarScrollController-class.html>
- PR #180389, release notes 3.44.0.

`TabBarScrollController` is a new final class that extends `ScrollController`. Pass to `TabBar` for programmatic scroll control.

### Form additions

Sources: PRs #180752, #180815, release notes 3.44.0.

- `Form.clearError()` / `FormFieldState.clearError()` - clear validation errors programmatically.
- `FormState.fields` - getter for iterating registered fields.

### Other widget additions (release notes 3.44.0)

| Widget / API | PR |
|---|---|
| `SizeTransition.alignment` | #177895 |
| `AnimatedCrossFade.onEnd` | #181455 |
| `Hero` customisable animation curves | #180100 |
| `NavigationRail.mainAxisAlignment` | #183514 |
| `DropdownMenu.scrollPadding` | #183109 |
| `SimpleDialog.contentTextStyle` | #178824 |
| `Stepper.headerPadding` / `contentPadding` | #180257 |
| `ModalBottomSheet` uses `AnimationStyle` curves | #181403 |
| `ThemeMode.isDark` / `isLight` / `isSystem` | #181475 |
| `Overlay.alwaysSizeToContent` | #182009 |
| `SizedBox.square()` named constructor | #182731 |
| `RawTooltip.ignorePointer` | #182527 |
| `ProgressIndicator` accepts percentage `SemanticsValue` (engine-side rendering, no API change) | #183670 |

Detailed code samples in `references/new-apis-catalog.md`.

## Platform / engine APIs

### `MediaQueryData.displayCornerRadii` (Android)

Source: <https://api.flutter.dev/flutter/widgets/MediaQueryData/displayCornerRadii.html>.

Type: `final BorderRadius?`. Populated only on Android API 31+. Returns the radii of the display corners in logical pixels. `null` on other platforms.

```dart
final radii = MediaQuery.of(context).displayCornerRadii;
if (radii != null) {
  // hug device corners
}
```

For physical pixel values, see `FlutterView.displayCornerRadii`.

### `FragmentShader.getUniformFloat`

Source: <https://api.flutter.dev/flutter/dart-ui/FragmentShader/getUniformFloat.html>.

Returns a `UniformFloatSlot` on which `.set(double)` writes the value. Optional second parameter is the component offset within the bound uniform.

```dart
import 'dart:ui' as ui;

void updateShader(ui.FragmentShader shader) {
  shader.getUniformFloat('uScale').set(1.234);
  shader.getUniformFloat('uColor', 0).set(1.0); // r
  shader.getUniformFloat('uColor', 1).set(0.0); // g
  shader.getUniformFloat('uColor', 2).set(0.0); // b
}
```

## Accessibility

### `AccessibilityFeatures.autoPlayAnimatedImages`

Source: <https://api.flutter.dev/flutter/dart-ui/AccessibilityFeatures-class.html>.

Type: `bool`. Whether the platform allows auto-playing animated images. Check before auto-playing GIFs or other animated content.

```dart
final features = MediaQuery.of(context).accessibilityFeatures;
if (!features.autoPlayAnimatedImages) {
  // freeze animation on first frame
}
```

### `AccessibilityFeatures.deterministicCursor`

Source: <https://api.flutter.dev/flutter/dart-ui/AccessibilityFeatures-class.html>.

Type: `bool`. The platform is requesting a deterministic (non-blinking) cursor in editable text fields. This is the actual property name - the announcement blog referred to it as `preferNonBlinkingCursor`, but the real property is `deterministicCursor`.

### `ProgressIndicator` percentage `SemanticsValue`

Source: PR #183670, release notes 3.44.0.

Screen readers now announce percentage strings (`"50%"`) supplied in `SemanticsValue` as percentages rather than literal text. Engine-side fix, no API surface change.

## Quick reference table

| Need | Use |
|---|---|
| Private field in named constructor (Dart 3.12 stable) | `{required this._field}` |
| iOS-style menu | `CupertinoMenuAnchor` + `CupertinoMenuItem` |
| Animated material menu | `MenuAnchor(animated: true, ...)` |
| Hover delay on submenu | `SubmenuButton(hoverOpenDelay: ...)` |
| iOS-style input border | `ShapedInputBorder(shape: RoundedSuperellipseBorder(...))` |
| iOS focus ring (squircle) | `CupertinoFocusHalo.withRoundedSuperellipse(...)` |
| iOS sheet with scroll coordination | `CupertinoSheetRoute(scrollableBuilder: (ctx, ctrl) => ...)` |
| Toggle expansion programmatically | `ExpansibleController.toggle()` (`ExpansionTileController` is a `@Deprecated` typedef for it - old code still works) |
| Drive list-tile state externally | pass `WidgetStatesController` to `RadioListTile` / `CheckboxListTile` / `SwitchListTile` / `ExpansionTile` |
| Cache extent on scroll widgets | `scrollCacheExtent: ScrollCacheExtent.pixels(...)` or `.viewport(...)` |
| Carousel leading item | `CarouselController(initialItem: 0)` and read `controller.leadingItem` |
| Carousel index change callback | `CarouselView(onIndexChanged: (i) => ...)` |
| Carousel infinite scroll | `CarouselView(infinite: true, ...)` |
| TabBar with custom scroll controller | `TabBar(scrollController: TabBarScrollController(), controller: tabController, ...)` |
| Square `SizedBox` | `SizedBox.square(dimension: 48, child: ...)` |
| Theme mode boolean inspection | `themeMode.isDark` / `.isLight` / `.isSystem` |
| Overlay sized to content | `Overlay(alwaysSizeToContent: true, ...)` |
| Form-wide error clearing | `formKey.currentState!.clearError()` |
| Android display corner radii | `MediaQuery.of(context).displayCornerRadii` (API 31+) |
| Fragment shader uniform by name | `shader.getUniformFloat('name').set(value)` |
| Respect "pause animated images" preference | `MediaQuery.of(context).accessibilityFeatures.autoPlayAnimatedImages` |
| Respect "non-blinking cursor" preference | `MediaQuery.of(context).accessibilityFeatures.deterministicCursor` |

## Integration with sibling skills

- `flutter-3-44-update:flutter-migrate-to-3-44` - run that one when upgrading an existing project (AGP 9.0 / built-in Kotlin, Swift Package Manager, UIScene, source-level deprecations). This skill is for new code only.

## Anti-patterns

- **Using primary constructors in production code.** Experimental in 3.12 - the syntax may shift. Use stable `this._field` form instead.
- **Picking `CupertinoMenuAnchor` for every menu without checking project context.** A project already standardised on `super_context_menu` does not need a second menu library for symmetry.
- **Bulk-renaming `cacheExtent` to `scrollCacheExtent` by sed.** Type change too - the new property takes a `ScrollCacheExtent` object, not a `double`. Use the correct factory.
- **Auto-playing animated content without checking `accessibilityFeatures.autoPlayAnimatedImages`.** Respect the user preference on 3.44 projects even if the prior code did not.
- **Searching for `RoundedSuperellipseInputBorder` (does not exist).** The class is `RoundedSuperellipseBorder` (painting library) - used as the `shape` parameter on `ShapedInputBorder`.
- **Searching for `CarouselView.onItemChanged`, `CarouselView.leadingItem`, or `CarouselController.leadingIndex` (none of these exist).** The correct names are `CarouselView.onIndexChanged` (callback) and `CarouselController.leadingItem` (read-only property).
- **Passing `TabBarScrollController` to `TabBar.controller` (will not compile).** `TabBar.controller` accepts `TabController`. `TabBarScrollController` goes into the separate `TabBar.scrollController` parameter.
- **Treating this skill as a checklist.** It is a reference. Pick the sections that match the task. Do not introduce every new API in one PR.

## Suggested next

After applying a feature from this skill:

- **Recommended:** run `dart analyze` and `flutter test`, then move on - the change should be a small, local addition.
- **Alternatives:**
  - `flutter-3-44-update:flutter-migrate-to-3-44` if introducing the feature surfaced a deprecation warning that the project needs to address.
- **Stop** if the change is self-contained and verified.

Wait for the user's choice. Do not chain into migration work unprompted.
