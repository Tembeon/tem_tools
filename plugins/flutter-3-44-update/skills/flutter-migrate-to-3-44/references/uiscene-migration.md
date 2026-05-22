# UIScene lifecycle migration (iOS)

Source: <https://docs.flutter.dev/release/breaking-changes/uiscenedelegate>
Apple Tech Note TN3187: <https://developer.apple.com/documentation/technotes/tn3187-migrating-to-the-uikit-scene-based-life-cycle>

## Why

Apple announcement: "In the release following iOS 26, any UIKit app built with the latest SDK will be required to use the UIScene lifecycle, otherwise it will not launch."

After UIScene adoption, UIKit stops calling UI-state methods on `AppDelegate` - everything UI-related belongs on `UISceneDelegate`. `AppDelegate` keeps process-level lifecycle.

## Auto-migration

- First available: Flutter 3.38.0-0.1.pre
- Default-on since: Flutter 3.41+
- Runs on: `flutter run` or `flutter build ios`
- Success log: `Finished migration to UIScene lifecycle`

Auto-migration only works on `AppDelegate` files that have not been customized. Customised projects need the manual steps below.

Known auto-migration limitation: if `UIKit` is imported before `Flutter` in `AppDelegate`, the migrator fails to detect the file. Reorder imports (`import Flutter` then `import UIKit`) and re-run.

## Utility flags

Hide the migration warning in `pubspec.yaml`:

```yaml
flutter:
  config:
    enable-uiscene-migration: false
```

Temporarily disable UIScene by prefixing the `Application Scene Manifest` key in `Info.plist` with `_` (becomes `_UIApplicationSceneManifest`). Remove the underscore to re-enable.

## Manual migration - Flutter apps

### Step 1 - Move plugin registration

`GeneratedPluginRegistrant.register` moves from `application:didFinishLaunchingWithOptions:` to the new `didInitializeImplicitFlutterEngine` callback declared by `FlutterImplicitEngineDelegate`.

Swift before:

```swift
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
```

Swift after:

```swift
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
```

Objective-C header before:

```objc
@interface AppDelegate : FlutterAppDelegate
```

Objective-C header after:

```objc
@interface AppDelegate : FlutterAppDelegate <FlutterImplicitEngineDelegate>
```

Objective-C implementation before:

```objc
- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
  [GeneratedPluginRegistrant registerWithRegistry:self];
  return [super application:application didFinishLaunchingWithOptions:launchOptions];
}
```

Objective-C implementation after:

```objc
- (void)didInitializeImplicitFlutterEngine:(NSObject<FlutterImplicitEngineBridge>*)engineBridge {
  [GeneratedPluginRegistrant registerWithRegistry:engineBridge.pluginRegistry];
}
```

### Step 2 - Move method channels and platform views

Any method channels or platform views previously created in `application:didFinishLaunchingWithOptions:` move into `didInitializeImplicitFlutterEngine`. Use `engineBridge.applicationRegistrar.messenger()` as the binary messenger.

Swift:

```swift
func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
  GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

  let batteryChannel = FlutterMethodChannel(
    name: "samples.flutter.dev/battery",
    binaryMessenger: engineBridge.applicationRegistrar.messenger()
  )

  let factory = FLNativeViewFactory(messenger: engineBridge.applicationRegistrar.messenger())
}
```

Objective-C:

```objc
- (void)didInitializeImplicitFlutterEngine:(NSObject<FlutterImplicitEngineBridge>*)engineBridge {
  [GeneratedPluginRegistrant registerWithRegistry:engineBridge.pluginRegistry];

  FlutterMethodChannel* batteryChannel = [FlutterMethodChannel
    methodChannelWithName:@"samples.flutter.dev/battery"
    binaryMessenger:engineBridge.applicationRegistrar.messenger];

  FLNativeViewFactory* factory =
    [[FLNativeViewFactory alloc] initWithMessenger:engineBridge.applicationRegistrar.messenger];
}
```

> Crash warning: accessing `FlutterViewController` in `application:didFinishLaunchingWithOptions:` via `window?.rootViewController` may crash after migration. Use `FlutterImplicitEngineDelegate` instead, or use `awakeFromNib` on a `FlutterViewController` subclass (see "Bespoke FlutterViewController" below).

