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
#import "LoginViewController.h"
#import "AppViewController.h"
#import "HUDController.h"
#import "XPFKernelInterface.h"

// 外部函数声明 (来自 ExternalStubs.c)
extern int jb_init(void);
extern int is_trollstore(void);
extern int is_jailbroken(void);
extern uint64_t physread64(uint64_t phys_addr);
extern int physwritebuf(uint64_t phys_addr, void *buffer, size_t size);
extern uint64_t phystokv(uint64_t phys_addr);

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
        vfprintf(g_logFile, args2, fmt);
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

    // ===== 步骤3: 越狱原语初始化 (允许失败) =====
    int jbResult = jb_init();
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
        [weakSelf showMainMenu];
    };

    self.window.rootViewController = self.loginVC;
    [self.window makeKeyAndVisible];

    // ===== 步骤6: 后台初始化 (不阻塞 UI) =====
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        if (weakSelf.environmentType >= 1) {
            // 尝试解析内核符号 (仅在越狱下有效)
            xpf_resolve_all_symbols();
            xpf_setup_kcall_primitive();
            SAFE_LOG("Background init complete (env=%d)", weakSelf.environmentType);
        }
    });

    return YES;
}

- (void)showMainMenu {
    NSLog(@"[Stocks] showMainMenu: START");

    @try {
        self.appVC = [[AppViewController alloc] init];
        NSLog(@"[Stocks] AppViewController alloc OK");
    } @catch (NSException *e) {
        NSLog(@"[Stocks] AppViewController init CRASH: %@", e);
        return;
    }

    // 确保 appVC.view 已被加载
    @try {
        UIView *v = self.appVC.view;
        if (!v) {
            NSLog(@"[Stocks] AppViewController.view is nil!");
            return;
        }
        NSLog(@"[Stocks] AppViewController.view loaded OK");
    } @catch (NSException *e) {
        NSLog(@"[Stocks] AppViewController.view access CRASH: %@", e);
        return;
    }

    // 直接替换 rootViewController，避免复杂的 view 动画
    @try {
        UIView *snapshot = [self.loginVC.view snapshotViewAfterScreenUpdates:NO];
        if (snapshot) {
            [self.appVC.view addSubview:snapshot];
            [UIView animateWithDuration:0.3 animations:^{
                snapshot.alpha = 0.0;
            } completion:^(BOOL finished) {
                [snapshot removeFromSuperview];
            }];
        }
        self.window.rootViewController = self.appVC;
        NSLog(@"[Stocks] showMainMenu: DONE");
    } @catch (NSException *e) {
        NSLog(@"[Stocks] showMainMenu transition CRASH: %@", e);
    }
}

@end

// 入口 (兼容 TrollStore 和 Xcode 编译)
int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil,
               NSStringFromClass([AppDelegate class]));
    }
}
