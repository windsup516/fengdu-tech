// HUDController - 作弊覆盖层管理器
// 基于反编译: createWindowsOnScene / registerHIDEventCallback
// 使用 SBSAccessibilityWindowHostingController 躲避检测
// 双窗口架构: HUDMainWindow(菜单) + TouchMainWindow(触摸)

#import "HUDController.h"
#import "HUDRootViewController.h"
#import "TouchMainWindow.h"
#import "TouchViewController.h"
#import "CryptoUtils.h"
#import "HIDEventManager.h"
#import <objc/runtime.h>
#import <UIKit/UIKit.h>

// 全局触摸窗口引用 (从反编译: qword_10139CB40)
static TouchMainWindow *gTouchWindow = nil;

// 加密的类名: "SBSAccessibilityWindowHostingController"
// 运行时解密避免静态检测
static int8x16_t encryptedClassName1 = {0x4a,0x4c,0x4e,0x43,0x4f,0x0e,0x45,0x0d,0x0e,0x46,0x4f,0x07,0x01,0x0b,0x06,0x04};
static int8x16_t xorKeyClassName1    = {0x2a,0x2c,0x2e,0x23,0x2f,0x6e,0x25,0x6d,0x6e,0x26,0x2f,0x67,0x61,0x6b,0x66,0x64};

// 对应反编译中的子函数 sub_10000A514 - 附加窗口到托管控制器
extern void attachWindowToHostingController(UIWindow *window, id hostingController);

@interface HUDController ()
@property (nonatomic, strong) HUDMainWindow *hudWindow;
@property (nonatomic, strong) TouchMainWindow *touchWindow;
@property (nonatomic, strong) HUDRootViewController *rootVC;
@property (nonatomic, strong) TouchViewController *touchVC;
@property (nonatomic, strong) id hostingController; // SBSAccessibilityWindowHostingController
@property (nonatomic) BOOL showing;
@property (nonatomic) BOOL windowsCreated;
@end

@implementation HUDController

+ (instancetype)shared {
    static HUDController *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[HUDController alloc] init];
    });
    return shared;
}

- (void)createWindowsOnScene:(id)scene {
    if (self.windowsCreated) return;
    self.windowsCreated = YES;
    
    // 步骤1: 创建 HUD 视图控制器
    self.rootVC = [[HUDRootViewController alloc] init];
    self.touchVC = [[TouchViewController alloc] init];
    
    // 步骤2: 获取屏幕尺寸
    UIScreen *screen = [UIScreen mainScreen];
    CGRect screenBounds = screen.bounds;
    
    // 步骤3: 创建 HUD 窗口 (level 10000010 - 在游戏 UI 之上)
    // HUDMainWindow 标志: _isSystemWindow=YES, _isSecure=YES, _ignoresHitTest=YES
    self.hudWindow = [[HUDMainWindow alloc] initWithFrame:screenBounds];
    self.hudWindow.windowScene = scene;
    self.hudWindow.rootViewController = self.rootVC;
    self.hudWindow.windowLevel = 10000010.0; // 高于游戏窗口
    self.hudWindow.hidden = NO;
    [self.hudWindow makeKeyAndVisible];
    
    // 步骤4: 创建触摸窗口 (level 10000011 - 最高层, 捕获触摸)
    self.touchWindow = [[TouchMainWindow alloc] initWithFrame:screenBounds];
    self.touchWindow.windowScene = scene;
    self.touchWindow.hudController = self.rootVC;
    self.touchWindow.rootViewController = self.touchVC;
    self.touchWindow.windowLevel = 10000011.0; // 高于 HUD 窗口
    self.touchWindow.hidden = NO;
    [self.touchWindow makeKeyAndVisible];
    
    // 保存全局引用
    gTouchWindow = self.touchWindow;
    
    // 步骤5: 通过 SBSAccessibilityWindowHostingController 注册 (防检测)
    [self setupHostingController];
    
    // 步骤6: 同步方向
    [self.rootVC syncCurrentOrientation];
    
    // 步骤7: 注册 HID 事件回调
    [self registerHIDEventCallback];
    
    // 初始状态设为隐藏 (等待用户激活)
    self.hudWindow.hidden = YES;
    self.touchWindow.hidden = YES;
    self.showing = NO;
    
    NSLog(@"[HUD] Windows created: hudLevel=10000010 touchLevel=10000011");
}

- (void)setupHostingController {
    // 运行时解密 "SBSAccessibilityWindowHostingController"
    // 对应反编译: NSClassFromString(decryptedClassName)
    NSString *className = DecryptXMMString(encryptedClassName1, xorKeyClassName1);
    
    Class hostingClass = NSClassFromString(className);
    if (hostingClass) {
        self.hostingController = [[hostingClass alloc] init];
        
        // 附加 HUD 窗口
        if (self.hudWindow) {
            attachWindowToHostingController(self.hudWindow, self.hostingController);
        }
        
        // 附加触摸窗口
        if (self.touchWindow) {
            attachWindowToHostingController(self.touchWindow, self.hostingController);
        }
        
        NSLog(@"[HUD] Hosting controller setup: %@", className);
    } else {
        NSLog(@"[HUD] Hosting class not available (iOS < 14?)");
    }
}

- (void)registerHIDEventCallback {
    // 注册 IOHIDEventSystemClient 回调
    // 对应反编译: dispatch_once + HID 回调注册
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [[HIDEventManager shared] registerEventCallback];
    });
}

- (void)show {
    self.hudWindow.hidden = NO;
    self.touchWindow.hidden = NO;
    self.showing = YES;
    
    // 播放入场动画
    [self.rootVC prepareForEntryAnimation];
    
    NSLog(@"[HUD] Shown");
}

- (void)hide {
    self.hudWindow.hidden = YES;
    self.touchWindow.hidden = YES;
    self.showing = NO;
    
    NSLog(@"[HUD] Hidden");
}

- (void)syncTouchWindowToPanel {
    // 同步触摸窗口位置到面板
    if (self.touchWindow && self.hudWindow) {
        self.touchWindow.frame = self.hudWindow.frame;
        self.touchWindow.hudController = self.rootVC;
    }
}

@end

// sub_10000A514 - 窗口附加到托管控制器
void attachWindowToHostingController(UIWindow *window, id hostingController) {
    if (!window || !hostingController) return;
    
    SEL selector = NSSelectorFromString(@"registerWindow:");
    if ([hostingController respondsToSelector:selector]) {
        IMP imp = [hostingController methodForSelector:selector];
        void (*func)(id, SEL, id) = (void *)imp;
        func(hostingController, selector, window);
    }
}
