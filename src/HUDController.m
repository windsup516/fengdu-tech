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

    if (!scene) {
        HUD_LOG(@"createWindowsOnScene: scene nil, trying fallback");
        scene = [UIApplication sharedApplication].connectedScenes.anyObject;
        if (!scene) {
            HUD_LOG(@"createWindowsOnScene FATAL: no connected scenes");
            self.windowsCreated = NO;
            return;
        }
    }

    @try {
        self.rootVC = [[HUDRootViewController alloc] init];
        self.touchVC = [[TouchViewController alloc] init];
        UIScreen *screen = [UIScreen mainScreen];
        CGRect screenBounds = screen.bounds;

        self.hudWindow = [[HUDMainWindow alloc] initWithFrame:screenBounds];
        self.hudWindow.windowScene = scene;
        self.hudWindow.rootViewController = self.rootVC;
        self.hudWindow.hidden = NO;
        [self.hudWindow makeKeyAndVisible];
        self.hudWindow.windowLevel = 10000010.0;

        self.touchWindow = [[TouchMainWindow alloc] initWithFrame:screenBounds];
        self.touchWindow.windowScene = scene;
        self.touchWindow.hudController = self.rootVC;
        self.touchWindow.rootViewController = self.touchVC;
        self.touchWindow.hidden = NO;
        [self.touchWindow makeKeyAndVisible];
        self.touchWindow.windowLevel = 10000011.0;

        gTouchWindow = self.touchWindow;

        @try { [self setupHostingController]; }
        @catch (NSException *e) { HUD_LOG(@"Hosting setup failed: %@", e); }

        [self.rootVC syncCurrentOrientation];
        [self setupBackgroundKeepAlive];

        @try { [self registerHIDEventCallback]; }
        @catch (NSException *e) { HUD_LOG(@"HID callback failed: %@", e); }

        HUD_LOG(@"Windows created: hudLevel=10000010 touchLevel=10000011");
    } @catch (NSException *e) {
        HUD_LOG(@"createWindowsOnScene FATAL: %@", e);
        self.windowsCreated = NO;
    }
}

- (void)setupHostingController {
    Class hostingClass = NSClassFromString(@"SBSAccessibilityWindowHostingController");

    if (hostingClass) {
        self.hostingController = [[hostingClass alloc] init];

        if (self.hudWindow)
            attachWindowToHostingController(self.hudWindow, self.hostingController);
        if (self.touchWindow)
            attachWindowToHostingController(self.touchWindow, self.hostingController);

        HUD_LOG(@"SBS hosting initialized");
    } else {
        HUD_LOG(@"SBS hosting UNAVAILABLE — fallback mode");
    }
}

