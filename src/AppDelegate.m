// AppDelegate — Stocks app lifecycle (matching Amazon2)
// Implements application:configurationForConnectingSceneSession:options: for Scene-based lifecycle
// BSServiceDomains + FrontBoard system-service keeps Scene alive on background

#import "AppDelegate.h"
#import "LoginViewController.h"
#import "AppViewController.h"
#import "HUDController.h"
#import "GameHooks.h"
#import "XPFKernelInterface.h"
#import "InternalAntiCheat.h"
#import "Logging.h"
#import "NBInstaller.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <spawn.h>
#import <sys/sysctl.h>
#import <mach-o/dyld.h>
#import <signal.h>
#import <execinfo.h>
#import <CommonCrypto/CommonDigest.h>

// SecTask API
typedef struct __SecTask *SecTaskRef;
extern SecTaskRef SecTaskCreateFromSelf(CFAllocatorRef allocator);
extern CFTypeRef SecTaskCopyValueForEntitlement(SecTaskRef task, CFStringRef entitlement, CFErrorRef *error);

// External stubs
extern int jb_init(void);
extern int is_trollstore(void);
extern int is_jailbroken(void);
extern uint64_t physread64(uint64_t phys_addr);
extern int physwritebuf(uint64_t phys_addr, void *buffer, size_t size);
extern uint64_t phystokv(uint64_t phys_addr);

// Dylib function pointers
static int (*real_jb_init)(void) = NULL;
static uint64_t (*real_physread64)(uint64_t) = NULL;
static int (*real_physwritebuf)(uint64_t, void*, size_t) = NULL;
static uint64_t (*real_phystokv)(uint64_t) = NULL;
static int (*real_xpf_inject_dylib)(int, const char*) = NULL;

static void resolve_dylib_functions(void) {
    char exePath[1024];
    uint32_t sz = (uint32_t)sizeof(exePath);
    if (_NSGetExecutablePath(exePath, &sz) != 0) {
        SAFE_LOG(@"Dylib: _NSGetExecutablePath failed");
        return;
    }

    NSString *exeStr = [NSString stringWithUTF8String:exePath];
    NSString *fwPath = [[[exeStr stringByDeletingLastPathComponent]
                         stringByAppendingPathComponent:@"Frameworks"]
                        stringByAppendingPathComponent:@"libjailbreak.dylib"];

    BOOL fwExists = [[NSFileManager defaultManager] fileExistsAtPath:fwPath];
    SAFE_LOG(@"Dylib path: %s (exists=%s)", [fwPath UTF8String], fwExists ? "YES" : "NO");
    if (!fwExists) return;

    void *jbHandle = dlopen([fwPath UTF8String], RTLD_LAZY);
    if (!jbHandle) {
        const char *err = dlerror();
        SAFE_LOG(@"Dylib dlopen FAILED: %s", err ? err : "unknown");
        jbHandle = dlopen("@rpath/libjailbreak.dylib", RTLD_LAZY);
        if (!jbHandle) {
            err = dlerror();
            SAFE_LOG(@"Dylib dlopen FAILED (@rpath): %s", err ? err : "unknown");
            return;
        }
    }

    real_jb_init = dlsym(jbHandle, "jb_init");
    real_physread64 = dlsym(jbHandle, "physread64");
    real_physwritebuf = dlsym(jbHandle, "physwritebuf");
    real_phystokv = dlsym(jbHandle, "phystokv");
    real_xpf_inject_dylib = dlsym(jbHandle, "xpf_inject_dylib");

    void *kcall_ptr = dlsym(jbHandle, "kcall");
    void *kalloc_ptr = dlsym(jbHandle, "kalloc");

    dylib_kern_reading = dlsym(jbHandle, "kern_reading");
    dylib_kern_writing = dlsym(jbHandle, "kern_writing");
    dylib_kcall = kcall_ptr;
    dylib_kalloc = kalloc_ptr;
    dylib_physread64 = real_physread64;
    dylib_physwritebuf = real_physwritebuf;

    SAFE_LOG(@"Dylib globals: kern_reading=%p kcall=%p physread64=%p",
             dylib_kern_reading, dylib_kcall, dylib_physread64);
}

static int call_jb_init(void) {
    if (real_jb_init) return real_jb_init();
    return jb_init();
}

