#ifndef XPF_KERNEL_INTERFACE_H
#define XPF_KERNEL_INTERFACE_H

#include <stdint.h>
#include <stdbool.h>
#include <mach/mach.h>
#include <CoreFoundation/CoreFoundation.h>

// === XPF 内核接口 ===

// 初始化
int xpf_initialize_kernel(void);
int xpf_resolve_all_symbols(void);
uint64_t xpf_find_symbol(const char *name);
uint64_t xpf_get_symbol(const char *name);

// kcall 原语
kern_return_t xpf_kcall(uint64_t func, uint64_t *args, int arg_count, uint64_t *result);

// 物理内存
uint64_t xpf_phys_to_virt(uint64_t phys_addr);
int xpf_phys_read(uint64_t phys_addr, void *buffer, size_t size);
int xpf_phys_write(uint64_t phys_addr, void *buffer, size_t size);

// 进程操作
uint64_t xpf_find_process(const char *proc_name);
int xpf_get_process_pid(uint64_t proc);
int xpf_sandbox_escape(uint64_t proc);

// PPL bypass (iOS 16+)
int xpf_ppl_bypass_init(void);

// AMFI / 开发者模式
int xpf_bypass_developer_mode(void);
int xpf_disable_amfi(void);

// 底层 kernel read/write (由 exploit 提供)
extern kern_return_t kern_reading(mach_port_t task, uint64_t addr, void *buf, size_t *size);
extern kern_return_t kern_writing(mach_port_t task, uint64_t addr, void *buf, size_t size);
extern uint64_t get_kernel_slide(void);
extern kern_return_t exploit_get_kernel_task(mach_port_t *task);
extern uint64_t get_current_thread_context(void);

// 进程附加到游戏
static inline int xpf_attach_to_game(const char *game_proc_name) {
    uint64_t proc = xpf_find_process(game_proc_name);
    if (!proc) {
        NSLog(@"[XPF] Process %s not found", game_proc_name);
        return -1;
    }
    
    int pid = xpf_get_process_pid(proc);
    if (pid <= 0) return -1;
    
    // 附加到进程进行内存操作
    mach_port_t game_task = MACH_PORT_NULL;
    kern_return_t kr = task_for_pid(mach_task_self(), pid, &game_task);
    
    if (kr != KERN_SUCCESS) {
        // 通过内核接口直接附加
        kr = xpf_attach_kernel_task(proc, &game_task);
    }
    
    if (kr == KERN_SUCCESS) {
        // 绕过沙箱
        xpf_sandbox_escape(proc);
        // 注入作弊 dylib
        xpf_inject_dylib(pid, "/Library/Star/GameHooks.dylib");
        return pid;
    }
    
    return -1;
}

extern kern_return_t xpf_attach_kernel_task(uint64_t proc, mach_port_t *task);
extern int xpf_inject_dylib(int pid, const char *dylib_path);

// === Delta Force 游戏进程特定 ===
// 游戏名: "Star" / "com.tencent.deltaforce" / "DeltaForce"

#define GAME_PROCESS_NAME    "Star"
#define GAME_BUNDLE_ID      "com.tencent.deltaforce"

// 游戏内存偏移 (通过反编译获取)
// 这些偏移需要根据游戏版本更新
typedef struct {
    uint64_t entity_list;       // 实体列表基址
    uint64_t local_player;       // 本地玩家指针
    uint64_t camera_manager;     // 相机管理器
    uint64_t visible_mask;       // 可见性掩码
    uint64_t health_offset;      // 生命值偏移
    uint64_t team_offset;        // 队伍偏移
    uint64_t position_offset;    // 坐标偏移
    uint64_t view_angle_offset;  // 视角偏移
    uint64_t weapon_offset;      // 武器偏移
    uint64_t aimbot_angle;       // 自瞄角度数据
    uint64_t recoil_offset;      // 后坐力偏移
    uint64_t esp_offsets[16];    // ESP 绘制偏移
} GameOffsets;

extern GameOffsets g_game_offsets;

#endif /* XPF_KERNEL_INTERFACE_H */