### Step 3 - Add Application Scene Manifest to Info.plist

Full XML:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
 <key>UIApplicationSceneManifest</key>
 <dict>
  <key>UIApplicationSupportsMultipleScenes</key>
  <false/>
  <key>UISceneConfigurations</key>
  <dict>
  <key>UIWindowSceneSessionRoleApplication</key>
    <array>
      <dict>
        <key>UISceneClassName</key>
        <string>UIWindowScene</string>
        <key>UISceneDelegateClassName</key>
        <string>FlutterSceneDelegate</string>
        <key>UISceneConfigurationName</key>
        <string>flutter</string>
        <key>UISceneStoryboardFile</key>
        <string>Main</string>
      </dict>
    </array>
   </dict>
 </dict>
</dict>
```

### Step 4 (optional) - Custom SceneDelegate

When custom scene behavior is needed, subclass `FlutterSceneDelegate`.

Swift `SceneDelegate.swift`:

```swift
import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {

}
```

Update Info.plist `UISceneDelegateClassName` from `FlutterSceneDelegate` to `$(PRODUCT_MODULE_NAME).SceneDelegate`.

Objective-C `SceneDelegate.h`:

```objc
#import <Flutter/Flutter.h>
#import <UIKit/UIKit.h>

@interface SceneDelegate : FlutterSceneDelegate

@end
```

Objective-C `SceneDelegate.m`:

```objc
#import "SceneDelegate.h"

@implementation SceneDelegate

@end
```

Update Info.plist `UISceneDelegateClassName` to `SceneDelegate`.

## Add-to-app (Flutter embedded in existing iOS app)

> Note: SwiftPM is not supported in add-to-app; CocoaPods stays in use.

Two paths depending on whether the host can subclass `FlutterSceneDelegate`.

### Option A - subclass FlutterSceneDelegate (preferred)

Swift:

```swift
// before
class SceneDelegate: UIResponder, UIWindowSceneDelegate {

// after
class SceneDelegate: FlutterSceneDelegate {
```

Objective-C:

```objc
// before
@interface SceneDelegate : UIResponder <UIWindowSceneDelegate>

// after
@interface SceneDelegate : FlutterSceneDelegate
```

Subclassing automatically forwards scene callbacks (e.g., `openURL`) to plugins like `local_auth`.

### Option B - use FlutterSceneLifeCycleProvider

For hosts where subclassing is not possible (existing inheritance constraints). The provider pattern wraps a `FlutterPluginSceneLifeCycleDelegate` and forwards each scene callback manually.

Swift:

```swift
import Flutter
import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate, FlutterSceneLifeCycleProvider {
  var sceneLifeCycleDelegate: FlutterPluginSceneLifeCycleDelegate =
    FlutterPluginSceneLifeCycleDelegate()

  var window: UIWindow?

  func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    sceneLifeCycleDelegate.scene(scene, willConnectTo: session, options: connectionOptions)
  }

  func sceneDidDisconnect(_ scene: UIScene) {
    sceneLifeCycleDelegate.sceneDidDisconnect(scene)
  }

  func sceneWillEnterForeground(_ scene: UIScene) {
    sceneLifeCycleDelegate.sceneWillEnterForeground(scene)
  }

  func sceneDidBecomeActive(_ scene: UIScene) {
    sceneLifeCycleDelegate.sceneDidBecomeActive(scene)
  }

  func sceneWillResignActive(_ scene: UIScene) {
    sceneLifeCycleDelegate.sceneWillResignActive(scene)
  }

  func sceneDidEnterBackground(_ scene: UIScene) {
    sceneLifeCycleDelegate.sceneDidEnterBackground(scene)
  }

  func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    sceneLifeCycleDelegate.scene(scene, openURLContexts: URLContexts)
  }

