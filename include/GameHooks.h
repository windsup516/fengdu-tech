#ifndef GAME_HOOKS_H
#define GAME_HOOKS_H

#import <Foundation/Foundation.h>
#import <mach/mach.h>
#import "XPFKernelInterface.h"

// 游戏钩子 API

extern GameOffsets g_game_offsets;

// 进程附加
int hooks_attach_to_game(void);

// 运行时偏移扫描
int hooks_scan_offsets(void);
uint64_t hooks_get_game_base(void);

// 内存补丁
int hooks_patch_recoil(BOOL enable);
int hooks_patch_no_spread(BOOL enable);
int hooks_patch_wallhack(BOOL enable);
int hooks_set_all_visible(void);

// 自瞄
int hooks_aimbot(uint64_t target_entity);

// 特征码扫描
int hooks_find_pattern(const char *pattern, size_t length, uint64_t *out_addr);
uint64_t xpf_scan_game_memory(mach_port_t task, const char *pattern, size_t length);

// 查询
mach_port_t hooks_get_game_task(void);
pid_t hooks_get_game_pid(void);
BOOL hooks_is_attached(void);

#endif
