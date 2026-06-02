// AppDelegate — Stocks app entry
// iOS 13+ Scene-based lifecycle (matching Amazon2 architecture)
// BSServiceDomains keeps Scene alive when app backgrounds

#import <UIKit/UIKit.h>

@class LoginViewController, AppViewController;

@interface AppDelegate : UIResponder <UIApplicationDelegate>

@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) LoginViewController *loginVC;
@property (nonatomic, strong) AppViewController *appVC;
@property (nonatomic) int environmentType;
@property (nonatomic) BOOL cheatStarted;
@property (nonatomic, strong) NSString *gameBundlePath;

- (BOOL)launchDeltaForceGame;
- (void)startCheatDirectly;

@end
