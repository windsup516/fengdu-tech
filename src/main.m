// Stocks.app (伪装) - Delta Force 作弊框架
// TrollStore + 越狱兼容版本
// arm64 iOS 13.0-16.x
// 伪装为苹果股票应用 (com.apple.stocks)

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <time.h>
#import <stdarg.h>
#import <signal.h>
#import <execinfo.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <objc/message.h>
#import "LoginViewController.h"
#import "AppViewController.h"
#import "HUDController.h"
#import "GameHooks.h"
#import "XPFKernelInterface.h"

// 外部函数声明 (来自 ExternalStubs.c 的 WEAK 存根)
extern int jb_init(void);
extern int is_trollstore(void);
extern int is_jailbroken(void);
extern uint64_t physread64(uint64_t phys_addr);
extern int physwritebuf(uint64_t phys_addr, void *buffer, size_t size);
extern uint64_t phystokv(uint64_t phys_addr);

// ====== dylib 函数指针 — 运行时从 libjailbreak.dylib 解析真实实现 ======
// WEAK 存根在 ExternalStubs.c 中，dyld 会优先用它们。
// 我们必须通过 dlopen/dlsym 显式获取 dylib 的真实函数指针。
static int (*real_jb_init)(void) = NULL;
static uint64_t (*real_physread64)(uint64_t) = NULL;
static int (*real_physwritebuf)(uint64_t, void*, size_t) = NULL;
static uint64_t (*real_phystokv)(uint64_t) = NULL;
static int (*real_xpf_inject_dylib)(int, const char*) = NULL;

static void resolve_dylib_functions(void) {
    // 从可执行文件路径推算 Frameworks 目录
    char exePath[1024];
    uint32_t sz = (uint32_t)sizeof(exePath);
    if (_NSGetExecutablePath(exePath, &sz) != 0) return;

    // 构建 libjailbreak.dylib 的绝对路径
    NSString *exeStr = [NSString stringWithUTF8String:exePath];
    NSString *fwPath = [[[exeStr stringByDeletingLastPathComponent]
                         stringByAppendingPathComponent:@"Frameworks"]
                        stringByAppendingPathComponent:@"libjailbreak.dylib"];

    void *jbHandle = dlopen([fwPath UTF8String], RTLD_NOLOAD | RTLD_LAZY);
    if (!jbHandle) {
        // 尝试用 @rpath
        jbHandle = dlopen("@rpath/libjailbreak.dylib", RTLD_NOLOAD | RTLD_LAZY);
    }

    if (jbHandle) {
        real_jb_init = dlsym(jbHandle, "jb_init");
        real_physread64 = dlsym(jbHandle, "physread64");
        real_physwritebuf = dlsym(jbHandle, "physwritebuf");
        real_phystokv = dlsym(jbHandle, "phystokv");
        real_xpf_inject_dylib = dlsym(jbHandle, "xpf_inject_dylib");
        fprintf(stderr, "[main] Resolved dylib funcs: jb_init=%p physread64=%p\n",
                (void*)real_jb_init, (void*)real_physread64);
    } else {
        fprintf(stderr, "[main] libjailbreak.dylib not loaded (err=%s)\n", dlerror());
    }
}

// 包装函数 — 优先用 dylib 版本，fallback 到 WEAK 存根
static int call_jb_init(void) {
    if (real_jb_init) return real_jb_init();
    return jb_init(); // WEAK stub
}

__attribute__((unused))
static uint64_t call_physread64(uint64_t addr) {
    if (real_physread64) return real_physread64(addr);
    return physread64(addr);
}

__attribute__((unused))
static int call_physwritebuf(uint64_t addr, void *buf, size_t sz) {
    if (real_physwritebuf) return real_physwritebuf(addr, buf, sz);
    return physwritebuf(addr, buf, sz);
}

__attribute__((unused))
static uint64_t call_phystokv(uint64_t addr) {
    if (real_phystokv) return real_phystokv(addr);
    return phystokv(addr);
}

// ====== 文件日志系统 ======
// 将日志写入 Documents/debug.log，崩溃后可在 Files.app 中查看
static FILE *g_logFile = NULL;

