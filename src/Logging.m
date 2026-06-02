// Logging.m — Centralized file logger (no locks, signal-safe)
// Single FILE* handle shared by all modules
// Uses NSString formatting (supports %@ for ObjC objects)
//
// Path priority:
//   1. /var/mobile/Documents/风度_debug.log — Filza-browsable, no Mac needed
//   2. /tmp/debug_stocks.log — fallback
//   3. Documents/debug.log    — last resort (iTunes file sharing)

#import <Foundation/Foundation.h>
#import <time.h>
#import <stdarg.h>
#import <stdio.h>

static FILE *g_centralLogFile = NULL;

static BOOL g_logInitReported = NO;

void central_log(const char *tag, NSString *fmt, ...) {
    // Step 1: Format the message
    va_list args;
    va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);

    // Step 2: Always write to stderr (visible in Xcode console / idevicesyslog)
    fprintf(stderr, "[%s] %s\n", tag, [msg UTF8String]);

    // One-time init report via NSLog (always visible in device console)
    if (!g_logInitReported) {
        g_logInitReported = YES;
        NSLog(@"[Logger] central_log initialized, stderr+file logging active");
    }

    // Step 3: Lazy-init file handle (no lock — debug logging tolerates rare interleaving)
    if (!g_centralLogFile) {
        // Try /var/mobile/Documents first — directly browsable via Filza, no Mac needed
        g_centralLogFile = fopen("/var/mobile/Documents/风度_debug.log", "a");
        if (!g_centralLogFile) {
            // Fallback 1: /tmp — no container sandbox needed
            g_centralLogFile = fopen("/tmp/debug_stocks.log", "a");
        }
        if (!g_centralLogFile) {
            // Fallback 2: App container Documents (iTunes file sharing)
            NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
            if (paths.count > 0) {
                NSString *docLog = [paths[0] stringByAppendingPathComponent:@"debug.log"];
                g_centralLogFile = fopen([docLog UTF8String], "a");
            }
        }
        if (g_centralLogFile) {
            time_t now = time(NULL);
            struct tm *tm_info = localtime(&now);
            char tb[16];
            strftime(tb, sizeof(tb), "%H:%M:%S", tm_info);
            fprintf(g_centralLogFile, "%s === Log Start ===\n", tb);
            fflush(g_centralLogFile);
        }
    }

    // Step 4: Write to file
    if (g_centralLogFile) {
        time_t now = time(NULL);
        struct tm *tm_info = localtime(&now);
        char tb[16];
        strftime(tb, sizeof(tb), "%H:%M:%S", tm_info);
        fprintf(g_centralLogFile, "%s [%s] %s\n", tb, tag, [msg UTF8String]);
        fflush(g_centralLogFile);
    }
}