// Crash handler
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
    fprintf(stderr, "\n!!! CRASH: signal %d (%s) !!!\n", sig, name);
    SAFE_LOG(@"!!! CRASH: signal %d (%s) !!!", sig, name);

    void *callstack[128];
    int frames = backtrace(callstack, 128);
    backtrace_symbols_fd(callstack, frames, 2);
    SAFE_LOG(@"Callstack: %d frames", frames);

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

// Forward declaration (SceneDelegate.m, no header)
@interface SceneDelegate : UIResponder <UIWindowSceneDelegate>
@end

@implementation AppDelegate

// === Amazon2: application:didFinishLaunchingWithOptions: ===
// Minimal — just return YES. Window creation is handled by SceneDelegate.
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    install_crash_handlers();
    resolve_dylib_functions();

    SAFE_LOG(@"=== DeltaForce_TrollKit Starting (Scene-based) ===");

    self.environmentType = 0;
    if (is_jailbroken()) {
        self.environmentType = 2;
        SAFE_LOG(@"Environment: JAILBROKEN");
    } else if (is_trollstore()) {
        self.environmentType = 1;
        SAFE_LOG(@"Environment: TrollStore");
    } else {
        SAFE_LOG(@"Environment: Normal");
    }

    int xpfResult = xpf_initialize_kernel();
    if (xpfResult != 0) {
        SAFE_LOG(@"XPF kernel init: FAILED (expected on TrollStore)");
    } else {
        SAFE_LOG(@"XPF kernel init: OK");
    }

    int jbResult = call_jb_init();
    if (jbResult != 0) {
        SAFE_LOG(@"jb_init: FAILED (continuing with userspace only)");
    }

    int acResult = ac_bypass_init();
    if (acResult != 0) {
        SAFE_LOG(@"Anti-cheat bypass: incomplete");
    } else {
        SAFE_LOG(@"Anti-cheat bypass: OK");
    }

    return YES;
}

// === Amazon2 CRITICAL: application:configurationForConnectingSceneSession:options: ===
// Returns UISceneConfiguration so iOS knows to use Scene-based lifecycle.
// Without this, BSServiceDomains / UIApplicationSceneManifest won't properly activate.
- (UISceneConfiguration *)application:(UIApplication *)application
        configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession
        options:(UISceneConnectionOptions *)options {
    NSString *role = connectingSceneSession.role;
    UISceneConfiguration *config = [[UISceneConfiguration alloc]
        initWithName:@"Default Configuration" sessionRole:role];
    config.delegateClass = [SceneDelegate class];
    SAFE_LOG(@"Scene configuration: role=%s delegate=%@",
             [role UTF8String], NSStringFromClass(config.delegateClass));
    return config;
}

// === Game Launch (matches Amazon2 LSApplicationWorkspace) ===
- (BOOL)launchDeltaForceGame {
    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    if (!workspaceClass) return NO;

    id workspace = [workspaceClass performSelector:@selector(defaultWorkspace)];
    if (!workspace) return NO;

    SEL openSel = NSSelectorFromString(@"openApplicationWithBundleID:");
    typedef BOOL (*OpenAppFunc)(id, SEL, NSString*);
    OpenAppFunc openApp = (OpenAppFunc)objc_msgSend;

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
                SAFE_LOG(@"Game launched: %s", [bid UTF8String]);
                return YES;
            }
        } @catch (NSException *e) {}
    }

    // Fallback: scan all apps
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
            if (isDelta && openApp(workspace, openSel, bundleID)) {
                SAFE_LOG(@"Game launched via scan: %s", [bundleID UTF8String]);
                return YES;
            }
        } @catch (NSException *e) {}
    }

    SAFE_LOG(@"Game not found");
    return NO;
}

- (void)inspectGameBundleAtPath:(NSString *)gamePath {
    if (!gamePath) return;
    NSFileManager *fm = [NSFileManager defaultManager];

    SAFE_LOG(@"=== Game bundle: %s ===", [gamePath UTF8String]);
    NSArray *rootFiles = [fm contentsOfDirectoryAtPath:gamePath error:nil];
    for (NSString *f in rootFiles) {
        BOOL isDir = NO;
        NSString *fullPath = [gamePath stringByAppendingPathComponent:f];
        [fm fileExistsAtPath:fullPath isDirectory:&isDir];
        unsigned long long size = [[fm attributesOfItemAtPath:fullPath error:nil] fileSize];
        SAFE_LOG(@"  %s%s (%llu bytes)", isDir ? "[DIR] " : "[FILE]", [f UTF8String], size);
    }
}