static void log_to_file(const char *tag, const char *fmt, ...) {
    // 打开日志文件（仅首次）
    if (!g_logFile) {
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        if (paths.count > 0) {
            NSString *logPath = [paths[0] stringByAppendingPathComponent:@"debug.log"];
            // 追加模式：每次启动新开一段
            g_logFile = fopen([logPath UTF8String], "a");
            if (g_logFile) {
                fprintf(g_logFile, "\n=== App Launch ===\n");
                fflush(g_logFile);
            }
        }
    }

    va_list args;
    va_start(args, fmt);

    // 写入 stderr (可被 idevicesyslog 捕获)
    fprintf(stderr, "[%s] ", tag);
    vfprintf(stderr, fmt, args);
    fprintf(stderr, "\n");

    // 写入文件 (崩溃后可在 Files.app 查看)
    if (g_logFile) {
        time_t now = time(NULL);
        struct tm *tm_info = localtime(&now);
        char time_buf[16];
        strftime(time_buf, sizeof(time_buf), "%H:%M:%S", tm_info);
        fprintf(g_logFile, "%s [%s] ", time_buf, tag);
        va_list args2;
        va_copy(args2, args);
        vfprintf(g_logFile, fmt, args2);
        va_end(args2);
        fprintf(g_logFile, "\n");
        fflush(g_logFile);
    }

    va_end(args);
}

// ====== 崩溃信号处理器 ======
// 捕获 SIGSEGV/SIGABRT/SIGBUS 等致命信号，写入日志文件

static void crash_signal_handler(int sig) {
    const char *name = "UNKNOWN";
    switch (sig) {
        case SIGSEGV: name = "SIGSEGV"; break;
        case SIGABRT: name = "SIGABRT"; break;
        case SIGBUS:  name = "SIGBUS";  break;
        case SIGILL:  name = "SIGILL";  break;
        case SIGTRAP: name = "SIGTRAP"; break;
        case SIGFPE:  name = "SIGFPE";  break;
    }

    // 写入 stderr 和文件
    fprintf(stderr, "\n!!! CRASH: signal %d (%s) !!!\n", sig, name);
    if (g_logFile) {
        fprintf(g_logFile, "\n!!! CRASH: signal %d (%s) !!!\n", sig, name);
        fflush(g_logFile);
    }

    // 获取调用栈
    void *callstack[128];
    int frames = backtrace(callstack, 128);
    if (g_logFile) {
        backtrace_symbols_fd(callstack, frames, fileno(g_logFile));
        fflush(g_logFile);
        fclose(g_logFile);
        g_logFile = NULL;
    }

    // 恢复默认处理器并重新触发
    signal(sig, SIG_DFL);
    raise(sig);
}

static void install_crash_handlers(void) {
    signal(SIGSEGV, crash_signal_handler);
    signal(SIGABRT, crash_signal_handler);
    signal(SIGBUS,  crash_signal_handler);
    signal(SIGILL,  crash_signal_handler);
    signal(SIGTRAP, crash_signal_handler);
    signal(SIGFPE,  crash_signal_handler);
}

// 安全日志宏
#define SAFE_LOG(fmt, ...) log_to_file("Stocks", fmt, ##__VA_ARGS__)

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) LoginViewController *loginVC;
@property (nonatomic, strong) AppViewController *appVC;
@property (nonatomic) int environmentType; // 0=普通, 1=TrollStore, 2=越狱
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {

    // 最先安装崩溃处理器
    install_crash_handlers();

    // 解析 dylib 真实函数 (必须在 jb_init 之前)
    resolve_dylib_functions();

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

    // ===== 步骤3: 越狱原语初始化 (优先用 dylib 版本) =====
    int jbResult = call_jb_init();
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
        [weakSelf startCheatDirectly];
    };

    self.window.rootViewController = self.loginVC;
    [self.window makeKeyAndVisible];

    return YES;
}

