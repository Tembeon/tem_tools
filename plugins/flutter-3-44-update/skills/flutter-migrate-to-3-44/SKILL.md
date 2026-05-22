---
name: flutter-migrate-to-3-44
description: This skill should be used when the user asks to "upgrade to Flutter 3.44", "migrate to SwiftPM", "fix AGP 9.0 build error", "remove KGP", "Kotlin Gradle Plugin error after Flutter upgrade", "adopt UIScene", "fix deprecated ReorderableListView.onReorder", "replace cacheExtent and cacheExtentStyle", "fix IconData extends compile error", "fix TextInputConnection.setStyle deprecation", "fix RawMenuAnchor close order", "CupertinoPageTransitionsBuilder not found", "ListTile color warning in debug", "plugin_ffi template deprecated", "--web-hot-reload removed", or upgrades an existing Flutter project to 3.44 with platform-config changes and deprecated-API replacements.
version: 0.1.0
---

# Flutter 3.44 migration

Workflow for upgrading an existing Flutter project to Flutter 3.44 (May 2026). Two categories of work:

1. **Platform configuration** - Android (AGP 9.0 built-in Kotlin) and iOS/macOS (Swift Package Manager default, UIScene lifecycle).
2. **Source-level deprecations** - eight breaking changes documented at `docs.flutter.dev/release/breaking-changes` plus two CLI-tool deprecations (`plugin_ffi` template, `--web-hot-reload` flag).

Every claim in this skill is backed by a link to the official Flutter docs page or the underlying platform docs (Android Studio, Apple). When a code sample is hand-written rather than copied from official docs, the surrounding text says so.

## When to use

Trigger when:

- Bumping `environment: flutter:` or `sdk:` constraint to 3.44+
- Build breaks after `flutter upgrade` with AGP / KGP / Kotlin errors
- `dart analyze` reports new deprecation warnings after SDK bump
- iOS/macOS project still on CocoaPods and team wants to adopt the new default
- Apple is about to enforce UIScene API and the project still uses pre-UIScene lifecycle
- Plugin author needs to publish SwiftPM-compatible plugin

Skip when:

- Project is already on 3.44+ and clean (use `flutter-3-44-update:flutter-3-44-dart-3-12-features` for new code)
- Project pins an older Flutter intentionally (do not force-upgrade)

## Authoritative sources

| Topic | Official page |
|---|---|
| Breaking changes index | <https://docs.flutter.dev/release/breaking-changes> |
| Release notes 3.44.0 | <https://docs.flutter.dev/release/release-notes/release-notes-3.44.0> |
| AGP 9.0 (Android) | <https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin> |
| SwiftPM | <https://docs.flutter.dev/packages-and-plugins/swift-package-manager> |
| UIScene | <https://docs.flutter.dev/release/breaking-changes/uiscenedelegate> |

If a fact in this skill conflicts with one of these pages, the page is correct.

## Breaking changes shipped in 3.44

Eight breaking changes on the `docs.flutter.dev` index plus two CLI-tool deprecations.

| Change | Source |
|---|---|
| RawMenuAnchor close order changed | <https://docs.flutter.dev/release/breaking-changes/raw-menu-anchor-close-order> |
| `ReorderableListView.onReorder` -> `onReorderItem` | <https://docs.flutter.dev/release/breaking-changes/deprecate-onreorder-callback> |
| `TextInputConnection.setStyle` -> `updateStyle` | <https://docs.flutter.dev/release/breaking-changes/deprecate-text-input-connection-set-style> |
| `cacheExtent` + `cacheExtentStyle` -> `scrollCacheExtent: ScrollCacheExtent` | <https://docs.flutter.dev/release/breaking-changes/scroll-cache-extent> |
| `IconData` is now `final` (no extends/implements) | <https://docs.flutter.dev/release/breaking-changes/icondata-class-marked-final> |
| `ListTile` debug warning in colored wrappers | <https://docs.flutter.dev/release/breaking-changes/list-tile-color-warning> |
| Migrate Android projects to built-in Kotlin | <https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin> |
| `CupertinoPageTransitionsBuilder` moved to cupertino.dart | <https://docs.flutter.dev/release/breaking-changes/decouple-page-transition-builders> |
| `plugin_ffi` template deprecated -> `package_ffi` | <https://github.com/flutter/flutter/pull/181588> |
| `--web-hot-reload` CLI flag removed | (web hot reload became default in 3.44) |

Full migration text, before/after samples, and edge cases are in `references/breaking-changes-catalog.md`.

