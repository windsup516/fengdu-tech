// SceneDelegate - 场景代理
// iOS 13+ Scene 生命周期兼容
// 将 AppDelegate 的 window 挂载到 UIScene

#import <UIKit/UIKit.h>

@interface SceneDelegate : UIResponder <UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation SceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    if (![scene isKindOfClass:[UIWindowScene class]]) return;

    UIWindowScene *windowScene = (UIWindowScene *)scene;
    id<UIApplicationDelegate> appDelegate = [UIApplication sharedApplication].delegate;

    // 尝试从 AppDelegate 获取已创建的 window
    UIWindow *existingWindow = nil;
    if ([appDelegate respondsToSelector:@selector(window)]) {
        existingWindow = [appDelegate performSelector:@selector(window)];
    }

    if (existingWindow) {
        // 挂载 AppDelegate 的 window 到这个 scene
        existingWindow.windowScene = windowScene;

        // 如果 window 还没 visible, 现在做
        if (existingWindow.hidden) {
            existingWindow.hidden = NO;
            [existingWindow makeKeyAndVisible];
        }
    } else {
        // AppDelegate 还没创建 window, 我们自己创建一个备份
        self.window = [[UIWindow alloc] initWithFrame:windowScene.coordinateSpace.bounds];
        self.window.windowScene = windowScene;
        self.window.rootViewController = [[UIViewController alloc] init];
        self.window.rootViewController.view.backgroundColor = [UIColor blackColor];
        [self.window makeKeyAndVisible];
    }
}

- (void)sceneDidDisconnect:(UIScene *)scene {}
- (void)sceneDidBecomeActive:(UIScene *)scene {}
- (void)sceneWillResignActive:(UIScene *)scene {}
- (void)sceneWillEnterForeground:(UIScene *)scene {}
- (void)sceneDidEnterBackground:(UIScene *)scene {}

@end