// 自动启动三角洲行动游戏 (通过 LSApplicationWorkspace 私有 API)
- (BOOL)launchDeltaForceGame {
    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    if (!workspaceClass) {
        SAFE_LOG("LSApplicationWorkspace 不可用");
        return NO;
    }

    id workspace = [workspaceClass performSelector:@selector(defaultWorkspace)];
    if (!workspace) {
        SAFE_LOG("无法获取 defaultWorkspace");
        return NO;
    }

    SEL openSel = NSSelectorFromString(@"openApplicationWithBundleID:");
    typedef BOOL (*OpenAppFunc)(id, SEL, NSString*);
    OpenAppFunc openApp = (OpenAppFunc)objc_msgSend;

    // 尝试已知的三角洲行动 Bundle ID
    NSArray *knownBIDs = @[
        @"com.tencent.tmgp.dfm",
        @"com.tencent.tmgp.deltaforce",
        @"com.tencent.deltaforce",
        @"com.proximabeta.deltaforce",
        @"com.garena.game.dfm",
    ];

    for (NSString *bid in knownBIDs) {
        @try {
            if (openApp(workspace, openSel, bid)) {
                SAFE_LOG("游戏启动成功: %s", [bid UTF8String]);
                return YES;
            }
        } @catch (NSException *e) {
            SAFE_LOG("启动 %s 失败: %s", [bid UTF8String], [[e description] UTF8String]);
        }
    }

    // 遍历所有已安装 App 查找三角洲行动
    NSArray *allApps = [workspace performSelector:@selector(allApplications)];
    for (id app in allApps) {
        @try {
            NSString *bundleID = [app performSelector:@selector(bundleIdentifier)];
            NSString *appName = [app performSelector:@selector(localizedName)];
            if (!bundleID) continue;

            BOOL isDelta = [bundleID containsString:@"dfm"]
                        || [bundleID containsString:@"deltaforce"]
                        || [bundleID containsString:@"DeltaForce"];

            if (!isDelta && appName) {
                isDelta = [appName containsString:@"Delta"]
                       || [appName containsString:@"三角洲"];
            }

            if (isDelta) {
                if (openApp(workspace, openSel, bundleID)) {
                    SAFE_LOG("游戏启动成功: %s (%s)", [appName UTF8String], [bundleID UTF8String]);
                    return YES;
                }
            }
        } @catch (NSException *e) {}
    }

    SAFE_LOG("未找到三角洲行动游戏，请手动打开");
    return NO;
}

// 授权成功后直接启动悬浮窗 + 自动打开游戏 + 注入
- (void)startCheatDirectly {
    SAFE_LOG("授权成功，正在启动辅助...");

    // 获取 scene
    id scene = self.window.windowScene;
    if (!scene) {
        scene = [UIApplication sharedApplication].connectedScenes.anyObject;
    }

    // 创建悬浮窗
    HUDController *hud = [HUDController shared];
    @try {
        [hud createWindowsOnScene:scene];
        SAFE_LOG("HUD windows created OK");
    } @catch (NSException *e) {
        SAFE_LOG("HUD create failed: %s", [[e description] UTF8String]);
    }

    if (hud.windowsCreated) {
        [hud show];
        SAFE_LOG("HUD overlay started");
    }

    // 后台: 先启动游戏, 再注入
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        // 步骤1: 自动打开三角洲行动 (主线程执行, 同步等待)
        dispatch_sync(dispatch_get_main_queue(), ^{
            [self launchDeltaForceGame];
        });
        // 给游戏一点启动时间
        sleep(2);

        // 步骤2: 注入游戏（带重试）
        int result = hooks_attach_to_game();
        if (result == 0) {
            SAFE_LOG("游戏注入成功，正在扫描偏移...");
            hooks_scan_offsets();
        } else {
            SAFE_LOG("等待游戏启动中（错误码=%d）...", result);
            for (int i = 0; i < 30; i++) {
                sleep(2);
                // 前几次没找到就再尝试启动
                if (i == 3 || i == 8 || i == 15) {
                    dispatch_sync(dispatch_get_main_queue(), ^{
                        [self launchDeltaForceGame];
                    });
                }
                result = hooks_attach_to_game();
                if (result == 0) {
                    SAFE_LOG("游戏注入成功！");
                    hooks_scan_offsets();
                    break;
                }
                if (i % 5 == 4) {
                    SAFE_LOG("仍在等待游戏... (%d/30)", i + 1);
                }
            }
        }
    });

    // 状态提示
    dispatch_async(dispatch_get_main_queue(), ^{
        UILabel *hint = [[UILabel alloc] init];
        hint.text = @"辅助已启动\n正在自动打开游戏...";
        hint.numberOfLines = 2;
        hint.textAlignment = NSTextAlignmentCenter;
        hint.font = [UIFont systemFontOfSize:14];
        hint.textColor = [UIColor colorWithRed:0.376 green:0.647 blue:0.980 alpha:1.0];
        hint.frame = CGRectMake(0, 0, 250, 50);
        hint.center = self.loginVC.view.center;
        [self.loginVC.view addSubview:hint];
    });
}

@end

// 入口 (兼容 TrollStore 和 Xcode 编译)
int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil,
               NSStringFromClass([AppDelegate class]));
    }
}