  func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
    sceneLifeCycleDelegate.scene(scene, continue: userActivity)
  }

  func windowScene(
    _ windowScene: UIWindowScene,
    performActionFor shortcutItem: UIApplicationShortcutItem,
    completionHandler: @escaping (Bool) -> Void
  ) {
    sceneLifeCycleDelegate.windowScene(
      windowScene,
      performActionFor: shortcutItem,
      completionHandler: completionHandler
    )
  }
}
```

Objective-C header:

```objc
@interface SceneDelegate : UIResponder <UIWindowSceneDelegate, FlutterSceneLifeCycleProvider>

@property(strong, nonatomic) UIWindow* window;
@property (nonatomic,strong) FlutterPluginSceneLifeCycleDelegate *sceneLifeCycleDelegate;

@end
```

Objective-C implementation:

```objc
@implementation SceneDelegate

- (instancetype)init {
    if (self = [super init]) {
        _sceneLifeCycleDelegate = [[FlutterPluginSceneLifeCycleDelegate alloc] init];
    }
    return self;
}

- (void)scene:(UIScene*)scene
    willConnectToSession:(UISceneSession*)session
                options:(UISceneConnectionOptions*)connectionOptions {
  [self.sceneLifeCycleDelegate scene:scene willConnectToSession:session options:connectionOptions];
}

- (void)sceneDidDisconnect:(UIScene*)scene {
  [self.sceneLifeCycleDelegate sceneDidDisconnect:scene];
}

- (void)sceneDidBecomeActive:(UIScene*)scene {
  [self.sceneLifeCycleDelegate sceneDidBecomeActive:scene];
}

- (void)sceneWillResignActive:(UIScene*)scene {
  [self.sceneLifeCycleDelegate sceneWillResignActive:scene];
}

- (void)sceneWillEnterForeground:(UIScene*)scene {
  [self.sceneLifeCycleDelegate sceneWillEnterForeground:scene];
}

- (void)sceneDidEnterBackground:(UIScene*)scene {
  [self.sceneLifeCycleDelegate sceneDidEnterBackground:scene];
}

- (void)scene:(UIScene *)scene openURLContexts:(NSSet<UIOpenURLContext *> *)URLContexts {
  [self.sceneLifeCycleDelegate scene:scene openURLContexts:URLContexts];
}

- (void)scene:(UIScene *)scene continueUserActivity:(NSUserActivity *)userActivity {
  [self.sceneLifeCycleDelegate scene:scene continueUserActivity:userActivity];
}

- (void)windowScene:(UIWindowScene *)windowScene performActionForShortcutItem:(UIApplicationShortcutItem *)shortcutItem completionHandler:(void (^)(BOOL))completionHandler {
  [self.sceneLifeCycleDelegate windowScene:windowScene performActionForShortcutItem:shortcutItem completionHandler:completionHandler];
}

@end
```

### SwiftUI host

Set the scene delegate to `FlutterSceneDelegate` in `application:configurationForConnecting:options:`:

```swift
@Observable
class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    configurationForConnecting connectingSceneSession: UISceneSession,
    options: UIScene.ConnectionOptions
  ) -> UISceneConfiguration {
    let configuration = UISceneConfiguration(
      name: nil,
      sessionRole: connectingSceneSession.role
    )
    configuration.delegateClass = FlutterSceneDelegate.self
    return configuration
  }
}
```

Also set `Enable Multiple Scenes` to `NO` in Info.plist if the app does not actually support multiple scenes (SwiftUI defaults to YES).

### Multiple scenes

When `UIApplicationSupportsMultipleScenes` is true, Flutter cannot auto-connect a `FlutterEngine` to its `UIScene` on initial connection. Manual registration is required in `scene:willConnectToSession:options:`, otherwise launch events (deep links, shortcut items) are missed.

Swift:

```swift
import Flutter
import FlutterPluginRegistrant
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  let flutterEngine = FlutterEngine(name: "my flutter engine")

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    guard let windowScene = scene as? UIWindowScene else { return }
    window = UIWindow(windowScene: windowScene)

    flutterEngine.run()
    GeneratedPluginRegistrant.register(with: flutterEngine)

    // Subclassing FlutterSceneDelegate:
    self.registerSceneLifeCycle(with: flutterEngine)

    // Using FlutterSceneLifeCycleProvider:
    // sceneLifeCycleDelegate.registerSceneLifeCycle(with: flutterEngine)

    let viewController = ViewController(engine: flutterEngine)
    window?.rootViewController = viewController
    window?.makeKeyAndVisible()
    super.scene(scene, willConnectTo: session, options: connectionOptions)
  }
}
```

When the engine's view changes scenes, unregister too:

```swift
// subclassing FlutterSceneDelegate
self.unregisterSceneLifeCycle(with: flutterEngine)

