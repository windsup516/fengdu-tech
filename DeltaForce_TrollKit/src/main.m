// DeltaForce TrollKit v2.1 - 内核级作弊框架
// 基于 XPF + PPL bypass + IOHID 注入
// arm64/arm64e iOS 15.0-18.5

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "LoginViewController.h"
#import "AppViewController.h"
#import "HUDController.h"
#import "XPFKernelInterface.h"
#import "GameHooks.h"

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) LoginViewController *loginVC;
@property (nonatomic, strong) AppViewController *appVC;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // 步骤1: 初始化 XPF 内核框架
    // xpf_start_with_kernel_path() → 解析 kernelcache MachO
    // 加载: __TEXT_EXEC, __PPLTEXT, __DATA, __BOOTDATA 各区段
    // 解析内核符号: allproc, pmap, vm_map, proc 等
    int xpfResult = xpf_initialize_kernel();
    if (xpfResult != 0) {
        NSLog(@"[Star] XPF init failed: %d - falling back to userspace only", xpfResult);
    } else {
        NSLog(@"[Star] XPF kernel primitives ready");
    }

    // 步骤2: 初始化 Jailbreak 服务 (libjailbreak.dylib)
    // 内存页重映射, 沙箱绕过, 进程附加
    jb_init();
    
    // 步骤3: 设置主窗口
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.windowLevel = UIWindowLevelAlert;
    
    // 步骤4: 显示授权登录界面
    self.loginVC = [[LoginViewController alloc] init];
    __weak typeof(self) weakSelf = self;
    self.loginVC.onAuthorized = ^{
        [weakSelf showMainMenu];
    };
    
    self.window.rootViewController = self.loginVC;
    [self.window makeKeyAndVisible];
    
    // 步骤5: 后台启动 XPF 内核符号批量解析
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        xpf_resolve_all_symbols();
        xpf_setup_kcall_primitive();  // kcall / kexec 原语
    });
    
    return YES;
}

- (void)showMainMenu {
    self.appVC = [[AppViewController alloc] init];
    self.appVC.onAuthorized = self.loginVC.onAuthorized; // 传递授权回调
    
    // 从 LoginVC 传递加密状态
    self.appVC.statusText = self.loginVC.statusLabel.text;
    
    // 平滑过渡动画
    [UIView transitionFromView:self.loginVC.view
                        toView:self.appVC.view
                      duration:0.4
                       options:UIViewAnimationOptionTransitionCrossDissolve
                    completion:^(BOOL finished) {
        self.window.rootViewController = self.appVC;
        
        // 初始化 HUD 系统 (作弊菜单覆盖层)
        [[HUDController shared] createWindowsOnScene:nil];
    }];
}

@end

// TrollStore 入口
int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}
