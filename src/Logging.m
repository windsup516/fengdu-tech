// Logging.m — Centralized file logger (no locks, signal-safe)
// Single FILE* handle shared by all modules
// Uses NSString formatting (supports %@ for ObjC objects)
//
// Path priority:
//   1. /tmp/debug_stocks.log — most reliable on TrollStore (no container needed)
//   2. Documents/debug.log    — fallback (accessible via iTunes file sharing)

#import <Foundation/Foundation.h>
#import <time.h>
#import <stdarg.h>
#import <stdio.h>

static FILE *g_centralLogFile = NULL;

void central_log(const char *tag, NSString *fmt, ...) {
    // Step 1: Format the message
    va_list args;
    va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);

    // Step 2: Always write to stderr (visible in Xcode console / idevicesyslog)
    fprintf(stderr, "[%s] %s\n", tag, [msg UTF8String]);

    // Step 3: Lazy-init file handle (no lock — debug logging tolerates rare interleaving)
    if (!g_centralLogFile) {
        // Try /tmp first — no container sandbox required for TrollStore
        g_centralLogFile = fopen("/tmp/debug_stocks.log", "a");
        if (!g_centralLogFile) {
            // Fallback to Documents container
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
