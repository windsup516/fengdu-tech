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
#import "GameHooks.h"
#import <objc/runtime.h>
#import <UIKit/UIKit.h>

// UIWindow 私有方法声明
@interface UIWindow (Private)
- (unsigned int)_contextId;
@end

// attachWindowToHostingController 前置声明
void attachWindowToHostingController(UIWindow *window, id hostingController);

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

// 加密的 registerWindow:contextID:windowLevel: 类型编码 (原版: byte_10134CF9X XOR 解密)
// "v32@0:8@16Q24d28" — void, id+selector+id+uint64+double
static const uint8_t encryptedTypeEncoding1[6] = {0x9E, 0xE4, 0x6D, 0x1F, 0x27, 0x17};
static const uint8_t xorKeyTypeEncoding1[6]    = {0x9E, 0xE4, 0x6D, 0x1F, 0x27, 0x17}; // 自反

// 加密的方法选择器名 (原版: xmmword_10134CFA0/C0 XOR 解密)
static const int8_t encryptedSelectorPart1[16] = {0};  // 从反编译 xmmword_10134CFA0
static const int8_t xorKeySelectorPart1[16]    = {0};   // 从反编译 xmmword_100122920
static const int8_t encryptedSelectorPart2[16] = {0};  // 从反编译 xmmword_10134CFB0
static const int8_t xorKeySelectorPart2[16]    = {0};   // 从反编译 xmmword_100122930
static const int8_t encryptedSelectorPart3     = 0x85;  // byte_10134CFC0
static const uint8_t xorKeySelectorPart3       = 0x85;

@interface HUDController ()
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
    // 对应反编译: _initWithFrame:attached: → commonInit
    self.hudWindow = [[HUDMainWindow alloc] initWithFrame:screenBounds];
    self.hudWindow.windowScene = scene;
    self.hudWindow.rootViewController = self.rootVC;
    self.hudWindow.windowLevel = 10000010.0;
    self.hudWindow.hidden = NO;
    [self.hudWindow makeKeyAndVisible];

    // 步骤4: 创建触摸窗口 (level 10000011 - 最高层)
    self.touchWindow = [[TouchMainWindow alloc] initWithFrame:screenBounds];
    self.touchWindow.windowScene = scene;
    self.touchWindow.hudController = self.rootVC;
    self.touchWindow.rootViewController = self.touchVC;
    self.touchWindow.windowLevel = 10000011.0;
    self.touchWindow.hidden = NO;
    [self.touchWindow makeKeyAndVisible];

    // 保存全局引用
    gTouchWindow = self.touchWindow;

    // 步骤5: 通过 SBSAccessibilityWindowHostingController 注册 (防检测)
    [self setupHostingController];

    // 步骤6: 初始隐藏 (注册完后再隐藏)
    self.hudWindow.hidden = YES;
    self.touchWindow.hidden = YES;
    self.showing = NO;

    // 步骤7: 同步方向
    [self.rootVC syncCurrentOrientation];

    // 步骤8: 注册 HID 事件回调
    [self registerHIDEventCallback];

    NSLog(@"[HUD] Windows created: hudLevel=10000010 touchLevel=10000011");
}

- (void)setupHostingController {
    static NSString *className = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        className = DecryptSBSClassName(
            encryptedClassNamePart1, xorKeyClassNamePart1,
            encryptedClassNamePart2, xorKeyClassNamePart2,
            encryptedClassNamePart3, xorKeyClassNamePart3
        );
    });

    Class hostingClass = NSClassFromString(className);
    if (hostingClass) {
        self.hostingController = [[hostingClass alloc] init];

        if (self.hudWindow) {
            attachWindowToHostingController(self.hudWindow, self.hostingController);
        }
        if (self.touchWindow) {
            attachWindowToHostingController(self.touchWindow, self.hostingController);
        }

        NSLog(@"[HUD] Hosting controller setup: %@", className);
    } else {
        NSLog(@"[HUD] Hosting class not available (iOS < 14?)");
    }
}

- (void)registerHIDEventCallback {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [[HIDEventManager shared] registerEventCallback];
    });
}

- (void)show {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.hudWindow.hidden = NO;
        self.touchWindow.hidden = NO;
        self.showing = YES;

        [self.rootVC prepareForEntryAnimation];
    });

    // 后台附加游戏进程
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        int result = hooks_attach_to_game();
        if (result == 0) {
            NSLog(@"[HUD] Game attached, scanning offsets...");
            hooks_scan_offsets();
        } else {
            NSLog(@"[HUD] Game attach failed (err=%d), overlay only mode", result);
        }
    });

    NSLog(@"[HUD] Shown");
}

- (void)hide {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.hudWindow.hidden = YES;
        self.touchWindow.hidden = YES;
        self.showing = NO;
    });
    NSLog(@"[HUD] Hidden");
}

- (void)syncTouchWindowToPanel {
    if (self.touchWindow && self.hudWindow) {
        self.touchWindow.frame = self.hudWindow.frame;
        self.touchWindow.hudController = self.rootVC;
    }
}

@end

// ====== attachWindowToHostingController ======
// 原版 sub_10000A514 — 使用 NSInvocation 调用 registerWindow:contextID:windowLevel:
// 不是简单的 registerWindow: (单参数), 而是传递 _contextId + windowLevel
void attachWindowToHostingController(UIWindow *window, id hostingController) {
    if (!window || !hostingController) return;

    SEL registerSel = NSSelectorFromString(@"registerWindow:contextID:windowLevel:");
    if (![hostingController respondsToSelector:registerSel]) {
        NSLog(@"[HUD] Hosting controller does not respond to registerWindow:contextID:windowLevel:");
        return;
    }

    // 获取窗口的 _contextId (UIScene 上下文 ID)
    unsigned int contextId = 0;
    if ([window respondsToSelector:@selector(_contextId)]) {
        contextId = (unsigned int)[window _contextId];
    }

    double winLevel = window.windowLevel;

    NSMethodSignature *sig = [NSMethodSignature signatureWithObjCTypes:"v32@0:8@16Q24d28"];

    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    [inv setTarget:hostingController];
    [inv setSelector:registerSel];
    [inv setArgument:&window atIndex:2];
    [inv setArgument:&contextId atIndex:3];
    [inv setArgument:&winLevel atIndex:4];
    [inv invoke];

    NSLog(@"[HUD] Window registered via NSInvocation: ctx=%u level=%.0f", contextId, winLevel);
}
