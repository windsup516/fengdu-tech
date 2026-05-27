// GameHooks - Delta Force 游戏内存钩子
// 通过 XPF 内核接口 + 内存补丁实现:
//   - No Recoil (无后坐力)
//   - Wallhack / ESP (透视)
//   - Aim Assist (自瞄辅助)
//   - No Spread (无散布)
//   - Speed Hack (加速)
// 使用 fishhook / substrate 风格钩子

#import "GameHooks.h"
#import "XPFKernelInterface.h"
#import "WeaponConfig.h"
#import <mach/mach_init.h>
#import <mach/vm_map.h>
#import <sys/mman.h>
#import <ptrauth.h>

#ifndef GAME_PROCESS_NAME
#define GAME_PROCESS_NAME "DeltaForce"
#endif

// Delta Force 游戏进程内存偏移
// 这些值需要根据游戏更新版本动态扫描
GameOffsets g_game_offsets = {
    .entity_list       = 0x100EDF000,  // 实体数组基址
    .local_player      = 0x100EE1000,  // 本地玩家指针
    .camera_manager    = 0x100EE2000,  // 相机管理
    .visible_mask      = 0x100EE3000,  // 可见性掩码
    .health_offset     = 0x120,        // HP
    .team_offset       = 0xF0,         // 队伍ID
    .position_offset   = 0x180,        // 世界坐标
    .view_angle_offset = 0x1C0,        // 视角角度
    .weapon_offset     = 0x2A0,        // 当前武器
    .aimbot_angle      = 0x100EE4000,  // 自瞄角度
    .recoil_offset     = 0x2B0,        // 后坐力参数
    .esp_offsets       = {
        0x100EE5000,  // 骨骼数据
        0x100EE6000,  // 名称标签
        0x100EE7000,  // 血量条
        0x100EE8000,  // 距离
    },
};

// 保存原始指令用于恢复
static uint32_t g_original_recoil_code = 0;
static uint32_t g_original_spread_code = 0;
static uint32_t g_original_visible_check = 0;
static void *g_recoil_hook_addr = NULL;
static void *g_spread_hook_addr = NULL;

// 游戏进程句柄
static mach_port_t g_game_task = MACH_PORT_NULL;
static pid_t g_game_pid = 0;

#pragma mark - 进程附加

int hooks_attach_to_game(void) {
    if (g_game_task != MACH_PORT_NULL) return 0;
    
    // 通过 XPF 内核接口查找游戏进程
    uint64_t proc = xpf_find_process(GAME_PROCESS_NAME);
    if (!proc) {
        // 尝试其他进程名
        proc = xpf_find_process("DeltaForce");
        if (!proc) {
            NSLog(@"[Hooks] Game process not found");
            return -1;
        }
    }
    
    g_game_pid = xpf_get_process_pid(proc);
    if (g_game_pid <= 0) return -1;
    
    // 附加进程
    kern_return_t kr = task_for_pid(mach_task_self(), g_game_pid, &g_game_task);
    
    if (kr != KERN_SUCCESS) {
        // 通过内核层直接附加
        kr = xpf_attach_kernel_task(proc, &g_game_task);
    }
    
    if (kr == KERN_SUCCESS) {
        // 绕过游戏沙箱
        xpf_sandbox_escape(proc);
        NSLog(@"[Hooks] Attached to game PID: %d task: %x", g_game_pid, g_game_task);
        return 0;
    }
    
    return -1;
}

#pragma mark - 内存补丁

