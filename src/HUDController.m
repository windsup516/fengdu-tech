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
#import "Logging.h"
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

    NSLog(@"[HUD] createWindowsOnScene called, scene=%@", scene);

    // 确保在主线程 + 窗口 scene 已就绪
    if (!scene) {
        HUD_LOG(@"createWindowsOnScene: scene is nil, aborting");
        NSLog(@"[HUD] FATAL: scene is nil, trying fallback");
        scene = [UIApplication sharedApplication].connectedScenes.anyObject;
        if (!scene) {
            NSLog(@"[HUD] FATAL: no connected scenes at all");
            self.windowsCreated = NO;
            return;
        }
        NSLog(@"[HUD] fallback scene found: %@", scene);
    }

    @try {
        // 步骤1: 创建 HUD 视图控制器
        self.rootVC = [[HUDRootViewController alloc] init];
        self.touchVC = [[TouchViewController alloc] init];

        // 步骤2: 获取屏幕尺寸
        UIScreen *screen = [UIScreen mainScreen];
        CGRect screenBounds = screen.bounds;

        // 步骤3: 创建 HUD 窗口 (level 10000010)
        self.hudWindow = [[HUDMainWindow alloc] initWithFrame:screenBounds];
        self.hudWindow.windowScene = scene;
        self.hudWindow.rootViewController = self.rootVC;
        self.hudWindow.hidden = NO;
        [self.hudWindow makeKeyAndVisible];
        self.hudWindow.windowLevel = 10000010.0;  // set AFTER makeKeyAndVisible (it resets level)

        // 步骤4: 创建触摸窗口 (level 10000011)
        self.touchWindow = [[TouchMainWindow alloc] initWithFrame:screenBounds];
        self.touchWindow.windowScene = scene;
        self.touchWindow.hudController = self.rootVC;
        self.touchWindow.rootViewController = self.touchVC;
        self.touchWindow.hidden = NO;
        [self.touchWindow makeKeyAndVisible];
        self.touchWindow.windowLevel = 10000011.0;  // set AFTER makeKeyAndVisible

        gTouchWindow = self.touchWindow;

        // 步骤5: SBS 托管 (可能失败，非致命)
        @try {
            [self setupHostingController];
        } @catch (NSException *e) {
            HUD_LOG(@"Hosting controller setup failed: %@", e);
        }

        // 步骤6: 同步方向
        [self.rootVC syncCurrentOrientation];

        // 步骤7: 后台保活 (SBS 不可用时的备选方案)
        [self setupBackgroundKeepAlive];

        // 步骤8: HID 回调 (可能失败，非致命)
        @try {
            [self registerHIDEventCallback];
        } @catch (NSException *e) {
            HUD_LOG(@"HID callback registration failed: %@", e);
        }

        HUD_LOG(@"Windows created: hudLevel=10000010 touchLevel=10000011");
    } @catch (NSException *e) {
        HUD_LOG(@"createWindowsOnScene FATAL: %@", e);
        self.windowsCreated = NO;
    }
}

- (void)setupHostingController {
    Class hostingClass = NSClassFromString(@"SBSAccessibilityWindowHostingController");

    HUD_LOG(@"SBS class lookup: %@", hostingClass ? NSStringFromClass(hostingClass) : @"NIL");

    if (hostingClass) {
        self.hostingController = [[hostingClass alloc] init];

        if (self.hudWindow) {
            // 获取窗口诊断信息
            unsigned int hudCtx = 0;
            if ([self.hudWindow respondsToSelector:@selector(_contextId)]) {
                hudCtx = (unsigned int)[self.hudWindow _contextId];
            }
            HUD_LOG(@"HUD window ctx=%u level=%.0f", hudCtx, self.hudWindow.windowLevel);
            attachWindowToHostingController(self.hudWindow, self.hostingController);
        }
        if (self.touchWindow) {
            unsigned int touchCtx = 0;
            if ([self.touchWindow respondsToSelector:@selector(_contextId)]) {
                touchCtx = (unsigned int)[self.touchWindow _contextId];
            }
            HUD_LOG(@"Touch window ctx=%u level=%.0f", touchCtx, self.touchWindow.windowLevel);
            attachWindowToHostingController(self.touchWindow, self.hostingController);
        }

        HUD_LOG(@"SBS hosting OK: %@", NSStringFromClass(hostingClass));
    } else {
        HUD_LOG(@"SBS hosting UNAVAILABLE on this iOS — will use background keep-alive fallback");
    }
}

