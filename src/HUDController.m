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

// 文件日志 — 与 main.m 的 SAFE_LOG 写入同一个文件
static FILE *g_hudLogFile = NULL;
static void hud_log(NSString *fmt, ...) {
    if (!g_hudLogFile) {
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        if (paths.count > 0) {
            NSString *logPath = [paths[0] stringByAppendingPathComponent:@"debug.log"];
            g_hudLogFile = fopen([logPath UTF8String], "a");
        }
    }
    va_list args;
    va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    fprintf(stderr, "[HUD] %s\n", [msg UTF8String]);
    if (g_hudLogFile) {
        time_t now = time(NULL);
        struct tm *tm_info = localtime(&now);
        char time_buf[16];
        strftime(time_buf, sizeof(time_buf), "%H:%M:%S", tm_info);
        fprintf(g_hudLogFile, "%s [HUD] %s\n", time_buf, [msg UTF8String]);
        fflush(g_hudLogFile);
    }
}

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

    // 确保在主线程 + 窗口 scene 已就绪
    if (!scene) {
        hud_log(@"createWindowsOnScene: scene is nil, aborting");
        self.windowsCreated = NO;
        return;
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
        self.hudWindow.windowLevel = 10000010.0;
        self.hudWindow.hidden = NO;
        [self.hudWindow makeKeyAndVisible];

        // 步骤4: 创建触摸窗口 (level 10000011)
        self.touchWindow = [[TouchMainWindow alloc] initWithFrame:screenBounds];
        self.touchWindow.windowScene = scene;
        self.touchWindow.hudController = self.rootVC;
        self.touchWindow.rootViewController = self.touchVC;
        self.touchWindow.windowLevel = 10000011.0;
        self.touchWindow.hidden = NO;
        [self.touchWindow makeKeyAndVisible];

        gTouchWindow = self.touchWindow;

        // 步骤5: SBS 托管 (可能失败，非致命)
        @try {
            [self setupHostingController];
        } @catch (NSException *e) {
            hud_log(@"Hosting controller setup failed: %@", e);
        }

        // 步骤6: 同步方向
        [self.rootVC syncCurrentOrientation];

        // 步骤7: 后台保活 (SBS 不可用时的备选方案)
        [self setupBackgroundKeepAlive];

        // 步骤8: HID 回调 (可能失败，非致命)
        @try {
            [self registerHIDEventCallback];
        } @catch (NSException *e) {
            hud_log(@"HID callback registration failed: %@", e);
        }

        hud_log(@"Windows created: hudLevel=10000010 touchLevel=10000011");
    } @catch (NSException *e) {
        hud_log(@"createWindowsOnScene FATAL: %@", e);
        self.windowsCreated = NO;
    }
}

- (void)setupHostingController {
    Class hostingClass = NSClassFromString(@"SBSAccessibilityWindowHostingController");

    hud_log(@"SBS class lookup: %@", hostingClass ? NSStringFromClass(hostingClass) : @"NIL");

    if (hostingClass) {
        self.hostingController = [[hostingClass alloc] init];

        if (self.hudWindow) {
            // 获取窗口诊断信息
            unsigned int hudCtx = 0;
            if ([self.hudWindow respondsToSelector:@selector(_contextId)]) {
                hudCtx = (unsigned int)[self.hudWindow _contextId];
            }
            hud_log(@"HUD window ctx=%u level=%.0f", hudCtx, self.hudWindow.windowLevel);
            attachWindowToHostingController(self.hudWindow, self.hostingController);
        }
        if (self.touchWindow) {
            unsigned int touchCtx = 0;
            if ([self.touchWindow respondsToSelector:@selector(_contextId)]) {
                touchCtx = (unsigned int)[self.touchWindow _contextId];
            }
            hud_log(@"Touch window ctx=%u level=%.0f", touchCtx, self.touchWindow.windowLevel);
            attachWindowToHostingController(self.touchWindow, self.hostingController);
        }

        hud_log(@"SBS hosting OK: %@", NSStringFromClass(hostingClass));
    } else {
        hud_log(@"SBS hosting UNAVAILABLE on this iOS — will use background keep-alive fallback");
    }
}

