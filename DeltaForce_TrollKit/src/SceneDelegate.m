// SceneDelegate - 场景代理
// iOS 13+ Scene 生命周期: 将 AppDelegate 创建的 window 挂载到 UIScene
// 否则 Info.plist 声明了 UIApplicationSceneManifest 但窗口未连接 = 黑屏

#import <UIKit/UIKit.h>

@interface SceneDelegate : UIResponder <UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation SceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    if (![scene isKindOfClass:[UIWindowScene class]]) return;

    id<UIApplicationDelegate> appDelegate = [UIApplication sharedApplication].delegate;
    UIWindow *existingWindow = nil;

    if ([appDelegate respondsToSelector:@selector(window)]) {
        existingWindow = [appDelegate performSelector:@selector(window)];
    }

    if (existingWindow) {
        existingWindow.windowScene = (UIWindowScene *)scene;
    }
}

- (void)sceneDidDisconnect:(UIScene *)scene {}
- (void)sceneDidBecomeActive:(UIScene *)scene {}
- (void)sceneWillResignActive:(UIScene *)scene {}
- (void)sceneWillEnterForeground:(UIScene *)scene {}
- (void)sceneDidEnterBackground:(UIScene *)scene {}

@end