// FlutterSceneLifeCycleProvider
sceneLifeCycleDelegate.unregisterSceneLifeCycle(with: flutterEngine)
```

## Plugin author migration

### Step 1 - pubspec.yaml

```yaml
environment:
  sdk: ^3.10.0
  flutter: ">=3.38.0"
```

### Step 2 - Adopt FlutterSceneLifeCycleDelegate

Swift:

```swift
// before
public final class MyPlugin: NSObject, FlutterPlugin {

// after
public final class MyPlugin: NSObject, FlutterPlugin, FlutterSceneLifeCycleDelegate {
```

Objective-C:

```objc
// before
@interface MyPlugin : NSObject<FlutterPlugin>

// after
@interface MyPlugin : NSObject<FlutterPlugin, FlutterSceneLifeCycleDelegate>
```

### Step 3 - Register for both lifecycles

Keep both calls so the plugin works with un-migrated apps and migrated apps alike.

Swift:

```swift
public static func register(with registrar: FlutterPluginRegistrar) {
  // ...
  registrar.addApplicationDelegate(instance)
  registrar.addSceneDelegate(instance)
}
```

Objective-C:

```objc
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  // ...
  [registrar addApplicationDelegate:instance];
  [registrar addSceneDelegate:instance];
}
```

### Step 4 - AppDelegate to SceneDelegate method mapping

| AppDelegate | SceneDelegate |
|---|---|
| `applicationDidBecomeActive` | `sceneDidBecomeActive` |
| `applicationWillResignActive` | `sceneWillResignActive` |
| `applicationWillEnterForeground` | `sceneWillEnterForeground` |
| `applicationDidEnterBackground` | `sceneDidEnterBackground` |
| `application:continueUserActivity:restorationHandler:` | `scene:continueUserActivity:` |
| `application:performActionForShortcutItem:completionHandler:` | `windowScene:performActionForShortcutItem:completionHandler:` |
| `application:openURL:options:` | `scene:openURLContexts:` |
| `application:performFetchWithCompletionHandler:` | `BGAppRefreshTask` |
| `application:willFinishLaunchingWithOptions:` | `scene:willConnectToSession:options:` |
| `application:didFinishLaunchingWithOptions:` | `scene:willConnectToSession:options:` |

### Step 5 - Scene event signatures

Swift:

```swift
public func scene(
  _ scene: UIScene,
  willConnectTo session: UISceneSession,
  options connectionOptions: UIScene.ConnectionOptions?
) -> Bool { }

public func sceneDidDisconnect(_ scene: UIScene) { }

public func sceneWillEnterForeground(_ scene: UIScene) { }

public func sceneDidBecomeActive(_ scene: UIScene) { }

public func sceneWillResignActive(_ scene: UIScene) { }

public func sceneDidEnterBackground(_ scene: UIScene) { }

public func scene(
    _ scene: UIScene,
    openURLContexts URLContexts: Set<UIOpenURLContext>
  ) -> Bool { }

public func scene(_ scene: UIScene, continue userActivity: NSUserActivity)
    -> Bool { }

public func windowScene(
    _ windowScene: UIWindowScene,
    performActionFor shortcutItem: UIApplicationShortcutItem,
    completionHandler: @escaping (Bool) -> Void
  ) -> Bool { }
```

Objective-C:

```objc
- (BOOL)scene:(UIScene*)scene
    willConnectToSession:(UISceneSession*)session
                 options:(nullable UISceneConnectionOptions*)connectionOptions { }

- (void)sceneDidDisconnect:(UIScene*)scene { }

- (void)sceneWillEnterForeground:(UIScene*)scene { }

- (void)sceneDidBecomeActive:(UIScene*)scene { }

- (void)sceneWillResignActive:(UIScene*)scene { }

- (void)sceneDidEnterBackground:(UIScene*)scene { }

- (BOOL)scene:(UIScene*)scene openURLContexts:(NSSet<UIOpenURLContext*>*)URLContexts { }

- (BOOL)scene:(UIScene*)scene continueUserActivity:(NSUserActivity*)userActivity { }

- (BOOL)windowScene:(UIWindowScene*)windowScene
    performActionForShortcutItem:(UIApplicationShortcutItem*)shortcutItem
               completionHandler:(void (^)(BOOL succeeded))completionHandler { }
```

### Step 6 - Launch options caveat

`application:willFinishLaunchingWithOptions:` and `application:didFinishLaunchingWithOptions:` are not deprecated, but after UIScene migration the launch options arg is `nil`. Any launch-options logic must move to `scene:willConnectToSession:options:`.

### Step 7 - Replace deprecated UIScreen/UIApplication APIs

| Deprecated | UIScene replacement |
|---|---|
| `UIScreen.mainScreen` | `UIWindowScene.screen` |
| `UIApplication.keyWindow` | `UIWindowScene.keyWindow` (iOS 15+) or filter `windows` |
| `UIApplication.windows` | `UIWindowScene.windows` |
| `UIApplicationDelegate.window` | `UIView.window` |

Objective-C plugin example (full pattern):

```objc
@interface MyPlugin ()
  @property(nonatomic, weak) NSObject<FlutterPluginRegistrar> *registrar;
   - (instancetype)initWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar;
@end

@implementation MyPlugin

