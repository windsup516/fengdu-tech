#ifndef INTERNAL_ANTI_CHEAT_H
#define INTERNAL_ANTI_CHEAT_H

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

// 主初始化 — 在 App 启动时调用
int ac_bypass_init(void);

// 查询录制/直播状态
BOOL ac_is_streaming_mode(void);

// 运行时检测
BOOL ac_is_detecting_debugger(void);
int ac_check_for_scan(void);

#ifdef __cplusplus
}
#endif

#endif
