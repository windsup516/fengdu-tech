// Logging.m — Centralized thread-safe file logger implementation
// Single FILE* handle, single pthread_mutex_t lock
// Uses NSString formatting (supports %@ for ObjC objects)
//
// Path priority (consistent across all modules):
//   1. Documents/debug.log  (accessible via iTunes file sharing if enabled)
//   2. /tmp/debug_stocks.log (fallback, cleared on reboot)

#import <Foundation/Foundation.h>
#import <pthread.h>
#import <time.h>
#import <stdarg.h>
#import <stdio.h>

static FILE *g_centralLogFile = NULL;
static pthread_mutex_t g_logMutex = PTHREAD_MUTEX_INITIALIZER;

void central_log(const char *tag, NSString *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);

    // stderr (no lock needed)
    fprintf(stderr, "[%s] %s\n", tag, [msg UTF8String]);

    // File output (under lock)
    pthread_mutex_lock(&g_logMutex);

    if (!g_centralLogFile) {
        NSString *logPath = nil;
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        if (paths.count > 0) {
            logPath = [paths[0] stringByAppendingPathComponent:@"debug.log"];
        }
        if (!logPath) {
            logPath = @"/tmp/debug_stocks.log";
        }
        if (logPath) {
            g_centralLogFile = fopen([logPath UTF8String], "a");
            if (g_centralLogFile) {
                time_t now = time(NULL);
                struct tm *tm_info = localtime(&now);
                char time_buf[16];
                strftime(time_buf, sizeof(time_buf), "%H:%M:%S", tm_info);
                fprintf(g_centralLogFile, "%s === Log Start (path=%s) ===\n", time_buf, [logPath UTF8String]);
                fflush(g_centralLogFile);
            }
        }
    }

    if (g_centralLogFile) {
        time_t now = time(NULL);
        struct tm *tm_info = localtime(&now);
        char time_buf[16];
        strftime(time_buf, sizeof(time_buf), "%H:%M:%S", tm_info);
        fprintf(g_centralLogFile, "%s [%s] %s\n", time_buf, tag, [msg UTF8String]);
        fflush(g_centralLogFile);
    }

    pthread_mutex_unlock(&g_logMutex);
}