 - (instancetype)initWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
   self = [super init];
   if (self) {
     _registrar = registrar;
   }
   return self;
 }

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
   MyPlugin *instance = [[MyPlugin alloc] initWithRegistrar:registrar];
}

- (void)someMethod {
   // UIScreen *screen = [UIScreen mainScreen];
   UIScreen *screen = self.registrar.viewController.view.window.windowScene.screen;

   // UIWindow *window = [UIApplication sharedApplication].delegate.window;
   UIWindow *window = self.registrar.viewController.view.window;

   // UIWindow *keyWindow = [[UIApplication sharedApplication] keyWindow];
   if (@available(iOS 15.0, *)) {
     UIWindow *keyWindow = self.registrar.viewController.view.window.windowScene.keyWindow;
   } else {
     for (UIWindow *window in self.registrar.viewController.view.window.windowScene.windows) {
       if (window.isKeyWindow) {
         UIWindow *keyWindow = window;
       }
     }
   }

   // NSArray<UIWindow *> *windows = [UIApplication sharedApplication].windows;
   NSArray<UIWindow *> *windows = self.pluginRegistrar.viewController.view.window.windowScene.windows;
}
```

## Bespoke FlutterViewController

For apps that instantiate `FlutterViewController` from a Storyboard inside `application:didFinishLaunchingWithOptions:`, two workarounds:

Option A - subclass and use `awakeFromNib`:

```swift
@objc class MyViewController: FlutterViewController {
  override func awakeFromNib() {
    self.awakeFromNib()
    doSomethingWithFlutterViewController(self)
  }
}
```

Option B - implement a `UISceneDelegate` (or keep a `UIApplicationDelegate`) and run the customisation in `scene:willConnectToSession:options:`.

## Crash conditions and caveats

1. Accessing `FlutterViewController` in `application:didFinishLaunchingWithOptions:` via `window?.rootViewController` may crash. Use `FlutterImplicitEngineDelegate` instead.
2. After UIScene migration, `didFinishLaunchingWithOptions` receives `nil` launch options. Move that logic to `scene:willConnectToSession:options:`.
3. With multiple scenes enabled, missing manual engine registration in `scene:willConnectToSession:options:` causes deep links and shortcut items from launch to be missed.
4. After migration, UIKit no longer calls deprecated `AppDelegate` UI lifecycle methods (e.g., `applicationDidBecomeActive`).
5. The auto-migrator fails to detect `AppDelegate` files where `UIKit` is imported before `Flutter`. Reorder imports.
