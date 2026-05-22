# Swift Package Manager migration (iOS/macOS)

Sources:

- App developers: <https://docs.flutter.dev/packages-and-plugins/swift-package-manager/for-app-developers>
- Plugin authors: <https://docs.flutter.dev/packages-and-plugins/swift-package-manager/for-plugin-authors>
- Overview: <https://docs.flutter.dev/packages-and-plugins/swift-package-manager>

## What changed

Swift Package Manager is the default for iOS and macOS in Flutter 3.44. CocoaPods is still supported as a fallback for plugins that have not migrated, but is in maintenance mode and will eventually be removed.

App-side benefits: no Ruby/CocoaPods install needed; access to the broader Swift package ecosystem.

## Critical limitation - add-to-app

> SwiftPM integration is NOT supported in add-to-app projects (where Flutter is embedded into an existing native iOS app). Tracking: <https://github.com/flutter/flutter/issues/146957>

Add-to-app projects must stay on CocoaPods. Do not run the SwiftPM enable command in those projects.

## Minimum versions

- Flutter SDK: 3.24+ for apps with SwiftPM integration
- Flutter SDK for plugin authors targeting the new `FlutterFramework` dependency: 3.41+
- Plugin `pubspec.yaml` constraint when adopting the new requirements: `flutter: ">=3.41.0"` and `sdk: ^3.11.0`

## App developer workflow

### Enable / disable

Global enable (or first-time opt-in):

```bash
flutter upgrade
flutter config --enable-swift-package-manager
```

Global disable:

```bash
flutter config --no-enable-swift-package-manager
```

Per-project disable in `pubspec.yaml`:

```yaml
flutter:
  config:
    enable-swift-package-manager: false
```

> Old syntax `flutter: disable-swift-package-manager: true` is deprecated and errors in Flutter 3.38+.

### Auto-migration

`flutter run` or `flutter build ios` with SwiftPM enabled detects an unmigrated project and runs the migration. The CLI prints:

```
Adding Swift Package Manager integration...
```

Files modified:

iOS:

- `ios/Runner.xcodeproj/project.pbxproj`
- `ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme`

macOS:

- `macos/Runner.xcodeproj/project.pbxproj`
- `macos/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme`

CocoaPods continues to work as a fallback for plugins that have not adopted SwiftPM. Flutter prints which plugins are still on CocoaPods.

### Manual migration (when auto fails)

Before manual steps, file an issue: <https://github.com/flutter/flutter/issues/new?template=2_bug.yml> with the error message and copies of `project.pbxproj` and the scheme file.

iOS manual steps:

1. Open `ios/Runner.xcworkspace` in Xcode
2. Project navigator -> Runner -> Package Dependencies
3. Click `+` -> `Add Local...`
4. Navigate to `ios/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage` -> `Add Package`
5. In the target picker, assign to `Runner` target -> `Add Package`
6. Verify `FlutterGeneratedPluginSwiftPackage` appears in Runner -> Frameworks, Libraries, and Embedded Content
7. Add a pre-build script (Product -> Scheme -> Edit Scheme -> Build -> Pre-actions):
   - New Run Script Action
   - Rename to `Run Prepare Flutter Framework Script`
   - Provide build settings from: `Runner`
   - Script:
     ```sh
     "$FLUTTER_ROOT/packages/flutter_tools/bin/xcode_backend.sh" prepare
     ```
   - Repeat for every scheme (each flavor)
8. Build in Xcode and verify CLI `flutter run` succeeds

macOS manual steps are identical except:

- Workspace: `macos/Runner.xcworkspace`
- Package path: `macos/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage`
- Pre-build script:
  ```sh
  "$FLUTTER_ROOT"/packages/flutter_tools/bin/macos_assemble.sh prepare
  ```

### Custom targets

For custom Xcode targets (not `Runner`), follow the manual steps above but substitute the custom target name everywhere `Runner` appears.