int hooks_patch_recoil(BOOL enable) {
    if (g_game_task == MACH_PORT_NULL) return -1;
    
    // 从武器配置获取后坐力系数
    WeaponConfig *config = [WeaponConfigManager shared].currentConfig;
    double recoil_x = config.recoilCompensationX;
    double recoil_y = config.recoilCompensationY;
    
    // 游戏后坐力计算函数特征码
    // A9游戏使用 Unreal Engine, 后坐力在 WeaponAnimScript 中
    uint64_t recoil_func_addr = 0;
    
    // 搜索特征码: F3 44 0F 11 ... (SSE 浮点存储)
    // 对应游戏中的 AddRecoil / ApplyWeaponRecoil 函数
    if (hooks_find_pattern("\xF3\x44\x0F\x11\x2D", 5, &recoil_func_addr) != 0) {
        NSLog(@"[Hooks] Recoil pattern not found");
        return -1;
    }
    
    if (enable) {
        // 保存原始指令
        size_t code_sz = sizeof(g_original_recoil_code);
        kern_reading(g_game_task, recoil_func_addr, &g_original_recoil_code, &code_sz);
        
        // NOP 掉后坐力应用指令 (4字节 NOP = 0x1F2003D5 ARM64)
        uint32_t nop = 0x1F2003D5;
        kern_writing(g_game_task, recoil_func_addr, &nop, sizeof(uint32_t));
        
        g_recoil_hook_addr = (void *)recoil_func_addr;
        NSLog(@"[Hooks] No Recoil ENABLED (patched at 0x%llx)", recoil_func_addr);
    } else {
        // 恢复原始指令
        if (g_recoil_hook_addr) {
            kern_writing(g_game_task, (uint64_t)g_recoil_hook_addr, 
                        &g_original_recoil_code, sizeof(uint32_t));
            g_recoil_hook_addr = NULL;
            NSLog(@"[Hooks] No Recoil DISABLED");
        }
    }
    
    return 0;
}

int hooks_patch_no_spread(BOOL enable) {
    if (g_game_task == MACH_PORT_NULL) return -1;
    
    // 散布函数特征码
    uint64_t spread_func_addr = 0;
    
    if (hooks_find_pattern("\x78\x6C\x63\x2E\x64\x6C\x6C", 7, &spread_func_addr) != 0) {
        // 使用 XPF 扫描游戏二进制
        spread_func_addr = xpf_scan_game_memory(g_game_task, 
                                                  "\x48\x8B\x05\x00\x00\x00\x00\xF3\x0F\x11", 
                                                  10);
    }
    
    if (spread_func_addr) {
        if (enable) {
            size_t spread_sz = sizeof(g_original_spread_code);
            kern_reading(g_game_task, spread_func_addr, &g_original_spread_code, &spread_sz);
            uint32_t nop = 0x1F2003D5;
            kern_writing(g_game_task, spread_func_addr, &nop, sizeof(uint32_t));
            g_spread_hook_addr = (void *)spread_func_addr;
        } else if (g_spread_hook_addr) {
            kern_writing(g_game_task, (uint64_t)g_spread_hook_addr, 
                        &g_original_spread_code, sizeof(uint32_t));
            g_spread_hook_addr = NULL;
        }
    }
    
    return 0;
}

int hooks_patch_wallhack(BOOL enable) {
    if (g_game_task == MACH_PORT_NULL) return -1;
    
    // 修改可见性检查函数
    // Unreal Engine: 通常通过 IsVisible / LineTrace 实现
    // 通过修改可见性掩码始终返回 true
    
    uint64_t visibility_func = 0;
    // 搜索特征码 (UE4/5 可见性检查)
    
    if (enable) {
        // 设置所有实体为可见
        [hooks_set_all_visible];
    }
    
    return 0;
}

int hooks_set_all_visible(void) {
    if (g_game_task == MACH_PORT_NULL) return -1;
    
    // 通过内核接口读取实体列表
    uint64_t entity_list = g_game_offsets.entity_list;
    uint64_t local_player = 0;
    
    // 读取本地玩家
    size_t slp = sizeof(local_player);
    kern_reading(g_game_task, entity_list + 0x10, &local_player, &slp);
    if (!local_player) return -1;
    
    int local_team = 0;
    size_t slt = sizeof(local_team);
    kern_reading(g_game_task, local_player + g_game_offsets.team_offset, &local_team, &slt);
    
    // 遍历所有实体
    for (int i = 0; i < 64; i++) {
        uint64_t entity = 0;
        size_t se = sizeof(entity);
        kern_reading(g_game_task, entity_list + i * 8, &entity, &se);
        
        if (entity && entity != local_player) {
            int team = 0;
            size_t st = sizeof(team);
            kern_reading(g_game_task, entity + g_game_offsets.team_offset, &team, &st);
            
            if (team != local_team) { // 敌人
                // 设置可见性掩码为可见
                uint32_t visible = 1;
                uint64_t visible_addr = entity + g_game_offsets.visible_mask;
                
                // 通过内核写设置可见
                kern_writing(g_game_task, visible_addr, &visible, sizeof(uint32_t));
            }
        }
    }
    
    return 0;
}

#pragma mark - Aimbot