- (void)setupBackgroundKeepAlive {
    __weak typeof(self) weakSelf = self;

    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillResignActiveNotification
                                                       object:nil queue:[NSOperationQueue mainQueue]
                                                   usingBlock:^(NSNotification *note) {
        [weakSelf.rootVC syncCurrentOrientation];
        if (weakSelf.hostingController) {
            if (weakSelf.hudWindow) attachWindowToHostingController(weakSelf.hudWindow, weakSelf.hostingController);
            if (weakSelf.touchWindow) attachWindowToHostingController(weakSelf.touchWindow, weakSelf.hostingController);
        }
        weakSelf.hudWindow.hidden = NO;
        weakSelf.touchWindow.hidden = NO;
        weakSelf.hudWindow.windowLevel = 10000010.0;
        weakSelf.touchWindow.windowLevel = 10000011.0;
    }];

    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidEnterBackgroundNotification
                                                       object:nil queue:[NSOperationQueue mainQueue]
                                                   usingBlock:^(NSNotification *note) {
        unsigned int hudCtx = 0, touchCtx = 0;
        if (weakSelf.hudWindow && [weakSelf.hudWindow respondsToSelector:@selector(_contextId)])
            hudCtx = (unsigned int)[weakSelf.hudWindow _contextId];
        if (weakSelf.touchWindow && [weakSelf.touchWindow respondsToSelector:@selector(_contextId)])
            touchCtx = (unsigned int)[weakSelf.touchWindow _contextId];
        HUD_LOG(@"Entered background: hudCtx=%u touchCtx=%u — %s",
                hudCtx, touchCtx,
                (hudCtx == 0) ? "DEAD" : "alive");
    }];

    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                       object:nil queue:[NSOperationQueue mainQueue]
                                                   usingBlock:^(NSNotification *note) {
        if (!weakSelf.showing) return;
        weakSelf.hudWindow.hidden = NO;
        weakSelf.touchWindow.hidden = NO;
        weakSelf.hudWindow.windowLevel = 10000010.0;
        weakSelf.touchWindow.windowLevel = 10000011.0;

        unsigned int hudCtx = 0, touchCtx = 0;
        if (weakSelf.hudWindow && [weakSelf.hudWindow respondsToSelector:@selector(_contextId)])
            hudCtx = (unsigned int)[weakSelf.hudWindow _contextId];
        if (weakSelf.touchWindow && [weakSelf.touchWindow respondsToSelector:@selector(_contextId)])
            touchCtx = (unsigned int)[weakSelf.touchWindow _contextId];

        if (hudCtx == 0 || touchCtx == 0)
            HUD_LOG(@"Became active: hudCtx=%u touchCtx=%u — DEAD", hudCtx, touchCtx);
        else
            [weakSelf reRegisterSBSHosting];
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
        HUD_LOG(@"SBS contextId lost (hud=%u touch=%u) — starting retry loop", hudCtx, touchCtx);

        [self.sbsRetryTimer invalidate];
        self.sbsRetryTimer = nil;

        __weak typeof(self) weakSelf = self;
        __block int retryCount = 0;
        self.sbsRetryTimer = [NSTimer scheduledTimerWithTimeInterval:3.0 repeats:YES block:^(NSTimer *timer) {
            retryCount++;
            unsigned int hc = 0, tc = 0;
            if (weakSelf.hudWindow && [weakSelf.hudWindow respondsToSelector:@selector(_contextId)])
                hc = (unsigned int)[weakSelf.hudWindow _contextId];
            if (weakSelf.touchWindow && [weakSelf.touchWindow respondsToSelector:@selector(_contextId)])
                tc = (unsigned int)[weakSelf.touchWindow _contextId];

            if (hc != 0 && tc != 0) {
                HUD_LOG(@"SBS contextId recovered after %d retries", retryCount);
                [timer invalidate];
                weakSelf.sbsRetryTimer = nil;
                if (weakSelf.hudWindow) attachWindowToHostingController(weakSelf.hudWindow, weakSelf.hostingController);
                if (weakSelf.touchWindow) attachWindowToHostingController(weakSelf.touchWindow, weakSelf.hostingController);
                return;
            }

            if (retryCount >= 10) {
                HUD_LOG(@"SBS recovery FAILED: %d retries exhausted, hudCtx=%u touchCtx=%u", retryCount, hc, tc);
                [timer invalidate];
                weakSelf.sbsRetryTimer = nil;
            }
        }];
        return;
    }

    if (self.hudWindow)
        attachWindowToHostingController(self.hudWindow, self.hostingController);
    if (self.touchWindow)
        attachWindowToHostingController(self.touchWindow, self.hostingController);
}