### Plugin requires higher OS version

Symptom (Xcode error):

```
Target Integrity (Xcode): The package product 'plugin_name_ios' requires minimum platform
version 14.0 for the iOS platform, but this target supports 12.0
```

Fix:

1. Open the workspace in Xcode
2. Increase Minimum Deployments for the target
3. Regenerate config:
   ```bash
   flutter build ios --config-only
   # or for macOS:
   flutter build macos --config-only
   ```

### Removing SwiftPM integration

```bash
flutter config --no-enable-swift-package-manager
flutter clean
```

Then in Xcode:

1. Package Dependencies -> select `FlutterGeneratedPluginSwiftPackage` -> click `-`
2. Target -> Frameworks, Libraries, and Embedded Content -> select `FlutterGeneratedPluginSwiftPackage` -> click `-`
3. Edit Scheme -> Build -> Pre-actions -> select `Run Prepare Flutter Framework Script` -> delete

## Plugin author workflow

Plugin packages must ship a `Package.swift` to be usable in SwiftPM-enabled apps. Packages without SwiftPM support now lose pub.dev scoring points.

### pubspec.yaml constraints

```yaml
environment:
  sdk: ^3.11.0
  flutter: ">=3.41.0"
```

### Package.swift - Swift plugin

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "plugin_name",
    platforms: [
        .iOS("13.0"),
        .macOS("10.15")
    ],
    products: [
        .library(name: "plugin-name", targets: ["plugin_name"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "plugin_name",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            resources: [
                // .process("PrivacyInfo.xcprivacy"),
            ]
        )
    ]
)
```

> Library name rule: if the plugin name contains `_`, the library name must use `-` instead. Example: plugin `my_plugin` -> library `my-plugin`.

### Package.swift - Objective-C plugin

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "plugin_name",
    platforms: [
        .iOS("13.0"),
        .macOS("10.15")
    ],
    products: [
        .library(name: "plugin-name", targets: ["plugin_name"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "plugin_name",
            dependencies: [],
            resources: [
                // .process("PrivacyInfo.xcprivacy"),
            ],
            cSettings: [
                .headerSearchPath("include/plugin_name")
            ]
        )
    ]
)
```

### Directory layout

Swift plugin:

```
plugin_name/
  ios/
    plugin_name/
      Package.swift
      Sources/
        plugin_name/
```

Objective-C plugin:

```
plugin_name/
  ios/
    plugin_name/
      Package.swift
      Sources/plugin_name/include/plugin_name/
        .gitkeep
```

### FlutterFramework dependency (new in 3.41)

Plugins that migrated during the 2025 pilot must add one extra step: add `FlutterFramework` as a dependency in `Package.swift`. See the templates above.

### podspec source paths

Update `source_files` and friends to point at the new SwiftPM layout (keeping the file work for CocoaPods consumers):

Swift plugin:

```ruby
# before
s.source_files = 'Classes/**/*.swift'
s.resource_bundles = {'plugin_name_privacy' => ['Resources/PrivacyInfo.xcprivacy']}

# after
s.source_files = 'plugin_name/Sources/plugin_name/**/*.swift'
s.resource_bundles = {'plugin_name_privacy' => ['plugin_name/Sources/plugin_name/PrivacyInfo.xcprivacy']}
```

Objective-C plugin:

```ruby
# before
s.source_files = 'Classes/**/*.{h,m}'
s.public_header_files = 'Classes/**/*.h'
s.module_map = 'Classes/cocoapods_plugin_name.modulemap'
s.resource_bundles = {'plugin_name_privacy' => ['Resources/PrivacyInfo.xcprivacy']}

# after
s.source_files = 'plugin_name/Sources/plugin_name/**/*.{h,m}'
s.public_header_files = 'plugin_name/Sources/plugin_name/include/**/*.h'
s.module_map = 'plugin_name/Sources/plugin_name/include/cocoapods_plugin_name.modulemap'
s.resource_bundles = {'plugin_name_privacy' => ['plugin_name/Sources/plugin_name/PrivacyInfo.xcprivacy']}
```