- (void)setupBackgroundKeepAlive {
    __weak typeof(self) weakSelf = self;

    // 退后台: 只保窗口属性，绝不调 makeKeyAndVisible（会触发 render server 回收 contextId）
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillResignActiveNotification
                                                       object:nil
                                                        queue:[NSOperationQueue mainQueue]
                                                   usingBlock:^(NSNotification *note) {
        HUD_LOG(@"App will resign active — syncing orientation + preserving window state");
        [weakSelf.rootVC syncCurrentOrientation];
        HUD_LOG(@"Screen after sync: %.0fx%.0f scale=%.1f",
                [HUDRootViewController screenWidth],
                [HUDRootViewController screenHeight],
                [HUDRootViewController screenScale]);
        // 只设 hidden + level, makeKeyAndVisible 会杀死 contextId
        weakSelf.hudWindow.hidden = NO;
        weakSelf.touchWindow.hidden = NO;
        weakSelf.hudWindow.windowLevel = 10000010.0;
        weakSelf.touchWindow.windowLevel = 10000011.0;
    }];

    // 回到前台: 检查 contextId 恢复情况
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                       object:nil
                                                        queue:[NSOperationQueue mainQueue]
                                                   usingBlock:^(NSNotification *note) {
        if (!weakSelf.showing) return;
        weakSelf.hudWindow.hidden = NO;
        weakSelf.touchWindow.hidden = NO;
        weakSelf.hudWindow.windowLevel = 10000010.0;
        weakSelf.touchWindow.windowLevel = 10000011.0;

        // 回到前台后验证 contextId，如果恢复了就重新注册 SBS
        unsigned int hudCtx = 0, touchCtx = 0;
        if (weakSelf.hudWindow && [weakSelf.hudWindow respondsToSelector:@selector(_contextId)])
            hudCtx = (unsigned int)[weakSelf.hudWindow _contextId];
        if (weakSelf.touchWindow && [weakSelf.touchWindow respondsToSelector:@selector(_contextId)])
            touchCtx = (unsigned int)[weakSelf.touchWindow _contextId];

        HUD_LOG(@"Become active: hudCtx=%u touchCtx=%u", hudCtx, touchCtx);
        if (hudCtx != 0 && touchCtx != 0) {
            [weakSelf reRegisterSBSHosting];
        }
    }];
}

- (void)registerHIDEventCallback {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [[HIDEventManager shared] registerEventCallback];
    });
}

- (void)reRegisterSBSHosting {
    // 确保 hosting controller 存在
    if (!self.hostingController) {
        HUD_LOG(@"reRegisterSBS: no hosting controller, initializing...");
        [self setupHostingController];
        return;
    }

    // 获取当前 contextId
    unsigned int hudCtx = 0, touchCtx = 0;
    if (self.hudWindow && [self.hudWindow respondsToSelector:@selector(_contextId)]) {
        hudCtx = (unsigned int)[self.hudWindow _contextId];
    }
    if (self.touchWindow && [self.touchWindow respondsToSelector:@selector(_contextId)]) {
        touchCtx = (unsigned int)[self.touchWindow _contextId];
    }

    if (hudCtx == 0 || touchCtx == 0) {
        // contextId 丢失 — 后台状态重建窗口拿不到新 context，不重建，改为定时重试
        HUD_LOG(@"reRegisterSBS: contextId lost (hud=%u touch=%u) — scheduling retry, NOT recreating", hudCtx, touchCtx);

        // 取消之前的重试定时器
        [self.sbsRetryTimer invalidate];
        self.sbsRetryTimer = nil;

        // 每 3 秒重试一次，最多 10 次 (30秒)
        __weak typeof(self) weakSelf = self;
        __block int retryCount = 0;
        self.sbsRetryTimer = [NSTimer scheduledTimerWithTimeInterval:3.0 repeats:YES block:^(NSTimer *timer) {
            retryCount++;
            unsigned int hc = 0, tc = 0;
            if (weakSelf.hudWindow && [weakSelf.hudWindow respondsToSelector:@selector(_contextId)])
                hc = (unsigned int)[weakSelf.hudWindow _contextId];
            if (weakSelf.touchWindow && [weakSelf.touchWindow respondsToSelector:@selector(_contextId)])
                tc = (unsigned int)[weakSelf.touchWindow _contextId];

            HUD_LOG(@"SBS retry #%d: hudCtx=%u touchCtx=%u", retryCount, hc, tc);

            if (hc != 0 && tc != 0) {
                HUD_LOG(@"SBS contextId recovered after %d retries — registering", retryCount);
                [timer invalidate];
                weakSelf.sbsRetryTimer = nil;
                if (weakSelf.hudWindow) attachWindowToHostingController(weakSelf.hudWindow, weakSelf.hostingController);
                if (weakSelf.touchWindow) attachWindowToHostingController(weakSelf.touchWindow, weakSelf.hostingController);
                return;
            }

            if (retryCount >= 10) {
                HUD_LOG(@"SBS retry exhausted (%d attempts) — contextId never recovered", retryCount);
                [timer invalidate];
                weakSelf.sbsRetryTimer = nil;
            }
        }];
        return;
    }

    // contextId 有效 — 直接重注册
    HUD_LOG(@"reRegisterSBS: contextId valid (hud=%u touch=%u), re-registering...", hudCtx, touchCtx);
    if (self.hudWindow) {
        attachWindowToHostingController(self.hudWindow, self.hostingController);
    }
    if (self.touchWindow) {
        attachWindowToHostingController(self.touchWindow, self.hostingController);
    }
}