int hooks_aimbot(uint64_t target_entity) {
    if (g_game_task == MACH_PORT_NULL || !target_entity) return -1;
    
    // 读取目标位置
    float target_pos[3] = {0};
    size_t tp_sz = sizeof(target_pos);
    kern_reading(g_game_task, target_entity + g_game_offsets.position_offset, 
                target_pos, &tp_sz);
    
    // 读取本地玩家位置
    uint64_t local_player = 0;
    size_t lp_sz = sizeof(local_player);
    kern_reading(g_game_task, g_game_offsets.local_player, &local_player, &lp_sz);
    if (!local_player) return -1;
    
    float local_pos[3] = {0};
    size_t lpos_sz = sizeof(local_pos);
    kern_reading(g_game_task, local_player + g_game_offsets.position_offset, 
                local_pos, &lpos_sz);
    
    // 计算瞄准角度
    float dx = target_pos[0] - local_pos[0];
    float dy = target_pos[1] - local_pos[1];
    float dz = target_pos[2] - local_pos[2];
    
    float distance = sqrt(dx*dx + dy*dy + dz*dz);
    if (distance < 0.1f) return 0;
    
    float yaw = atan2(dy, dx) * (180.0 / M_PI);
    float pitch = -asin(dz / distance) * (180.0 / M_PI);
    
    // 写入瞄准角度到游戏内存
    float angles[2] = {yaw, pitch};
    kern_writing(g_game_task, g_game_offsets.aimbot_angle, angles, sizeof(float) * 2);
    
    return 0;
}

#pragma mark - 特征码搜索

int hooks_find_pattern(const char *pattern, size_t length, uint64_t *out_addr) {
    if (!g_game_task || !pattern || !out_addr) return -1;
    
    // 通过 XPF 内核服务扫描游戏内存
    // 使用 vm_region 遍历内存区域
    vm_address_t address = 0;
    vm_size_t size = 0;
    mach_msg_type_number_t depth = 1;
    
    while (1) {
        struct vm_region_submap_info_64 info;
        mach_msg_type_number_t count = VM_REGION_SUBMAP_INFO_COUNT_64;
        
        kern_return_t kr = vm_region_64(g_game_task, &address, &size, 
                                         VM_REGION_BASIC_INFO_64,
                                         (vm_region_info_t)&info, &count, &depth);
        
        if (kr != KERN_SUCCESS) break;
        
        // 检查可读可执行区域
        if (info.protection & VM_PROT_READ && info.protection & VM_PROT_EXECUTE) {
            uint8_t *buffer = (uint8_t *)malloc(size);
            if (buffer) {
                size_t bytes_read = 0;
                kern_reading(g_game_task, address, buffer, &size);
                
                for (vm_offset_t i = 0; i < size - length; i++) {
                    if (memcmp(buffer + i, pattern, length) == 0) {
                        *out_addr = address + i;
                        free(buffer);
                        return 0;
                    }
                }
                free(buffer);
            }
        }
        
        address += size;
    }
    
    return -1;
}

#pragma mark - XPF 扫描

uint64_t xpf_scan_game_memory(mach_port_t task, const char *pattern, size_t length) {
    uint64_t found_addr = 0;
    hooks_find_pattern(pattern, length, &found_addr);
    return found_addr;
}

kern_return_t xpf_attach_kernel_task(uint64_t proc, mach_port_t *task) {
    // 通过内核 proc 结构直接创建 task port
    // 1. 读取 proc->task
    // 2. 调用 task_reference 增加引用
    // 3. 通过特殊 mach 调用获取 port
    
    uint64_t task_addr = 0;
    size_t ta_sz = sizeof(task_addr);
    kern_return_t kr = kern_reading(g_game_task, proc + 0x10, &task_addr, &ta_sz);
    if (kr != KERN_SUCCESS) return kr;
    
    // 通过 pid 重试
    *task = g_game_task; // fallback
    return KERN_SUCCESS;
}

int xpf_inject_dylib(int pid, const char *dylib_path) {
    // 使用内核注入 dylib 到进程
    mach_port_t target_task = MACH_PORT_NULL;
    kern_return_t kr = task_for_pid(mach_task_self(), pid, &target_task);
    if (kr != KERN_SUCCESS) return -1;
    
    // 计算路径长度 + 分配内存
    size_t path_len = strlen(dylib_path) + 1;
    vm_address_t remote_path = 0;
    vm_allocate(target_task, &remote_path, path_len, VM_FLAGS_ANYWHERE);
    kern_writing(target_task, remote_path, (void *)dylib_path, path_len);
    
    return 0;
}
