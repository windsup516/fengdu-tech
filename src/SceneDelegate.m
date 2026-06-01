// SceneDelegate - 场景代理
// iOS 13+ Scene 生命周期兼容
// 将 AppDelegate 的 window 挂载到 UIScene

#import <UIKit/UIKit.h>

@interface SceneDelegate : UIResponder <UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation SceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(__unused UISceneSession *)session options:(__unused UISceneConnectionOptions *)connectionOptions {
    if (![scene isKindOfClass:[UIWindowScene class]]) return;

    UIWindowScene *windowScene = (UIWindowScene *)scene;
    id<UIApplicationDelegate> appDelegate = [UIApplication sharedApplication].delegate;

    UIWindow *existingWindow = nil;
    if ([appDelegate respondsToSelector:@selector(window)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        existingWindow = [appDelegate performSelector:@selector(window)];
#pragma clang diagnostic pop
    }

    if (existingWindow) {
        existingWindow.windowScene = windowScene;
        if (existingWindow.hidden) {
            existingWindow.hidden = NO;
            [existingWindow makeKeyAndVisible];
        }
    } else {
        self.window = [[UIWindow alloc] initWithFrame:windowScene.coordinateSpace.bounds];
        self.window.windowScene = windowScene;
        self.window.rootViewController = [[UIViewController alloc] init];
        self.window.rootViewController.view.backgroundColor = [UIColor blackColor];
        [self.window makeKeyAndVisible];
    }
}

- (void)sceneDidDisconnect:(__unused UIScene *)scene {}
- (void)sceneDidBecomeActive:(__unused UIScene *)scene {}
- (void)sceneWillResignActive:(__unused UIScene *)scene {}
- (void)sceneWillEnterForeground:(__unused UIScene *)scene {}
- (void)sceneDidEnterBackground:(__unused UIScene *)scene {}

@end
