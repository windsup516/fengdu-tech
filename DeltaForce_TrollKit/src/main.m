// Stocks.app (伪装) - 内核级作弊框架
// 基于 XPF + PPL bypass + IOHID 注入
// arm64 iOS 14.0-18.5
// 伪装为苹果股票应用 (com.apple.stocks)

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "LoginViewController.h"
#import "AppViewController.h"
#import "HUDController.h"
#import "XPFKernelInterface.h"

// libjailbreak.dylib 外部函数 (嵌入在 Frameworks/ 目录)
// 提供: physread32/64, physwritebuf, phystokv, vtophys, kalloc, kfree
extern int jb_init(void);
extern uint64_t physread64(uint64_t phys_addr);
extern int physwritebuf(uint64_t phys_addr, void *buffer, size_t size);
extern uint64_t phystokv(uint64_t phys_addr);

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) LoginViewController *loginVC;
@property (nonatomic, strong) AppViewController *appVC;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // ===== 步骤1: XPF 内核框架初始化 =====
    // 对应反编译: sub_10002D8C8 (首次初始化)
    // 解析 kernelcache Mach-O, 加载各区段符号
    // __TEXT_EXEC, __PPLTEXT, __DATA, __BOOTDATA, __PRELINK_TEXT 等
    int xpfResult = xpf_initialize_kernel();
    if (xpfResult != 0) {
        NSLog(@"[Stocks] XPF init failed: %d", xpfResult);
    }

    // ===== 步骤2: 越狱原语初始化 =====
    // 对应反编译: sub_1000328C8 (二次初始化)
    // libjailbreak.dylib 提供物理内存 R/W
    jb_init();
    
    // ===== 步骤3: 设置主窗口 =====
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    
    // ===== 步骤4: 显示授权登录界面 =====
    // 对应反编译: LoginViewController 加载
    self.loginVC = [[LoginViewController alloc] init];
    __weak typeof(self) weakSelf = self;
    self.loginVC.onAuthorized = ^{
        // 授权成功 → 显示主菜单 + 启动 HUD
        [weakSelf showMainMenu];
    };
    
    self.window.rootViewController = self.loginVC;
    [self.window makeKeyAndVisible];
    
    // ===== 步骤5: 后台批量解析内核符号 =====
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        // xpf_common_init → 解析所有 kernelSymbol.
        // xpf_non_ppl_init → iOS < 16 路径
        // xpf_ppl_init → iOS 16+ PPL 绕过
        // xpf_bad_recovery_init → 备用漏洞
        xpf_resolve_all_symbols();
        xpf_setup_kcall_primitive();
    });
    
    return YES;
}

- (void)showMainMenu {
    self.appVC = [[AppViewController alloc] init];
    
    // 平滑过渡 (对应反编译: transitionFromView)
    [UIView transitionFromView:self.loginVC.view
                        toView:self.appVC.view
                      duration:0.4
                       options:UIViewAnimationOptionTransitionCrossDissolve
                    completion:^(BOOL finished) {
        self.window.rootViewController = self.appVC;
        
        // 初始化 HUD 系统 (作弊菜单覆盖层 + 触摸捕获)
        // HUDWindow + TouchWindow + SBSAccessibility托管
        [[HUDController shared] createWindowsOnScene:nil];
    }];
}

@end

// TrollStore 入口
int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, 
               NSStringFromClass([AppDelegate class]));
    }
}
