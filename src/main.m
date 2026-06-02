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
#import <sys/sysctl.h>
#import <CommonCrypto/CommonDigest.h>
#import <spawn.h>

// SecTask API — Security.framework 私有头，手动声明
typedef struct __SecTask *SecTaskRef;
extern SecTaskRef SecTaskCreateFromSelf(CFAllocatorRef allocator);
extern CFTypeRef SecTaskCopyValueForEntitlement(SecTaskRef task, CFStringRef entitlement, CFErrorRef *error);
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

// ====== 文件日志系统 (必须在 resolve_dylib_functions 之前) ======
static FILE *g_logFile = NULL;

static void log_to_file(const char *tag, const char *fmt, ...) {
    if (!g_logFile) {
        NSString *logPath = nil;
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        if (paths.count > 0) {
            logPath = [paths[0] stringByAppendingPathComponent:@"debug.log"];
        }
        if (!logPath) {
            logPath = @"/tmp/debug_stocks.log";
        }
        if (logPath) {
            g_logFile = fopen([logPath UTF8String], "a");
            if (g_logFile) {
                fprintf(g_logFile, "\n=== App Launch (path=%s) ===\n", [logPath UTF8String]);
                fflush(g_logFile);
            }
        }
    }

    va_list args;
    va_start(args, fmt);
    fprintf(stderr, "[%s] ", tag);
    vfprintf(stderr, fmt, args);
    fprintf(stderr, "\n");

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

#define SAFE_LOG(fmt, ...) log_to_file("Stocks", fmt, ##__VA_ARGS__)

static void resolve_dylib_functions(void) {
    char exePath[1024];
    uint32_t sz = (uint32_t)sizeof(exePath);
    if (_NSGetExecutablePath(exePath, &sz) != 0) {
        SAFE_LOG("Dylib: _NSGetExecutablePath failed");
        return;
    }

    NSString *exeStr = [NSString stringWithUTF8String:exePath];
    NSString *fwPath = [[[exeStr stringByDeletingLastPathComponent]
                         stringByAppendingPathComponent:@"Frameworks"]
                        stringByAppendingPathComponent:@"libjailbreak.dylib"];

    // 先检查文件是否存在
    BOOL fwExists = [[NSFileManager defaultManager] fileExistsAtPath:fwPath];
    SAFE_LOG("Dylib path: %s (exists=%s)", [fwPath UTF8String], fwExists ? "YES" : "NO");

    if (!fwExists) {
        SAFE_LOG("Dylib FILE NOT FOUND at Frameworks path!");
        return;
    }

    // RTLD_LAZY 真实加载（不用 RTLD_NOLOAD，那个只查已加载的）
    void *jbHandle = dlopen([fwPath UTF8String], RTLD_LAZY);
    if (!jbHandle) {
        // 打完整 dlerror，可能的错误：签名无效、架构不匹配、依赖缺失、LC_RPATH 不对
        const char *err = dlerror();
        SAFE_LOG("Dylib dlopen FAILED (abs path): %s", err ? err : "unknown");

        // Fallback: 尝试 @rpath（如果 dylib 的 install_name 是 @rpath）
        jbHandle = dlopen("@rpath/libjailbreak.dylib", RTLD_LAZY);
        if (!jbHandle) {
            err = dlerror();
            SAFE_LOG("Dylib dlopen FAILED (@rpath): %s", err ? err : "unknown");
            return;
        }
        SAFE_LOG("Dylib loaded via @rpath");
    } else {
        SAFE_LOG("Dylib loaded OK (abs path)");
    }

    real_jb_init = dlsym(jbHandle, "jb_init");
    real_physread64 = dlsym(jbHandle, "physread64");
    real_physwritebuf = dlsym(jbHandle, "physwritebuf");
    real_phystokv = dlsym(jbHandle, "phystokv");
    real_xpf_inject_dylib = dlsym(jbHandle, "xpf_inject_dylib");

    SAFE_LOG("Dylib symbols: jb_init=%p physread64=%p physwritebuf=%p phystokv=%p",
             (void*)real_jb_init, (void*)real_physread64,
             (void*)real_physwritebuf, (void*)real_phystokv);

    void *kcall_ptr = dlsym(jbHandle, "kcall");
    void *kalloc_ptr = dlsym(jbHandle, "kalloc");
    void *exp_kt_ptr = dlsym(jbHandle, "exploit_get_kernel_task");
    SAFE_LOG("Dylib kcall=%p kalloc=%p exploit_get_kernel_task=%p",
             kcall_ptr, kalloc_ptr, exp_kt_ptr);

    if (!real_jb_init) {
        SAFE_LOG("WARNING: jb_init NOT in dylib — WEAK stub used (IOSurface exploit disabled)");
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

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) LoginViewController *loginVC;
@property (nonatomic, strong) AppViewController *appVC;
@property (nonatomic) int environmentType; // 0=普通, 1=TrollStore, 2=越狱
@property (nonatomic) BOOL cheatStarted; // 防止重复启动
@property (nonatomic, strong) NSString *gameBundlePath; // 缓存的游戏包路径
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

// 探查游戏包 — 通过 proc_pidpath 获取游戏可执行文件路径后检查 Frameworks
- (void)inspectGameBundleAtPath:(NSString *)gamePath {
    if (!gamePath) {
        SAFE_LOG("inspectGameBundleAtPath: gamePath is nil");
        return;
    }
    NSFileManager *fm = [NSFileManager defaultManager];

    SAFE_LOG("=== 探查游戏包: %s ===", [gamePath UTF8String]);

    // 列出 .app 根目录
    NSArray *rootFiles = [fm contentsOfDirectoryAtPath:gamePath error:nil];
    for (NSString *f in rootFiles) {
        BOOL isDir = NO;
        NSString *fullPath = [gamePath stringByAppendingPathComponent:f];
        [fm fileExistsAtPath:fullPath isDirectory:&isDir];
        unsigned long long size = [[fm attributesOfItemAtPath:fullPath error:nil] fileSize];
        if (isDir) {
            SAFE_LOG("  [DIR]  %s/", [f UTF8String]);
        } else {
            SAFE_LOG("  [FILE] %s (%llu bytes)", [f UTF8String], size);
        }
    }

    // 列出 Frameworks 目录下的 dylib
    NSString *fwPath = [gamePath stringByAppendingPathComponent:@"Frameworks"];
    if ([fm fileExistsAtPath:fwPath]) {
        NSArray *fwFiles = [fm contentsOfDirectoryAtPath:fwPath error:nil];
        SAFE_LOG("--- Frameworks/ (%lu items) ---", (unsigned long)fwFiles.count);
        for (NSString *f in fwFiles) {
            NSString *fullPath = [fwPath stringByAppendingPathComponent:f];
            unsigned long long size = [[fm attributesOfItemAtPath:fullPath error:nil] fileSize];
            SAFE_LOG("  %s (%llu bytes)", [f UTF8String], size);
        }
    } else {
        SAFE_LOG("Frameworks/ 目录不存在");
    }

    SAFE_LOG("=== 游戏包探查完成 ===");
}

// 授权成功后直接启动悬浮窗 + 自动打开游戏 + 注入
- (void)startCheatDirectly {
    if (self.cheatStarted) {
        SAFE_LOG("startCheatDirectly: already started, skipping");
        return;
    }
    self.cheatStarted = YES;
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

    // ====== 诊断0: 运行时 binary hash (确认手机上的二进制 == CI artifact) ======
    {
        NSString *exePath = [[NSBundle mainBundle] executablePath];
        NSData *exeData = [NSData dataWithContentsOfFile:exePath];
        if (exeData) {
            unsigned char hash[CC_SHA256_DIGEST_LENGTH];
            CC_SHA256(exeData.bytes, (CC_LONG)exeData.length, hash);
            NSMutableString *hs = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH*2];
            for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [hs appendFormat:@"%02x", hash[i]];
            SAFE_LOG("Binary SHA256: %s", [hs UTF8String]);
            SAFE_LOG("Expected CI:   898d50fcebfaa78cdb95b59aa1aeae5ce1ca7b8f26705a242d29834b51202cef");
            BOOL match = [hs isEqualToString:@"898d50fcebfaa78cdb95b59aa1aeae5ce1ca7b8f26705a242d29834b51202cef"];
            SAFE_LOG("Binary match CI: %s", match ? "YES" : "NO (different binary!)");
        } else {
            SAFE_LOG("Binary SHA256: FAILED to read executable at %s", [exePath UTF8String]);
        }
    }

    // ====== 诊断0b: SecTaskCopyValueForEntitlement (内核是否承认这些权限) ======
    {
        SAFE_LOG("=== SecTask runtime entitlement check ===");
        SecTaskRef task = SecTaskCreateFromSelf(NULL);
        if (!task) {
            SAFE_LOG("SecTaskCreateFromSelf: FAILED");
        } else {
            NSArray *keys = @[
                @"get-task-allow",
                @"task_for_pid-allow",
                @"com.apple.system-task-ports",
                @"com.apple.security.cs.debugger",
                @"com.apple.security.cs.disable-library-validation",
                @"com.apple.private.skip-library-validation",
                @"com.apple.private.security.no-sandbox",
                @"com.apple.private.security.no-container",
                @"platform-application",
            ];
            for (NSString *k in keys) {
                CFTypeRef val = SecTaskCopyValueForEntitlement(task, (__bridge CFStringRef)k, NULL);
                if (val) {
                    if (CFGetTypeID(val) == CFBooleanGetTypeID()) {
                        SAFE_LOG("  %s = %s", [k UTF8String], CFBooleanGetValue(val) ? "TRUE" : "FALSE");
                    } else if (CFGetTypeID(val) == CFStringGetTypeID()) {
                        SAFE_LOG("  %s = '%s'", [k UTF8String], [(__bridge NSString*)val UTF8String]);
                    } else if (CFGetTypeID(val) == CFArrayGetTypeID()) {
                        SAFE_LOG("  %s = <array %ld items>", [k UTF8String], (long)CFArrayGetCount(val));
                    } else {
                        SAFE_LOG("  %s = <type %lu>", [k UTF8String], (unsigned long)CFGetTypeID(val));
                    }
                    CFRelease(val);
                } else {
                    SAFE_LOG("  %s = (nil - NOT GRANTED)", [k UTF8String]);
                }
            }

            // 检查 IOKit user client 是否被授予
            CFTypeRef iokitVal = SecTaskCopyValueForEntitlement(task,
                CFSTR("com.apple.security.exception.iokit-user-client-class"), NULL);
            if (iokitVal) {
                if (CFGetTypeID(iokitVal) == CFArrayGetTypeID()) {
                    NSArray *arr = (__bridge NSArray*)iokitVal;
                    NSMutableString *joined = [NSMutableString string];
                    for (id item in arr) {
                        if ([item isKindOfClass:[NSString class]]) {
                            [joined appendFormat:@"%@, ", item];
                        }
                    }
                    SAFE_LOG("  IOKit-user-client-class = GRANTED [%s]", [joined UTF8String]);
                }
                CFRelease(iokitVal);
            } else {
                SAFE_LOG("  IOKit-user-client-class = (nil - NOT GRANTED by AMFI)");
            }
            CFRelease(task);
        }
        SAFE_LOG("=== SecTask check complete ===");
    }

    // 前台预检: 逐层诊断所有进程枚举 API
    // 依次测试: proc_pidpath / task_for_pid / proc_name / proc_listallpids / proc_listpids
    {
        pid_t myPid = getpid();
        SAFE_LOG("=== Foreground API diagnostic (self PID=%d) ===", myPid);

        // 测试1: proc_pidpath — 能读自身路径吗?
        char pathbuf[PROC_PIDPATHINFO_MAXSIZE] = {0};
        errno = 0;
        int ppRet = proc_pidpath(myPid, pathbuf, sizeof(pathbuf));
        SAFE_LOG("Test1 proc_pidpath(self): ret=%d errno=%d path=%s", ppRet, errno, ppRet > 0 ? pathbuf : "(fail)");

        // 测试2: task_for_pid — 能获取自身 task port 吗?
        mach_port_t selfTask = MACH_PORT_NULL;
        errno = 0;
        kern_return_t tfpRet = task_for_pid(mach_task_self(), myPid, &selfTask);
        SAFE_LOG("Test2 task_for_pid(self): kr=%d errno=%d task=%x", tfpRet, errno, selfTask);
        if (selfTask != MACH_PORT_NULL) {
            mach_port_deallocate(mach_task_self(), selfTask);
        }

        // 测试3: proc_pidpath 对 PID 1 (launchd) — 不同内核路径
        {
            char p1buf[PROC_PIDPATHINFO_MAXSIZE] = {0};
            errno = 0;
            int p1Ret = proc_pidpath(1, p1buf, sizeof(p1buf));
            SAFE_LOG("Test3 proc_pidpath(1): ret=%d errno=%d path=%s", p1Ret, errno, p1Ret > 0 ? p1buf : "(fail)");
        }

        // 测试3b: task_for_pid 测几个系统 PID
        for (int tp = 1; tp <= 5; tp++) {
            mach_port_t t = MACH_PORT_NULL;
            kern_return_t kr = task_for_pid(mach_task_self(), tp, &t);
            if (kr == KERN_SUCCESS) {
                SAFE_LOG("Test3b task_for_pid(%d): SUCCESS task=%x", tp, t);
                mach_port_deallocate(mach_task_self(), t);
            }
        }

        // 测试4: proc_name — 能读自身进程名吗?
        char myName[64] = {0};
        errno = 0;
        proc_name(myPid, myName, sizeof(myName)-1);
        SAFE_LOG("Test4 proc_name(self): name='%s' errno=%d", myName, errno);

        // 测试5: proc_listallpids
        int pidbuf[256];
        errno = 0;
        int testN = proc_listallpids(pidbuf, sizeof(pidbuf));
        SAFE_LOG("Test5 proc_listallpids: ret=%d errno=%d bufsize=%zu", testN, errno, sizeof(pidbuf));
        if (testN > 0) {
            for (int i = 0; i < testN && i < 5; i++) {
                char pn[64] = {0};
                proc_name(pidbuf[i], pn, sizeof(pn)-1);
                SAFE_LOG("  PID[%d]=%d name=%s", i, pidbuf[i], pn);
            }
        }

        // 测试6: proc_listpids(PROC_ALL_PIDS)
        errno = 0;
        int testN2 = proc_listpids(1 /* PROC_ALL_PIDS */, 0, pidbuf, sizeof(pidbuf));
        SAFE_LOG("Test6 proc_listpids: ret=%d errno=%d", testN2, errno);

        // 测试7: sysctl(KERN_PROC_ALL) — 绕过 sandbox 的关键路径
        {
            int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0};
            size_t bufSize = 0;
            errno = 0;
            int sRet = sysctl(mib, 4, NULL, &bufSize, NULL, 0);
            SAFE_LOG("Test7 sysctl(KERN_PROC_ALL) size query: ret=%d errno=%d bufSize=%zu", sRet, errno, bufSize);
            if (sRet == 0 && bufSize > 0) {
                struct kinfo_proc *procs = (struct kinfo_proc *)malloc(bufSize);
                if (procs) {
                    sRet = sysctl(mib, 4, procs, &bufSize, NULL, 0);
                    int count = (int)(bufSize / sizeof(struct kinfo_proc));
                    SAFE_LOG("Test7 sysctl data: ret=%d errno=%d process_count=%d", sRet, errno, count);
                    for (int i = 0; i < count && i < 5; i++) {
                        SAFE_LOG("  [%d] %s", procs[i].kp_proc.p_pid, procs[i].kp_proc.p_comm);
                    }
                    free(procs);
                }
            }
        }

        // 测试8: exploit_get_kernel_task + host_get_special_port
        {
            mach_port_t kt = MACH_PORT_NULL;
            kern_return_t kr = exploit_get_kernel_task(&kt);
            SAFE_LOG("Test8 exploit_get_kernel_task: kr=%d task=%x", kr, kt);
            if (kt != MACH_PORT_NULL) mach_port_deallocate(mach_task_self(), kt);

            kt = MACH_PORT_NULL;
            kr = host_get_special_port(mach_host_self(), 0, 4, &kt);
            SAFE_LOG("Test8 host_get_special_port(HOST_KERNEL_PORT): kr=%d task=%x", kr, kt);
            if (kt != MACH_PORT_NULL) mach_port_deallocate(mach_task_self(), kt);
        }

        // 测试9: 启动 RootHelper 查看其环境中 task_for_pid 是否可用
        {
            SAFE_LOG("Test9 RootHelper spawn test...");
            NSString *rhPath = [[NSBundle mainBundle] pathForResource:@"RootHelper" ofType:nil];
            if (!rhPath) {
                rhPath = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"RootHelper"];
            }
            SAFE_LOG("Test9 RootHelper path: %s exists=%s", [rhPath UTF8String],
                     [[NSFileManager defaultManager] fileExistsAtPath:rhPath] ? "YES" : "NO");
            if ([[NSFileManager defaultManager] fileExistsAtPath:rhPath]) {
                pid_t rhPid = 0;
                const char *rpath = [rhPath UTF8String];
                char *argv[] = { (char *)rpath, NULL };
                posix_spawnattr_t attr;
                posix_spawnattr_init(&attr);
                int ret = posix_spawn(&rhPid, rpath, NULL, &attr, argv, NULL);
                SAFE_LOG("Test9 posix_spawn ret=%d pid=%d", ret, rhPid);
                if (ret == 0 && rhPid > 0) {
                    sleep(3); // 等它跑完
                    NSString *rhLog = [NSString stringWithContentsOfFile:@"/tmp/roothelper.log"
                                                                encoding:NSUTF8StringEncoding error:nil];
                    if (rhLog.length > 0) {
                        for (NSString *line in [rhLog componentsSeparatedByString:@"\n"]) {
                            if (line.length > 0) SAFE_LOG("RootHelper: %s", [line UTF8String]);
                        }
                    } else {
                        SAFE_LOG("Test9 RootHelper log empty/missing");
                    }
                }
                posix_spawnattr_destroy(&attr);
            } else {
                SAFE_LOG("Test9 RootHelper binary NOT FOUND");
            }
        }

        SAFE_LOG("=== Foreground diagnostic complete ===");
    }

    // 后台: 先启动游戏, 再注入
    // 使用 beginBackgroundTask 防止 iOS 挂起扫描线程
    __block UIBackgroundTaskIdentifier bgTask = UIBackgroundTaskInvalid;
    bgTask = [[UIApplication sharedApplication] beginBackgroundTaskWithName:@"GameLauncher" expirationHandler:^{
        SAFE_LOG("后台任务即将超时");
        if (bgTask != UIBackgroundTaskInvalid) {
            [[UIApplication sharedApplication] endBackgroundTask:bgTask];
            bgTask = UIBackgroundTaskInvalid;
        }
    }];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        // 步骤1: 自动打开三角洲行动 (主线程异步, 避免 openApplication 导致死锁)
        dispatch_async(dispatch_get_main_queue(), ^{
            [self launchDeltaForceGame];
        });
        // 给游戏启动时间
        sleep(3);

        // 步骤2: 注入游戏（带重试），每次找到游戏进程后重新注册 SBS
        int result = hooks_attach_to_game();
        if (result == 0) {
            SAFE_LOG("游戏进程已找到，正在扫描偏移...");
            hooks_scan_offsets();

            // 通过 PID 获取游戏路径 (proc_pidpath 不需要特殊权限)
            NSString *gamePath = hooks_get_game_path();
            SAFE_LOG("proc_pidpath 游戏路径: %s", gamePath ? [gamePath UTF8String] : "(nil)");
            [self inspectGameBundleAtPath:gamePath];

            dispatch_async(dispatch_get_main_queue(), ^{
                [[HUDController shared] reRegisterSBSHosting];
            });
        } else {
            SAFE_LOG("等待游戏进程出现...");
            for (int i = 0; i < 30; i++) {
                sleep(2);
                result = hooks_attach_to_game();
                if (result == 0) {
                    SAFE_LOG("游戏进程已找到！");
                    hooks_scan_offsets();

                    // 通过 PID 获取游戏路径
                    NSString *gamePath = hooks_get_game_path();
                    SAFE_LOG("proc_pidpath 游戏路径: %s", gamePath ? [gamePath UTF8String] : "(nil)");
                    [self inspectGameBundleAtPath:gamePath];

                    dispatch_async(dispatch_get_main_queue(), ^{
                        [[HUDController shared] reRegisterSBSHosting];
                    });
                    break;
                }
                if (i % 5 == 4) {
                    SAFE_LOG("仍在等待游戏... (%d/30)", i + 1);
                    // 定期尝试重新注册 SBS
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [[HUDController shared] reRegisterSBSHosting];
                    });
                }
            }
        }

        // 清理后台任务
        if (bgTask != UIBackgroundTaskInvalid) {
            [[UIApplication sharedApplication] endBackgroundTask:bgTask];
            bgTask = UIBackgroundTaskInvalid;
        }
        SAFE_LOG("后台扫描任务结束");
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
