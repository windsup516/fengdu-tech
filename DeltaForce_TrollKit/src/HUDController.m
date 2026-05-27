// HUDController - 作弊覆盖层管理器
// 基于反编译: createWindowsOnScene / registerHIDEventCallback
// 使用 SBSAccessibilityWindowHostingController 躲避检测
// 双窗口架构: HUDMainWindow(菜单) + TouchMainWindow(触摸)

#import "HUDController.h"
#import "HUDMainWindow.h"
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
// 运行时通过 NEON XOR (veorq_s8/veor_s8) 解密, 匹配原版反编译
//
// 原版地址:
//   xmmword_10134CF10 ^ xmmword_100122900  (前16字节)
//   xmmword_10134CF20 ^ xmmword_100122910  (后16字节)
//   qword_10134CF30  ^ 0x3BD3649011612E66  (最后8字节)

// 第1段: 加密的16字节 (xmmword_10134CF10)
static const int8_t encryptedClassNamePart1[16] = {
    0x4A, 0x4C, 0x4E, 0x43, 0x4F, 0x0E, 0x45, 0x0D,
    0x0E, 0x46, 0x4F, 0x07, 0x01, 0x0B, 0x06, 0x04
};
// 第1段: XOR密钥 (xmmword_100122900)
static const int8_t xorKeyClassNamePart1[16] = {
    0x2A, 0x2C, 0x2E, 0x23, 0x2F, 0x6E, 0x25, 0x6D,
    0x6E, 0x26, 0x2F, 0x67, 0x61, 0x6B, 0x66, 0x64
};

// 第2段: 加密的16字节 (xmmword_10134CF20)
static const int8_t encryptedClassNamePart2[16] = {
    0x21, 0x04, 0x1A, 0x46, 0x59, 0x11, 0x1C, 0x46,
    0x11, 0x0E, 0x1F, 0x53, 0x4E, 0x0E, 0x08, 0x01
};
// 第2段: XOR密钥 (xmmword_100122910)
static const int8_t xorKeyClassNamePart2[16] = {
    0x01, 0x64, 0x7A, 0x26, 0x39, 0x71, 0x7C, 0x26,
    0x71, 0x6E, 0x7F, 0x33, 0x2E, 0x6E, 0x68, 0x61
};

// 第3段: 加密的8字节 (qword_10134CF30)
static const int8_t encryptedClassNamePart3[8] = {
    0x4A, 0x5B, 0x4C, 0x19, 0x1B, 0x7F, 0x65, 0x11
};
// 第3段: XOR密钥 (0x3BD3649011612E66)
static const int64_t xorKeyClassNamePart3 = 0x3BD3649011612E66;

// 对应反编译中的子函数 sub_10000A514 - 附加窗口到托管控制器
extern void attachWindowToHostingController(UIWindow *window, id hostingController);

@interface HUDController ()
// 所有属性已在 HUDController.h 中声明, 此处不再重复
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
    // ====== 运行时解密 "SBSAccessibilityWindowHostingController" ======
    // 使用 DecryptSBSClassName 便利函数 (三段 NEON XOR veorq_s8 + veor_s8)
    // dispatch_once 保护, 只解密一次
    
    static NSString *className = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        className = DecryptSBSClassName(
            encryptedClassNamePart1, xorKeyClassNamePart1,
            encryptedClassNamePart2, xorKeyClassNamePart2,
            encryptedClassNamePart3, xorKeyClassNamePart3
        );
    });
    
    // 对应反编译: NSClassFromString(decryptedHostingClassName)
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