// === Authorization success → show HUD + launch game ===
- (void)startCheatDirectly {
    if (self.cheatStarted) {
        SAFE_LOG(@"startCheatDirectly: already started");
        return;
    }
    self.cheatStarted = YES;
    SAFE_LOG(@"Authorization OK, starting cheat...");

    // Get scene from SceneDelegate's window
    id scene = self.window.windowScene;
    if (!scene) {
        for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
            if ([s isKindOfClass:[UIWindowScene class]]) {
                scene = (UIWindowScene *)s;
                break;
            }
        }
    }
    SAFE_LOG(@"createWindowsOnScene: scene=%@", scene);

    HUDController *hud = [HUDController shared];
    @try {
        [hud createWindowsOnScene:scene];
        SAFE_LOG(@"HUD windows created OK");
    } @catch (NSException *e) {
        SAFE_LOG(@"HUD create failed: %s", [[e description] UTF8String]);
    }

    if (hud.windowsCreated) {
        [hud show];
        SAFE_LOG(@"HUD overlay started");
    }

    // Verify binary identity
    {
        NSString *exePath = [[NSBundle mainBundle] executablePath];
        NSData *exeData = [NSData dataWithContentsOfFile:exePath];
        if (exeData) {
            unsigned char hash[CC_SHA256_DIGEST_LENGTH];
            CC_SHA256(exeData.bytes, (CC_LONG)exeData.length, hash);
            NSMutableString *hs = [NSMutableString string];
            for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [hs appendFormat:@"%02x", hash[i]];
            SAFE_LOG(@"Binary SHA256: %s", [hs UTF8String]);
        }
    }

    // Launch game + inject in background
    __block UIBackgroundTaskIdentifier bgTask = UIBackgroundTaskInvalid;
    bgTask = [[UIApplication sharedApplication] beginBackgroundTaskWithName:@"GameLauncher" expirationHandler:^{
        if (bgTask != UIBackgroundTaskInvalid) {
            [[UIApplication sharedApplication] endBackgroundTask:bgTask];
            bgTask = UIBackgroundTaskInvalid;
        }
    }];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        // nb方案: 先替换游戏 framework，再启动游戏
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *gamePath = [[NBInstaller shared] autoInstall];
            SAFE_LOG(@"NB: Auto-install result: gamePath=%s", gamePath ? [gamePath UTF8String] : "FAILED");
            [self launchDeltaForceGame];
        });
        sleep(3);

        // Retry loop: find game + inject dylib + register SBS
        int result = hooks_attach_to_game();
        if (result == 0) {
            hooks_inject_overlay_dylib();  // Inject FIRST — scan may crash/hang
            hooks_scan_offsets();
            NSString *gamePath = hooks_get_game_path();
            [self inspectGameBundleAtPath:gamePath];
            dispatch_async(dispatch_get_main_queue(), ^{
                [[HUDController shared] reRegisterSBSHosting];
            });
        } else {
            for (int i = 0; i < 30; i++) {
                sleep(2);
                result = hooks_attach_to_game();
                if (result == 0) {
                    hooks_inject_overlay_dylib();  // Inject FIRST — scan may crash/hang
                    hooks_scan_offsets();
                    NSString *gamePath = hooks_get_game_path();
                    [self inspectGameBundleAtPath:gamePath];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [[HUDController shared] reRegisterSBSHosting];
                    });
                    break;
                }
                if (i % 5 == 4) {
                    SAFE_LOG(@"Still waiting for game... (%d/30)", i + 1);
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [[HUDController shared] reRegisterSBSHosting];
                    });
                }
            }
        }

        if (bgTask != UIBackgroundTaskInvalid) {
            [[UIApplication sharedApplication] endBackgroundTask:bgTask];
            bgTask = UIBackgroundTaskInvalid;
        }
        SAFE_LOG(@"Background scan complete");
    });
}

@end
