// SceneDelegate — matching Amazon2 AppSceneDelegate pattern
// Creates main Stocks window on UIWindowScene
// BSServiceDomains keeps Scene alive when app backgrounds

#import "SceneDelegate.h"
#import "LoginViewController.h"
#import "AppDelegate.h"
#import "AppViewController.h"
#import "HUDController.h"
#import "TouchMainWindow.h"
#import "Logging.h"

// UIWindow private API
@interface UIWindow (Private)
- (unsigned int)_contextId;
@end

@implementation SceneDelegate

// === Amazon2: scene:willConnectToSession:options: ===
// Creates the main window with initWithWindowScene: (Scene-based, not standalone)
// Sets up login UI with authorization callback
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session
      options:(UISceneConnectionOptions *)connectionOptions {

    if (![scene isKindOfClass:[UIWindowScene class]]) return;

    UIWindowScene *windowScene = (UIWindowScene *)scene;

    // Create window attached to this scene (matching Amazon2 initWithWindowScene:)
    self.window = [[UIWindow alloc] initWithWindowScene:windowScene];
    self.window.frame = windowScene.coordinateSpace.bounds;

    // Get AppDelegate for the authorization callback
    AppDelegate *appDelegate = (AppDelegate *)[UIApplication sharedApplication].delegate;

    // Set up login UI
    LoginViewController *loginVC = [[LoginViewController alloc] init];
    __weak typeof(self) weakSelf = self;
    __weak typeof(appDelegate) weakApp = appDelegate;

    loginVC.onAuthorized = ^{
        // Switch to main app UI
        AppViewController *appVC = [[AppViewController alloc] init];
        weakSelf.window.rootViewController = appVC;

        // Trigger HUD + game launch
        [weakApp startCheatDirectly];
    };

    self.window.rootViewController = loginVC;
    [self.window makeKeyAndVisible];

    // Store reference back to AppDelegate for window access
    appDelegate.window = self.window;

    SAFE_LOG(@"SceneDelegate: window created on scene, ctx=%u",
             (unsigned int)[self.window _contextId]);
}

// === Scene lifecycle callbacks (required for UIWindowSceneDelegate) ===

- (void)sceneDidDisconnect:(UIScene *)scene {
    SAFE_LOG(@"Scene did disconnect");
}

- (void)sceneDidBecomeActive:(UIScene *)scene {
    SAFE_LOG(@"Scene did become active — re-registering SBS");
    [[HUDController shared] reRegisterSBSHosting];
}

- (void)sceneWillResignActive:(UIScene *)scene {
    SAFE_LOG(@"Scene will resign active — proactive SBS re-register");
    [[HUDController shared] reRegisterSBSHosting];
}

- (void)sceneWillEnterForeground:(UIScene *)scene {
    SAFE_LOG(@"Scene will enter foreground");
    [[HUDController shared] reRegisterSBSHosting];
}

- (void)sceneDidEnterBackground:(UIScene *)scene {
    SAFE_LOG(@"Scene did enter background — checking contextId");
    // ContextId check
    HUDController *hc = [HUDController shared];
    unsigned int hudCtx = 0, touchCtx = 0;
    if (hc.hudWindow && [hc.hudWindow respondsToSelector:@selector(_contextId)])
        hudCtx = (unsigned int)[hc.hudWindow _contextId];
    if (hc.touchWindow && [hc.touchWindow respondsToSelector:@selector(_contextId)])
        touchCtx = (unsigned int)[hc.touchWindow _contextId];
    SAFE_LOG(@"Background: hudCtx=%u touchCtx=%u", hudCtx, touchCtx);

    if (hudCtx == 0 || touchCtx == 0) {
        SAFE_LOG(@"CONTEXT LOST on background — triggering recovery");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [[HUDController shared] reRegisterSBSHosting];
        });
    }
}

@end
