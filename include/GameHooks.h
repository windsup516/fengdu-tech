#ifndef GAME_HOOKS_H
#define GAME_HOOKS_H

#import <Foundation/Foundation.h>
#import <mach/mach.h>
#import "XPFKernelInterface.h"

#ifndef PROC_PIDPATHINFO_MAXSIZE
#define PROC_PIDPATHINFO_MAXSIZE 4096
#endif

#ifdef __cplusplus
extern "C" {
#endif

int proc_pidpath(int pid, void *buffer, uint32_t buffersize);
int proc_listallpids(void *buffer, int buffersize);
int proc_name(int pid, void *buffer, uint32_t buffersize);
int proc_listpids(uint32_t type, uint32_t typeinfo, void *buffer, int buffersize);

// === 骨骼目标索引 (红狼提取: _Bones_Pos 数组) ===
// Delta Force 使用 UE4 骨骼系统, 常用骨骼:
typedef enum {
    BONE_HEAD      = 0,   // 头部 (爆头)
    BONE_NECK      = 1,   // 颈部
    BONE_CHEST     = 2,   // 胸部
    BONE_PELVIS    = 3,   // 骨盆
    BONE_LEFT_SHOULDER = 4,
    BONE_RIGHT_SHOULDER = 5,
    BONE_LEFT_ELBOW    = 6,
    BONE_RIGHT_ELBOW   = 7,
    BONE_LEFT_HAND     = 8,
    BONE_RIGHT_HAND    = 9,
    BONE_LEFT_KNEE     = 10,
    BONE_RIGHT_KNEE    = 11,
    BONE_LEFT_FOOT     = 12,
    BONE_RIGHT_FOOT    = 13,
    BONE_ROOT     = 14,
    BONE_COUNT    = 15,
} BoneTarget;

// === 自瞄配置 ===
typedef struct {
    BOOL enabled;
    BOOL silent_aim;         // 静默自瞄 (服务器端修改, 更隐蔽)
    BOOL visibility_check;   // 可见性检查 (不透墙)
    BOOL ignore_down;        // 忽略倒地敌人
    BOOL ignore_ai;          // 忽略人机 (红狼 _bIsAI)
    BOOL auto_fire;          // 自动开火 (红狼 FireStateToggleKey)
    int  target_bone;        // 优先瞄准骨骼 (默认 BONE_HEAD)
    float fov_radius;        // 自瞄FOV半径 (度, 0=关闭FOV限制)
    float smooth_factor;     // 平滑系数 (0=瞬间锁, 1=max平滑)
    float max_distance;      // 最大自瞄距离 (米, 0=无限制)
    float aim_speed_mult;    // 自瞄速度倍率 (1.0=默认)
} AimbotConfig;

// === ESP 配置 ===
typedef struct {
    BOOL enabled;
    BOOL box_esp;            // 2D方框
    BOOL skeleton_esp;       // 骨骼绘制
    BOOL health_bar;         // 血条
    BOOL distance_esp;       // 距离显示
    BOOL name_esp;           // 名称显示
    BOOL weapon_esp;         // 武器显示
    BOOL line_esp;           // 射线 (底部屏幕线)
    BOOL head_dot;           // 头部瞄准点
    BOOL visible_only;       // 仅显示可见敌人
    BOOL show_ai;            // 显示人机 (红狼: 隐藏人机开关)
    BOOL show_team;          // 显示队友
    float max_distance;      // 最大ESP距离 (米, 0=无限制)
    // 颜色配置 (RGBA)
    float enemy_box_color[4];     // 敌人方框颜色
    float enemy_visible_color[4]; // 可见敌人颜色
    float team_box_color[4];      // 队友方框颜色
    float ai_box_color[4];        // 人机方框颜色
} ESPConfig;

// === 反检测配置 (内防, 红狼: AAyantibs) ===
typedef struct {
    BOOL bypass_ptrace;      // 绕过 ptrace 反调试
    BOOL bypass_syscall;     // 绕过 syscall hook
    BOOL bypass_integrity;   // 绕过完整性检查
    BOOL hide_overlay;       // 隐藏覆盖层 (直播模式/录屏隐藏)
    BOOL disable_crash_report; // 禁用崩溃上报
    BOOL spoof_device;       // 设备指纹伪装
    BOOL encrypted_comms;    // 加密进程间通信
    BOOL disable_telemetry;  // 禁用遥测上报
    BOOL clean_env;          // 清理环境变量/标记
    BOOL bypass_ue4_anticheat; // 绕过 UE4 内建反作弊
} AntiCheatConfig;

// === 全局配置 ===
extern AimbotConfig g_aimbot_config;
extern ESPConfig g_esp_config;
extern AntiCheatConfig g_anticheat_config;

// === 游戏偏移 ===
extern GameOffsets g_game_offsets;

// === 进程附加 ===
int hooks_attach_to_game(void);
int hooks_scan_offsets(void);
uint64_t hooks_get_game_base(void);

// === 自瞄 (增强版) ===
int hooks_aimbot_find_best_target(void);  // FOV+骨骼选择最佳目标
int hooks_aimbot_target_bone(uint64_t target, int bone); // 瞄准特定骨骼
int hooks_aimbot_calc_angle(float *src, float *dst, float *out_angles); // 计算角度
int hooks_aimbot_apply_smooth(float *current, float *target, float smooth); // 平滑
int hooks_aimbot_silent_fire(uint64_t target, int bone); // 静默自瞄开火
int hooks_aimbot(uint64_t target_entity); // 传统接口 (兼容)

// === ESP 渲染 ===
int hooks_esp_get_entity_list(uint64_t *out_list, int *out_count); // 获取实体列表
int hooks_esp_get_bone_position(uint64_t entity, int bone, float *out_pos); // 骨骼世界坐标
int hooks_esp_get_entity_info(uint64_t entity, char *name, int name_len,
                               float *health, float *max_health, int *team,
                               float *pos, float *distance); // 实体信息
int hooks_esp_world_to_screen(float *world, float *screen); // 世界坐标转屏幕
BOOL hooks_esp_is_visible(uint64_t entity); // 可见性检查
int hooks_esp_get_view_matrix(float *out_matrix); // 获取视图矩阵
int hooks_esp_get_screen_size(float *width, float *height); // 获取屏幕尺寸

// === 无后坐力/无散布 (增强版, 红狼: NoRecoilKey) ===
int hooks_patch_recoil(BOOL enable);
int hooks_patch_no_spread(BOOL enable);
int hooks_patch_weapon_recoil(BOOL enable, const char *weapon_name); // 特定武器
int hooks_set_recoil_multiplier(float mult);  // 后坐力倍率 (0=完全无后坐力)
int hooks_set_spread_multiplier(float mult);  // 散布倍率
int hooks_patch_wallhack(BOOL enable);
int hooks_set_all_visible(void);

// === 反检测 (内防) ===
int hooks_bypass_anti_cheat(void);  // 主反检测函数
int hooks_hide_from_recording(void); // 直播模式 (隐藏覆盖层)
int hooks_disable_crash_reports(void); // 禁用崩溃上报
int hooks_clean_environment(void);  // 清理环境
int hooks_bypass_ptrace(void);      // 绕过反调试
int hooks_spoof_process_name(void); // 进程名伪装

// === 特征码扫描 ===
int hooks_find_pattern(const char *pattern, size_t length, uint64_t *out_addr);
uint64_t xpf_scan_game_memory(mach_port_t task, const char *pattern, size_t length);

// === 查询 ===
mach_port_t hooks_get_game_task(void);
pid_t hooks_get_game_pid(void);
BOOL hooks_is_attached(void);
NSString *hooks_get_game_path(void);

#ifdef __cplusplus
}
#endif

#endif
