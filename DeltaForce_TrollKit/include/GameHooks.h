#ifndef GAME_HOOKS_H
#define GAME_HOOKS_H

#import <Foundation/Foundation.h>
#import <mach/mach.h>
#import "XPFKernelInterface.h"

// 游戏钩子 API
extern GameOffsets g_game_offsets;

int hooks_attach_to_game(void);
int hooks_patch_recoil(BOOL enable);
int hooks_patch_no_spread(BOOL enable);
int hooks_patch_wallhack(BOOL enable);
int hooks_set_all_visible(void);
int hooks_aimbot(uint64_t target_entity);
int hooks_find_pattern(const char *pattern, size_t length, uint64_t *out_addr);

// XPF 扩展 (额外, 不在 XPFKernelInterface.h 中)
uint64_t xpf_scan_game_memory(mach_port_t task, const char *pattern, size_t length);

#endif