- (void)show {
    NSLog(@"[HUD] show called, windowsCreated=%d hudWindow=%@ touchWindow=%@",
          self.windowsCreated, self.hudWindow, self.touchWindow);

    void (^showBlock)(void) = ^{
        self.hudWindow.hidden = NO;
        self.touchWindow.hidden = NO;
        self.hudWindow.windowLevel = 10000010.0;
        self.touchWindow.windowLevel = 10000011.0;
        self.showing = YES;
        [self.rootVC prepareForEntryAnimation];
        HUD_LOG(@"Windows now visible (hudLevel=%.0f touchLevel=%.0f)",
                self.hudWindow.windowLevel, self.touchWindow.windowLevel);
        NSLog(@"[HUD] Windows set visible: hudLevel=%.0f touchLevel=%.0f",
              self.hudWindow.windowLevel, self.touchWindow.windowLevel);
    };

    if ([NSThread isMainThread]) {
        showBlock();
    } else {
        NSLog(@"[HUD] show called from background thread, dispatching to main");
        dispatch_async(dispatch_get_main_queue(), showBlock);
    }

    HUD_LOG(@"Shown");
}

- (void)hide {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.hudWindow.hidden = YES;
        self.touchWindow.hidden = YES;
        self.showing = NO;
    });
    HUD_LOG(@"Hidden");
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

    @try {
        // 太阳神使用 registerWindowWithContextID:atLevel: 而非 registerWindow:contextID:windowLevel:
        SEL registerSel = NSSelectorFromString(@"registerWindowWithContextID:atLevel:");
        if (![hostingController respondsToSelector:registerSel]) {
            HUD_LOG(@"Hosting controller does NOT respond to registerWindowWithContextID:atLevel:");
            return;
        }
        HUD_LOG(@"Hosting controller responds to registerWindowWithContextID:atLevel: ✓");

        // 获取窗口的 _contextId (UIScene 上下文 ID)
        unsigned int contextId = 0;
        if ([window respondsToSelector:@selector(_contextId)]) {
            contextId = (unsigned int)[window _contextId];
        }
        HUD_LOG(@"Window _contextId=%u level=%.0f class=%@", contextId, window.windowLevel, NSStringFromClass([window class]));

        // contextId=0 表示窗口上下文已丢失 (切后台后可能出现), 跳过注册
        if (contextId == 0) {
            HUD_LOG(@"Skipping SBS registration: contextId=0 (window context lost)");
            return;
        }

        double winLevel = window.windowLevel;

        // 太阳神使用简化类型编码 v@:Id (void, id, SEL, unsigned int, double)
        NSMethodSignature *sig = [NSMethodSignature signatureWithObjCTypes:"v@:Id"];

        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
        [inv setTarget:hostingController];
        [inv setSelector:registerSel];
        // 只传 contextID + level，不传 window 对象 (SBS 通过 contextID 识别窗口)
        [inv setArgument:&contextId atIndex:2];
        [inv setArgument:&winLevel atIndex:3];
        [inv invoke];

        HUD_LOG(@"Window registered via NSInvocation: ctx=%u level=%.0f", contextId, winLevel);
    } @catch (NSException *e) {
        HUD_LOG(@"attachWindowToHostingController failed: %@", e);
    }
}