## Workflow

Copy this checklist into the conversation to track progress.

### Task progress

- [ ] **Step 0 - Prepare.** Capture baseline and audit plugin compatibility:
  ```bash
  flutter --version > .pre-migration-version.txt
  git status                                    # confirm working tree clean
  git checkout -b chore/flutter-3-44-migration
  flutter pub outdated                          # red rows = plugins without 3.44-compatible release
  ```
  If a critical plugin has no 3.44-compatible release, choose one of: (a) pin Flutter to the highest version that plugin supports and wait, (b) fork the plugin and apply the migration upstream, (c) replace the plugin. Do not silently bump - the build will surface failures later in a less useful place.
- [ ] **Step 1 - Bump SDK constraints.** Update `pubspec.yaml` `environment:` (Dart SDK `>=3.10.0 <4.0.0`, Flutter `>=3.44.0`) and any CI Flutter version pin. Run `flutter pub get`. If the project's existing constraint uses an inclusive upper bound (e.g., `<=4.0.0`), keep that style - do not introduce drive-by changes.
- [ ] **Step 2 - Android: migrate to built-in Kotlin (AGP 9.0).** Remove `kotlin-android` plugin from gradle files, replace `kotlinOptions { }` with top-level `kotlin { compilerOptions { } }`, delete auto-added opt-out flags. For multi-module projects (feature modules under `android/`), repeat the per-module steps for each one. If the project uses `kotlin-kapt` (Hilt / Drift / Floor / Moor codegen), see the "kotlin-kapt" subsection - migrate to KSP or `com.android.legacy-kapt`. Details: `references/agp-9-kotlin-migration.md`.
- [ ] **Step 3 - iOS/macOS: enable Swift Package Manager.** Run `flutter config --enable-swift-package-manager`, then a single `flutter build ios --debug --no-codesign` (or `flutter run`) triggers auto-migration. Details: `references/swiftpm-migration.md`. Skip for add-to-app projects (SwiftPM is not supported there).
- [ ] **Step 4 - iOS: adopt UIScene lifecycle.** Before running the auto-migrator, inventory `AppDelegate` for customisations: push notifications setup (APNS / Firebase), deep-link handlers (`application:openURL:options:`), `application:continueUserActivity:`, background fetch, shortcut items, state restoration. Auto-migration runs on `flutter run` / `flutter build ios` and only handles an unmodified `AppDelegate` - look for `Finished migration to UIScene lifecycle`. For customised `AppDelegate`, follow `references/uiscene-migration.md` and port each item to `SceneDelegate` or `didInitializeImplicitFlutterEngine`.
- [ ] **Step 5 - Plugin authors only (skip if not authoring a plugin): update Package.swift and pubspec.yaml.** SDK floors differ by what the plugin uses:
  - Plugin adopts SwiftPM `FlutterFramework` dependency: `sdk: ^3.11.0`, `flutter: ">=3.41.0"` (see `references/swiftpm-migration.md`).
  - Plugin adopts UIScene `FlutterSceneLifeCycleDelegate` only (no SwiftPM): `sdk: ^3.10.0`, `flutter: ">=3.38.0"` (see `references/uiscene-migration.md`).
  - Plugin adopts both: use the SwiftPM floor (`^3.11.0` / `>=3.41.0`) - it is the stricter of the two.
  Add `FlutterFramework` dependency in `Package.swift` (SwiftPM). Add `FlutterSceneLifeCycleDelegate` adoption and `registrar.addSceneDelegate(instance)` (UIScene).
- [ ] **Step 6 - Replace deprecated source APIs and CLI invocations.** Work through the table below. Audit CI scripts, IDE run configs, Makefiles, and `justfile`s for the removed CLI flags. Details for each in `references/breaking-changes-catalog.md`.
- [ ] **Step 7 - Run `dart analyze` and `flutter test`.** Address remaining warnings. Re-run until clean.
- [ ] **Step 8 - Build per platform.** `flutter build apk --debug`, `flutter build ios --no-codesign --debug`, and any other platforms the project supports (`macos`, `web`, `linux`, `windows`). Run `flutter clean` between platform-config changes to avoid stale Gradle caches.

### Rollback per step

`git checkout` alone is rarely enough - Gradle, CocoaPods, and pub caches survive a revert. Use the matching command per step.

