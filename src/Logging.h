// Logging.h — Centralized thread-safe file logger
// Single FILE* + pthread_mutex_t, shared by all modules
// Replaces 4 duplicate log functions with interleaving risk
// Uses NSString formatting internally for ObjC %@ compatibility

#ifndef DeltaForce_Logging_h
#define DeltaForce_Logging_h

#ifdef __OBJC__
#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

void central_log(const char *tag, NSString *fmt, ...) NS_FORMAT_FUNCTION(2, 3);

#ifdef __cplusplus
}
#endif

// Per-module convenience macros
#define SAFE_LOG(fmt, ...)    central_log("风度", fmt, ##__VA_ARGS__)
#define HOOKS_LOG(fmt, ...)   central_log("Hooks", fmt, ##__VA_ARGS__)
#define HUD_LOG(fmt, ...)     central_log("HUD", fmt, ##__VA_ARGS__)
#define AC_LOG(fmt, ...)      central_log("AC-Bypass", fmt, ##__VA_ARGS__)

// DEBUG_LOG: 只有在 ENABLE_DEBUG_LOG=1 时才输出 (默认关)
// 用 #if 而非运行时检查, 编译时直接剔除
#if ENABLE_DEBUG_LOG
#define DEBUG_LOG(tag, fmt, ...) central_log(tag, fmt, ##__VA_ARGS__)
#else
#define DEBUG_LOG(tag, fmt, ...) ((void)0)
#endif

#endif // __OBJC__

#endif /* DeltaForce_Logging_h */
