// DFTest — minimal dylib to verify Mach VM injection works
// No ImGui, no Metal, no UIWindow. Just logging.
// If this works, the injection mechanism is correct and the problem is in the overlay setup.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// Log to the game's sandboxed /tmp/ AND NSLog (visible in device console)
static void test_log(const char *fmt, ...) {
    // NSLog
    va_list args;
    va_start(args, fmt);
    NSString *nsMsg = [[NSString alloc] initWithFormat:[NSString stringWithUTF8String:fmt] arguments:args];
    va_end(args);
    NSLog(@"[DFTest] %@", nsMsg);

    // File log
    FILE *f = fopen("/tmp/dftest.log", "a");
    if (f) {
        time_t now = time(NULL);
        struct tm *t = localtime(&now);
        fprintf(f, "%02d:%02d:%02d [DFTest] ", t->tm_hour, t->tm_min, t->tm_sec);
        va_list args2;
        va_start(args2, fmt);
        vfprintf(f, fmt, args2);
        fprintf(f, "\n");
        fflush(f);
        fclose(f);
        va_end(args2);
    }
}

__attribute__((constructor))
static void DFTestInit(void) {
    test_log("=== MINIMAL constructor: PID=%d proc=%s ===", getpid(), getprogname());

    @try {
        // Check if this works on the raw thread (no dispatch to main)
        BOOL isMain = [NSThread isMainThread];
        test_log("isMainThread=%d", isMain);

        // Try NSLog (no file write — just console)
        NSLog(@"[DFTest] CONSTRUCTOR EXECUTED SUCCESSFULLY");

        // Test basic ObjC
        NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier];
        test_log("bundleId=%s", [bundleId UTF8String]);

        // Test file write to game's /tmp/
        FILE *f2 = fopen("/tmp/dftest_constructor.log", "w");
        if (f2) {
            fprintf(f2, "DFTest constructor OK — PID=%d\n", getpid());
            fclose(f2);
            test_log("Constructor file write OK");
        } else {
            test_log("Constructor file write FAILED: %s", strerror(errno));
        }

    } @catch (NSException *e) {
        test_log("CRASH in constructor: %s", [[e description] UTF8String]);
    }
}

__attribute__((destructor))
static void DFTestCleanup(void) {
    test_log("=== dylib destructor ===");
}