| Step | Rollback commands |
|---|---|
| 1 (SDK bump) | `git checkout -- pubspec.yaml pubspec.lock && flutter pub get` |
| 2 (AGP/Kotlin) | `git checkout -- android/ && flutter clean` |
| 3 (SwiftPM) | `flutter config --no-enable-swift-package-manager && git checkout -- ios/ macos/ && flutter clean && rm -rf ios/Pods ios/Podfile.lock` |
| 4 (UIScene) | `git checkout -- ios/`. Fast workaround for a broken UIScene boot: prefix `Application Scene Manifest` key in `ios/Runner/Info.plist` with `_` (becomes `_UIApplicationSceneManifest`) to disable UIScene without reverting code (see `references/uiscene-migration.md`). |
| 5 (plugin) | `git checkout -- <plugin>/pubspec.yaml <plugin>/Package.swift <plugin>/ios/` |
| 6 (source) | `git diff` to inspect, `git checkout -- <file>` per file |

## Step 2 - quick reference for AGP 9.0

Full details: `references/agp-9-kotlin-migration.md`.

Symptom of unmigrated build:

```
Failed to apply plugin 'org.jetbrains.kotlin.android'.
  > Cannot add extension with name 'kotlin', as there is an extension already registered with that name.
```

Flutter 3.44 auto-writes opt-out flags to `android/gradle.properties` on first build:

```properties
android.newDsl=false
android.builtInKotlin=false
```

These keep existing projects building during the upgrade window. The migration goal is to delete those flags by removing the legacy KGP application.

Module-level `android/app/build.gradle.kts` - remove the kotlin plugin and the `kotlinOptions` block, add a top-level `kotlin { compilerOptions { } }` block:

```kotlin
// before
plugins {
    id("com.android.application")
    id("kotlin-android")
}

android {
    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }
}

// after
plugins {
    id("com.android.application")
}

android { ... }

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}
```

Then delete `android.newDsl=false` and `android.builtInKotlin=false` from `gradle.properties` and verify `flutter run`.

> Add-to-app: Flutter migrator does not run on native Android host apps. Add the opt-out flags manually and follow the same removal sequence.

## Step 3 - quick reference for SwiftPM

Full details: `references/swiftpm-migration.md`.

```bash
flutter config --enable-swift-package-manager
flutter build ios --debug --no-codesign
```

The Flutter CLI prints `Adding Swift Package Manager integration...` and modifies `ios/Runner.xcodeproj/project.pbxproj` plus the scheme. CocoaPods continues as fallback for plugins that have not migrated.

> Add-to-app is not supported by SwiftPM. Tracking: <https://github.com/flutter/flutter/issues/146957>. Add-to-app projects stay on CocoaPods.

If auto-migration fails, file an issue and follow the manual steps in `references/swiftpm-migration.md`.

## Step 4 - quick reference for UIScene

Full details: `references/uiscene-migration.md`.

Auto-migration triggers on `flutter run` / `flutter build ios` when `AppDelegate` is unmodified. Success log: `Finished migration to UIScene lifecycle`.

Known auto-migration limitation: fails when `UIKit` is imported before `Flutter` in `AppDelegate`. Reorder to `import Flutter` then `import UIKit` and re-run.

For customised `AppDelegate`, the migration moves `GeneratedPluginRegistrant.register` (and method channels, platform views) from `application:didFinishLaunchingWithOptions:` to `didInitializeImplicitFlutterEngine` declared by `FlutterImplicitEngineDelegate`. It also adds `UIApplicationSceneManifest` to `Info.plist`. See the reference file for full code.

Apple deadline: "In the release following iOS 26, any UIKit app built with the latest SDK will be required to use the UIScene lifecycle, otherwise it will not launch." Source: <https://developer.apple.com/documentation/technotes/tn3187-migrating-to-the-uikit-scene-based-life-cycle>.

## Step 6 - source-level deprecation table

Every replacement below comes from the per-change migration page in `docs.flutter.dev`. Verified signatures and code samples in `references/breaking-changes-catalog.md`.