- (void)show {
    void (^showBlock)(void) = ^{
        self.hudWindow.hidden = NO;
        self.touchWindow.hidden = NO;
        self.hudWindow.windowLevel = 10000010.0;
        self.touchWindow.windowLevel = 10000011.0;
        self.showing = YES;
        [self.rootVC prepareForEntryAnimation];
        HUD_LOG(@"HUD shown");
    };

    if ([NSThread isMainThread]) {
        showBlock();
    } else {
        dispatch_async(dispatch_get_main_queue(), showBlock);
    }
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
        unsigned int contextId = 0;
        if ([window respondsToSelector:@selector(_contextId)]) {
            contextId = (unsigned int)[window _contextId];
        }

        if (contextId == 0) return;

        double winLevel = window.windowLevel;
        static unsigned int lastRegCtx = 0;
        static double lastRegLevel = 0;
        BOOL changed = (contextId != lastRegCtx || winLevel != lastRegLevel);

        if (changed) {
            HUD_LOG(@"SBS register: %@ ctx=%u level=%.0f",
                    NSStringFromClass([window class]), contextId, winLevel);
            lastRegCtx = contextId;
            lastRegLevel = winLevel;
        }

        // Prefer 3-arg: registerWindow:contextID:windowLevel:
        SEL sel3 = NSSelectorFromString(@"registerWindow:contextID:windowLevel:");
        if ([hostingController respondsToSelector:sel3]) {
            NSMethodSignature *sig = [NSMethodSignature signatureWithObjCTypes:"v@:@Id"];
            NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
            [inv setTarget:hostingController];
            [inv setSelector:sel3];
            [inv setArgument:&window atIndex:2];
            [inv setArgument:&contextId atIndex:3];
            [inv setArgument:&winLevel atIndex:4];
            [inv invoke];
            if (changed) {
                BOOL result = NO;
                if ([[inv methodSignature] methodReturnLength] > 0)
                    [inv getReturnValue:&result];
                HUD_LOG(@"SBS 3-arg result=%d", result);
            }
            return;
        }

        // Fallback: 2-arg registerWindowWithContextID:atLevel:
        SEL sel2 = NSSelectorFromString(@"registerWindowWithContextID:atLevel:");
        if ([hostingController respondsToSelector:sel2]) {
            NSMethodSignature *sig = [NSMethodSignature signatureWithObjCTypes:"v@:Id"];
            NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
            [inv setTarget:hostingController];
            [inv setSelector:sel2];
            [inv setArgument:&contextId atIndex:2];
            [inv setArgument:&winLevel atIndex:3];
            [inv invoke];
            if (changed) {
                BOOL result = NO;
                if ([[inv methodSignature] methodReturnLength] > 0)
                    [inv getReturnValue:&result];
                HUD_LOG(@"SBS 2-arg result=%d", result);
            }
            return;
        }

        HUD_LOG(@"SBS: no known selector responds");
    } @catch (NSException *e) {
        HUD_LOG(@"SBS attach failed: %@", e);
    }
}

// contextId heartbeat accessors for HUDRootViewController diagnostics
static unsigned int g_lastHudCtx = 0;
static unsigned int g_lastTouchCtx = 0;

unsigned int hudWindowContextId(void) {
    HUDController *hc = [HUDController shared];
    if (hc.hudWindow && [hc.hudWindow respondsToSelector:@selector(_contextId)]) {
        g_lastHudCtx = (unsigned int)[hc.hudWindow _contextId];
    }
    return g_lastHudCtx;
}

unsigned int touchWindowContextId(void) {
    HUDController *hc = [HUDController shared];
    if (hc.touchWindow && [hc.touchWindow respondsToSelector:@selector(_contextId)]) {
        g_lastTouchCtx = (unsigned int)[hc.touchWindow _contextId];
    }
    return g_lastTouchCtx;
}

// SBS 恢复触发器 — 由 HUDRootViewController 在 contextId 变 0 时调用
// 1. 直接重注册现有窗口 (可能已有新 contextId)
// 2. 也调用 reRegisterSBSHosting 走完整恢复逻辑
void hudTriggerSBSRecovery(void) {
    HUDController *hc = [HUDController shared];
    if (!hc.hostingController) {
        [hc setupHostingController];
        return;
    }

    unsigned int hudCtx = 0, touchCtx = 0;
    if (hc.hudWindow && [hc.hudWindow respondsToSelector:@selector(_contextId)])
        hudCtx = (unsigned int)[hc.hudWindow _contextId];
    if (hc.touchWindow && [hc.touchWindow respondsToSelector:@selector(_contextId)])
        touchCtx = (unsigned int)[hc.touchWindow _contextId];

    HUD_LOG(@"SBS recovery: hudCtx=%u touchCtx=%u", hudCtx, touchCtx);

    if (hudCtx != 0 || touchCtx != 0) {
        if (hc.hudWindow && hudCtx != 0)
            attachWindowToHostingController(hc.hudWindow, hc.hostingController);
        if (hc.touchWindow && touchCtx != 0)
            attachWindowToHostingController(hc.touchWindow, hc.hostingController);
    } else {
        [hc reRegisterSBSHosting];
    }
}
