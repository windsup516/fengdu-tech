// Stocks.app (伪装) - Delta Force 作弊框架
// TrollStore + 越狱兼容版本
// arm64 iOS 13.0-16.x
// 伪装为苹果股票应用 (com.apple.stocks)

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "LoginViewController.h"
#import "AppViewController.h"
#import "HUDController.h"
#import "XPFKernelInterface.h"

// 外部函数声明 (来自 ExternalStubs.c)
extern int jb_init(void);
extern int is_trollstore(void);
extern int is_jailbroken(void);
extern uint64_t physread64(uint64_t phys_addr);
extern int physwritebuf(uint64_t phys_addr, void *buffer, size_t size);
extern uint64_t phystokv(uint64_t phys_addr);

// 安全日志宏
#define SAFE_LOG(fmt, ...) do { \
    fprintf(stderr, "[Stocks] " fmt "\n", ##__VA_ARGS__); \
} while(0)

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) LoginViewController *loginVC;
@property (nonatomic, strong) AppViewController *appVC;
@property (nonatomic) int environmentType; // 0=普通, 1=TrollStore, 2=越狱
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {

    SAFE_LOG("=== DeltaForce TrollKit v2.1 Starting ===");

    // ===== 步骤1: 环境检测 (非致命) =====
    self.environmentType = 0;
    if (is_jailbroken()) {
        self.environmentType = 2;
        SAFE_LOG("Environment: JAILBROKEN");
    } else if (is_trollstore()) {
        self.environmentType = 1;
        SAFE_LOG("Environment: TrollStore");
    } else {
        SAFE_LOG("Environment: Normal (limited)");
    }

    // ===== 步骤2: XPF 内核框架初始化 (允许失败) =====
    // 在 TrollStore 环境下这步会失败, 但不影响 overlay 功能
    int xpfResult = xpf_initialize_kernel();
    if (xpfResult != 0) {
        SAFE_LOG("XPF kernel init: FAILED (expected on TrollStore, continuing...)");
    } else {
        SAFE_LOG("XPF kernel init: OK");
    }

    // ===== 步骤3: 越狱原语初始化 (允许失败) =====
    int jbResult = jb_init();
    if (jbResult != 0) {
        SAFE_LOG("jb_init: FAILED (continuing with userspace only)");
    }

    // ===== 步骤4: 设置主窗口 =====
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];

    // iOS 13+ 需要 UIWindowScene
    if (@available(iOS 13.0, *)) {
        // 尝试从已连接的 scenes 获取
        UIWindowScene *scene = nil;
        for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
            if ([s isKindOfClass:[UIWindowScene class]]) {
                scene = (UIWindowScene *)s;
                break;
            }
        }
        if (scene) {
            self.window.windowScene = scene;
        }
        // 如果没有 scene (旧式启动), 直接使用, iOS 会容忍
    }

    // ===== 步骤5: 显示授权登录界面 =====
    self.loginVC = [[LoginViewController alloc] init];
    __weak typeof(self) weakSelf = self;
    self.loginVC.onAuthorized = ^{
        [weakSelf showMainMenu];
    };

    self.window.rootViewController = self.loginVC;
    [self.window makeKeyAndVisible];

    // ===== 步骤6: 后台初始化 (不阻塞 UI) =====
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        if (weakSelf.environmentType >= 1) {
            // 尝试解析内核符号 (仅在越狱下有效)
            xpf_resolve_all_symbols();
            xpf_setup_kcall_primitive();
            SAFE_LOG("Background init complete (env=%d)", weakSelf.environmentType);
        }
    });

    return YES;
}

- (void)showMainMenu {
    self.appVC = [[AppViewController alloc] init];

    [UIView transitionFromView:self.loginVC.view
                        toView:self.appVC.view
                      duration:0.4
                       options:UIViewAnimationOptionTransitionCrossDissolve
                    completion:^(BOOL finished) {
        self.window.rootViewController = self.appVC;

        // 初始化 HUD 系统 (作弊菜单覆盖层 + 触摸捕获)
        // 在 TrollStore 环境: 仅使用 userspace overlay (无需内核)
        // 在越狱环境: 可以使用完整的内核级功能
        [[HUDController shared] createWindowsOnScene:self.window.windowScene];
    }];
}

@end

// 入口 (兼容 TrollStore 和 Xcode 编译)
int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil,
               NSStringFromClass([AppDelegate class]));
    }
}