### Resource access in code

Different bundle access in SwiftPM vs CocoaPods. Use the compile-time `SWIFT_PACKAGE` flag.

Swift:

```swift
#if SWIFT_PACKAGE
    let settingsURL = Bundle.module.url(forResource: "image", withExtension: "jpg")
#else
    let settingsURL = Bundle(for: Self.self).url(forResource: "image", withExtension: "jpg")
#endif
```

Objective-C:

```objc
#if SWIFT_PACKAGE
   NSBundle *bundle = SWIFTPM_MODULE_BUNDLE;
#else
   NSBundle *bundle = [NSBundle bundleForClass:[self class]];
#endif
NSURL *imageURL = [bundle URLForResource:@"image" withExtension:@"jpg"];
```

### Pigeon

Swift plugin generator output path:

```dart
// before
swiftOut: 'ios/Classes/messages.g.swift',

// after
swiftOut: 'ios/plugin_name/Sources/plugin_name/messages.g.swift',
swiftOptions: SwiftOptions(),
```

Objective-C plugin (headers in same dir):

```dart
// before
objcHeaderOut: 'ios/Classes/messages.g.h',
objcSourceOut: 'ios/Classes/messages.g.m',

// after
objcHeaderOut: 'ios/plugin_name/Sources/plugin_name/messages.g.h',
objcSourceOut: 'ios/plugin_name/Sources/plugin_name/messages.g.m',
```

Objective-C plugin (headers in include dir):

```dart
objcHeaderOut: 'ios/plugin_name/Sources/plugin_name/include/plugin_name/messages.g.h',
objcSourceOut: 'ios/plugin_name/Sources/plugin_name/messages.g.m',
objcOptions: ObjcOptions(
  headerIncludePath: './include/plugin_name/messages.g.h',
),
```

### .gitignore

Swift plugin add:

```
.build/
.swiftpm/
```

Objective-C plugin add (to preserve `.gitkeep`):

```
!.gitkeep
```

### Testing both managers

CocoaPods:

```bash
flutter config --no-enable-swift-package-manager
cd path/to/plugin/example/
flutter run
cd path/to/plugin/
pod lib lint ios/plugin_name.podspec --configuration=Debug --skip-tests --use-modular-headers --use-libraries
pod lib lint ios/plugin_name.podspec --configuration=Debug --skip-tests --use-modular-headers
```

SwiftPM:

```bash
flutter config --enable-swift-package-manager
cd path/to/plugin/example/
flutter run
```

> Running the example app with SwiftPM enabled migrates it, raising its minimum Flutter SDK to 3.24. Do not commit those changes if the example must support older Flutter.

### ObjC modulemap exclusion

To prevent the SwiftPM build from picking up the CocoaPods modulemap:

```swift
.target(
    name: "plugin_name",
    dependencies: [],
    exclude: ["include/cocoapods_plugin_name.modulemap", "include/plugin_name-umbrella.h"],
```

And in tests:

```objc
@import plugin_name;
#if __has_include(<plugin_name/plugin_name-umbrella.h>)
  @import plugin_name.Test;
#endif
```

## Key paths reference

| Purpose | Path |
|---|---|
| iOS generated package | `ios/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage` |
| macOS generated package | `macos/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage` |
| iOS workspace | `ios/Runner.xcworkspace` |
| macOS workspace | `macos/Runner.xcworkspace` |
| iOS project file | `ios/Runner.xcodeproj/project.pbxproj` |
| iOS scheme | `ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme` |
| iOS prepare script | `$FLUTTER_ROOT/packages/flutter_tools/bin/xcode_backend.sh` |
| macOS prepare script | `$FLUTTER_ROOT/packages/flutter_tools/bin/macos_assemble.sh` |