- (void)setupBackgroundKeepAlive {
    // SBS 托管不可用时的备选方案:
    // 使用后台任务 + 定期刷新窗口，尽可能保持窗口可见
    __weak typeof(self) weakSelf = self;
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillResignActiveNotification
                                                       object:nil
                                                        queue:[NSOperationQueue mainQueue]
                                                   usingBlock:^(NSNotification *note) {
        hud_log(@"App will resign active — forcing window refresh");
        // 延迟重新显示窗口 (等系统完成后台过渡)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            weakSelf.hudWindow.hidden = NO;
            weakSelf.touchWindow.hidden = NO;
            [weakSelf.hudWindow makeKeyAndVisible];
            [weakSelf.touchWindow makeKeyAndVisible];
            hud_log(@"Windows forced visible after background transition");
        });
    }];

    // 监听回到前台
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                       object:nil
                                                        queue:[NSOperationQueue mainQueue]
                                                   usingBlock:^(NSNotification *note) {
        if (weakSelf.showing) {
            weakSelf.hudWindow.hidden = NO;
            weakSelf.touchWindow.hidden = NO;
            hud_log(@"Windows restored on become active");
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
    // 在游戏启动后重新注册 SBS 托管
    // SBS 注册可能在 app 切后台时被清除，需要在游戏活跃时重新注册
    if (!self.hostingController) {
        hud_log(@"reRegisterSBS: no hosting controller, re-initializing...");
        [self setupHostingController];
        return;
    }

    hud_log(@"reRegisterSBS: re-registering both windows...");
    if (self.hudWindow) {
        attachWindowToHostingController(self.hudWindow, self.hostingController);
    }
    if (self.touchWindow) {
        attachWindowToHostingController(self.touchWindow, self.hostingController);
    }
    hud_log(@"reRegisterSBS: done");
}

- (void)show {
    void (^showBlock)(void) = ^{
        self.hudWindow.hidden = NO;
        self.touchWindow.hidden = NO;
        self.showing = YES;
        [self.rootVC prepareForEntryAnimation];
        hud_log(@"Windows now visible (hudLevel=%.0f touchLevel=%.0f)",
                self.hudWindow.windowLevel, self.touchWindow.windowLevel);
    };

    if ([NSThread isMainThread]) {
        showBlock();
    } else {
        dispatch_async(dispatch_get_main_queue(), showBlock);
    }

    hud_log(@"Shown");
}

- (void)hide {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.hudWindow.hidden = YES;
        self.touchWindow.hidden = YES;
        self.showing = NO;
    });
    hud_log(@"Hidden");
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
            hud_log(@"Hosting controller does NOT respond to registerWindowWithContextID:atLevel:");
            return;
        }
        hud_log(@"Hosting controller responds to registerWindowWithContextID:atLevel: ✓");

        // 获取窗口的 _contextId (UIScene 上下文 ID)
        unsigned int contextId = 0;
        if ([window respondsToSelector:@selector(_contextId)]) {
            contextId = (unsigned int)[window _contextId];
        }
        hud_log(@"Window _contextId=%u level=%.0f class=%@", contextId, window.windowLevel, NSStringFromClass([window class]));

        // contextId=0 表示窗口上下文已丢失 (切后台后可能出现), 跳过注册
        if (contextId == 0) {
            hud_log(@"Skipping SBS registration: contextId=0 (window context lost)");
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

        hud_log(@"Window registered via NSInvocation: ctx=%u level=%.0f", contextId, winLevel);
    } @catch (NSException *e) {
        hud_log(@"attachWindowToHostingController failed: %@", e);
    }
}