| Old API | New API | Source |
|---|---|---|
| `ReorderableListView.onReorder` | `ReorderableListView.onReorderItem` (same signature `(int, int)`, but `newIndex` is now pre-corrected - remove the `-1` adjustment) | [deprecate-onreorder-callback](https://docs.flutter.dev/release/breaking-changes/deprecate-onreorder-callback) |
| `TextInputConnection.setStyle(...)` | `TextInputConnection.updateStyle(TextInputStyle(...))` | [deprecate-text-input-connection-set-style](https://docs.flutter.dev/release/breaking-changes/deprecate-text-input-connection-set-style) |
| `cacheExtent: double` + `cacheExtentStyle: CacheExtentStyle` on `ListView`/`GridView`/`CustomScrollView`/`Viewport` | `scrollCacheExtent: ScrollCacheExtent.pixels(...)` or `.viewport(...)` | [scroll-cache-extent](https://docs.flutter.dev/release/breaking-changes/scroll-cache-extent) |
| `enum implements IconData` or `class extends IconData` | Wrapper class with `static const` `IconData` instances + custom `Icon`-rendering widget | [icondata-class-marked-final](https://docs.flutter.dev/release/breaking-changes/icondata-class-marked-final) |
| `Container(color: ..., child: ListTile(...))` (debug warning, not compile error) | Move colour to `Material` ancestor, or wrap `ListTile` in transparent `Material` | [list-tile-color-warning](https://docs.flutter.dev/release/breaking-changes/list-tile-color-warning) |
| `CupertinoPageTransitionsBuilder` from `material.dart` | Add `import 'package:flutter/cupertino.dart';` (class moved there) | [decouple-page-transition-builders](https://docs.flutter.dev/release/breaking-changes/decouple-page-transition-builders) |
| `RawMenuAnchor` with manual `controller.closeChildren()` in `onCloseRequested` | Remove the manual call (framework does it); audit `onClose` for new bottom-up order | [raw-menu-anchor-close-order](https://docs.flutter.dev/release/breaking-changes/raw-menu-anchor-close-order) |
| `flutter create --template=plugin_ffi` | `flutter create --template=package_ffi` (preferred) or `--template=plugin` if Flutter Plugin API or Google Play Services components are needed | [PR #181588](https://github.com/flutter/flutter/pull/181588), [tracking #131209](https://github.com/flutter/flutter/issues/131209) |
| `--web-hot-reload` CLI flag | Remove the flag - hot reload on web is now default behaviour | (removed in 3.44; was introduced in 3.32 as opt-in) |

`dart fix` automation is NOT supported for the `onReorder` -> `onReorderItem` change (semantic shift in `newIndex`) or for the `RawMenuAnchor` close order change. Manual updates required for those two.

## Step 8 - verification commands

```bash
dart analyze
flutter test
flutter build apk --debug
flutter build ios --no-codesign --debug
```

Add any other platforms the project supports (macos, web, linux, windows).

## Anti-patterns

- **Skipping Step 1 (SDK bump).** Without it, deprecation warnings hide behind compile errors and the migration order falls apart.
- **Bulk-renaming `onReorder` to `onReorderItem` with sed.** Same signature, but `newIndex` semantics changed. A blind rename can re-introduce the off-by-one bug the new API was designed to remove. Read each call site.
- **Keeping `android.builtInKotlin=false` "for safety".** It is a temporary opt-out, not a destination. AGP 10.0 will not honor it. Migrate properly.
- **Running `flutter config --enable-swift-package-manager` in an add-to-app project.** SwiftPM does not support add-to-app yet (issue #146957). Stay on CocoaPods for those.
- **Force-migrating a customised `AppDelegate` by overwriting it with the Flutter template.** Customisations (push notifications setup, deep links, state restoration) must be carried into `SceneDelegate` or `didInitializeImplicitFlutterEngine`. Do not lose them.
- **Patching plugins downstream instead of upstreaming.** If a plugin lacks SwiftPM `Package.swift` or `FlutterSceneLifeCycleDelegate` adoption, file an issue and send a PR. Private forks rot.
- **Treating `dart analyze` clean as full verification.** UIScene and SwiftPM changes surface only at build or runtime. Run Step 8 builds.
- **Trying to apply `dart fix` to the `onReorder` or `RawMenuAnchor` close-order migrations.** Both are explicitly unsupported by `dart fix` per the official docs. Manual edits only.

## Suggested next

Commit the migration in logical chunks - Android config separate from iOS config separate from source-level deprecation fixes - so review is easier. New feature adoption should not be bundled with the upgrade PR.

- **Recommended:** `flutter-3-44-update:flutter-3-44-dart-3-12-features` if the team now wants to adopt APIs that were not safe pre-3.44.
- **Alternatives:**
  - Open a follow-up issue tracking the temporary AGP shims (`android.newDsl=false` / `android.builtInKotlin=false`) so they get removed in a later PR after broader confidence.
- **Stop** if the migration is complete, verified, and the team prefers to ship before adopting any new feature.

Wait for the user's choice. Do not auto-commit.
