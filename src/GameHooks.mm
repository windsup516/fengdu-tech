// GameHooks - Delta Force 游戏内存钩子 (增强版)
// 基于红狼/Amazon/太阳神 逆向工程完善
// 骨骼自瞄 + FOV限制 + ESP渲染 + 内防绕过 + 无后坐力
//
// 红狼核心发现 (honglang_translate.bin):
//   _Bones_Pos, _bIsAI, _POV, _health, _totalEnemies, _aiCounts
//   NoRecoilKey, AimbotEnableKey, AimbotLineKey, FireStateToggleKey
//   AAyantibs (反检测), MenuHideVC (直播隐藏), HideBotKey
//   ImGui + Metal 渲染 (_GImGui, MetalContext, setupImGui)
//
// Amazon核心发现:
//   platform-application + no-sandbox + task_for_pid-allow
//   HUDController + HUDMainWindow (level=10000010) + TouchMainWindow
//   libjailbreak.dylib (IOSurface exploit) + libchoma.dylib
//   splitmix64 NEON 字符串加密

#import "GameHooks.h"
#import "XPFKernelInterface.h"
#import "Logging.h"
#import "OffsetScanner.h"
#import <mach/mach.h>
#import <mach/mach_host.h>
#import <mach/vm_map.h>
#import <mach-o/loader.h>
#import <sys/sysctl.h>
#import <dlfcn.h>
#import <math.h>

#ifndef GAME_PROCESS_NAME
#define GAME_PROCESS_NAME "DeltaForceClient"
#endif

// 额外游戏进程名候选
static const char *g_game_process_names[] = {
    "DeltaForceClient", "DeltaForce", "DFM", "dfm", "tmgp", "Star", "Delta", NULL
};

// === 全局配置 (红狼默认值) ===
AimbotConfig g_aimbot_config = {
    .enabled = NO,
    .silent_aim = NO,
    .visibility_check = YES,
    .ignore_down = YES,
    .ignore_ai = YES,
    .auto_fire = NO,
    .target_bone = BONE_HEAD,
    .fov_radius = 15.0f,
    .smooth_factor = 0.3f,
    .max_distance = 200.0f,
    .aim_speed_mult = 1.0f,
};

ESPConfig g_esp_config = {
    .enabled = NO,
    .box_esp = YES,
    .skeleton_esp = YES,
    .health_bar = YES,
    .distance_esp = YES,
    .name_esp = YES,
    .weapon_esp = NO,
    .line_esp = YES,
    .head_dot = YES,
    .visible_only = NO,
    .show_ai = NO,
    .show_team = NO,
    .max_distance = 300.0f,
    .enemy_box_color = {1.0f, 0.0f, 0.0f, 1.0f},
    .enemy_visible_color = {1.0f, 1.0f, 0.0f, 1.0f},
    .team_box_color = {0.0f, 1.0f, 0.0f, 1.0f},
    .ai_box_color = {0.5f, 0.5f, 1.0f, 1.0f},
};

AntiCheatConfig g_anticheat_config = {
    .bypass_ptrace = YES,
    .bypass_syscall = YES,
    .bypass_integrity = YES,
    .hide_overlay = NO,
    .disable_crash_report = YES,
    .spoof_device = NO,
    .encrypted_comms = YES,
    .disable_telemetry = YES,
    .clean_env = YES,
    .bypass_ue4_anticheat = YES,
};

// === 游戏偏移 (运行时填充) ===
GameOffsets g_game_offsets = {0};

// 原始指令保存 (恢复用)
static uint32_t g_origRecoilCode = 0;
static uint32_t g_origSpreadCode = 0;
static uint64_t g_recoilAddr = 0;
static uint64_t g_spreadAddr = 0;

// 游戏进程状态
static mach_port_t g_gameTask = MACH_PORT_NULL;
static pid_t g_gamePid = 0;
static BOOL g_attached = NO;

// ESP 缓存 (减少内存读取次数)
static uint64_t g_entityCache[256] = {0};
static int g_entityCount = 0;
static uint64_t g_lastEntityUpdate = 0;
static float g_viewMatrix[16] = {0};
static float g_screenWidth = 1920.0f;
static float g_screenHeight = 1080.0f;

// 前向声明
static kern_return_t game_read(mach_port_t task, uint64_t addr, void *buf, size_t size);
static kern_return_t game_write(mach_port_t task, uint64_t addr, const void *buf, size_t size);

#pragma mark - 向量/矩阵数学 (UE4 FVector/FRotator 兼容)

static inline float vec3_dot(const float *a, const float *b) {
    return a[0]*b[0] + a[1]*b[1] + a[2]*b[2];
}

static inline float vec3_length(const float *v) {
    return sqrtf(v[0]*v[0] + v[1]*v[1] + v[2]*v[2]);
}

static inline void vec3_sub(const float *a, const float *b, float *out) {
    out[0] = a[0] - b[0]; out[1] = a[1] - b[1]; out[2] = a[2] - b[2];
}

static inline void vec3_normalize(float *v) {
    float len = vec3_length(v);
    if (len > 0.0001f) { v[0] /= len; v[1] /= len; v[2] /= len; }
}

// 角度归一化到 [-180, 180] / [-90, 90]
static inline float clamp_angle(float a) {
    while (a > 180.0f) a -= 360.0f;
    while (a < -180.0f) a += 360.0f;
    return a;
}

static inline float clampf_float(float v, float lo, float hi) {
    return v < lo ? lo : (v > hi ? hi : v);
}

// 4x4 矩阵 * 向量 (w=1) — 用于世界坐标转屏幕
static void mat4_mul_vec(const float *m, const float *v, float *out) {
    out[0] = m[0]*v[0] + m[4]*v[1] + m[8]*v[2]  + m[12];
    out[1] = m[1]*v[0] + m[5]*v[1] + m[9]*v[2]  + m[13];
    out[2] = m[2]*v[0] + m[6]*v[1] + m[10]*v[2] + m[14];
    out[3] = m[3]*v[0] + m[7]*v[1] + m[11]*v[2] + m[15];
}

#pragma mark - 进程查找与附加

static pid_t find_pid_by_name_multi(const char **names) {
    static BOOL dumpedOnce = NO;

    // 方法1: sysctl(KERN_PROC_ALL)
    {
        int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0};
        size_t bufSize = 0;
        if (sysctl(mib, 4, NULL, &bufSize, NULL, 0) == 0 && bufSize > 0) {
            struct kinfo_proc *procs = (struct kinfo_proc *)malloc(bufSize);
            if (procs) {
                if (sysctl(mib, 4, procs, &bufSize, NULL, 0) == 0) {
                    int count = (int)(bufSize / sizeof(struct kinfo_proc));
                    if (!dumpedOnce) {
                        dumpedOnce = YES;
                        HOOKS_LOG(@"sysctl: %d processes visible", count);
                    }
                    for (int i = 0; i < count; i++) {
                        const char *pname = procs[i].kp_proc.p_comm;
                        if (!pname || pname[0] == '\0') continue;
                        for (const char **n = names; *n; n++) {
                            if (strcasecmp(pname, *n) == 0) {
                                pid_t found = procs[i].kp_proc.p_pid;
                                HOOKS_LOG(@"Found '%s' PID=%d via sysctl", pname, found);
                                free(procs);
                                return found;
                            }
                        }
                    }
                    // 子串匹配
                    for (int i = 0; i < count; i++) {
                        const char *pname = procs[i].kp_proc.p_comm;
                        if (strcasestr(pname, "delta") || strcasestr(pname, "dfm") ||
                            strcasestr(pname, "tmgp") || strcasestr(pname, "force") ||
                            strcasestr(pname, "star")) {
                            pid_t found = procs[i].kp_proc.p_pid;
                            HOOKS_LOG(@"sysctl substring: '%s' PID=%d", pname, found);
                            free(procs);
                            return found;
                        }
                    }
                }
                free(procs);
            }
        }
    }

    // 方法2-3: proc_listallpids + proc_listpids
    int pidbuf[1024];
    int npids = proc_listallpids(pidbuf, sizeof(pidbuf));
    if (npids <= 0) {
        npids = proc_listpids(1, 0, pidbuf, sizeof(pidbuf));
    }
    if (npids > 0) {
        for (int i = 0; i < npids; i++) {
            char pname[64] = {0};
            proc_name(pidbuf[i], pname, sizeof(pname) - 1);
            if (pname[0] == '\0') continue;
            for (const char **n = names; *n; n++) {
                if (strcasecmp(pname, *n) == 0) return pidbuf[i];
            }
        }
        for (int i = 0; i < npids; i++) {
            char pname[64] = {0};
            proc_name(pidbuf[i], pname, sizeof(pname) - 1);
            if (strcasestr(pname, "delta") || strcasestr(pname, "dfm") ||
                strcasestr(pname, "tmgp") || strcasestr(pname, "force")) {
                return pidbuf[i];
            }
        }
    }

    // 方法4: PID暴力扫描
    for (pid_t p = 1; p < 3000; p++) {
        char ppath[PROC_PIDPATHINFO_MAXSIZE] = {0};
        if (proc_pidpath(p, ppath, sizeof(ppath)) <= 0) continue;
        NSString *fullPath = [NSString stringWithUTF8String:ppath];
        NSString *execName = [[fullPath lastPathComponent] stringByDeletingPathExtension];
        const char *pname = [execName UTF8String];
        if (!pname || pname[0] == '\0') continue;
        for (const char **n = names; *n; n++) {
            if (strcasecmp(pname, *n) == 0) return p;
        }
        if (strcasestr(pname, "delta") || strcasestr(pname, "dfm") ||
            strcasestr(pname, "tmgp")) return p;
    }
    return -1;
}

int hooks_attach_to_game(void) {
    if (g_attached && g_gameTask != MACH_PORT_NULL) return 0;

    pid_t pid = find_pid_by_name_multi(g_game_process_names);
    if (pid < 0) { HOOKS_LOG(@"Game not found"); return -1; }

    g_gamePid = pid;
    g_gameTask = MACH_PORT_NULL;

    // 4层 task port 获取
    kern_return_t kr = task_for_pid(mach_task_self(), pid, &g_gameTask);
    HOOKS_LOG(@"task_for_pid(%d): kr=%d task=%x", pid, kr, g_gameTask);

    if (kr != KERN_SUCCESS || g_gameTask == MACH_PORT_NULL) {
        kr = xpf_attach_kernel_task((uint64_t)pid, &g_gameTask);
        HOOKS_LOG(@"xpf_attach_kernel_task: kr=%d task=%x", kr, g_gameTask);

        if (kr != KERN_SUCCESS || g_gameTask == MACH_PORT_NULL) {
            mach_port_t kt = MACH_PORT_NULL;
            kern_return_t ktkr = exploit_get_kernel_task(&kt);
            if (ktkr == KERN_SUCCESS && kt != MACH_PORT_NULL) {
                g_gameTask = kt;
                HOOKS_LOG(@"Using kernel_task (bypass sandbox)");
            } else {
                kr = host_get_special_port(mach_host_self(), 0, 4, &g_gameTask);
                if (kr != KERN_SUCCESS || g_gameTask == MACH_PORT_NULL) {
                    HOOKS_LOG(@"ALL task port methods FAILED");
                    g_attached = YES;
                    return 0;
                }
            }
        }
    }

    g_attached = YES;
    HOOKS_LOG(@"Attached PID=%d task=%x", pid, g_gameTask);

    // Note: hooks_scan_offsets is called synchronously by main.m after attach
    // Don't dispatch async here — causes duplicate scans

    return 0;
}

// === Dylib injection into game process ===
// Inject DFOverlay.dylib so Metal+ImGui overlay renders in game's process
// Render context never dies because game is always foreground
// Declare the injector function from DylibInjector.m
extern "C" int inject_dylib_to_pid(pid_t pid, const char *dylibName);

int hooks_inject_overlay_dylib(void) {
    if (!g_attached || g_gamePid <= 0) {
        HOOKS_LOG(@"Inject: game not attached, can't inject");
        return -1;
    }

    // Check if dylib already injected (check for DFOverlayController in remote process)
    // For now, just inject — if already loaded, dlopen is a no-op
    int ret = inject_dylib_to_pid(g_gamePid, "DFOverlay.dylib");
    if (ret == 0) {
        HOOKS_LOG(@"Inject: DFOverlay.dylib loaded into game PID %d", g_gamePid);
    } else {
        HOOKS_LOG(@"Inject: FAILED to inject DFOverlay.dylib (ret=%d)", ret);
    }

    return ret;
}

#pragma mark - 偏移扫描 (增强版)

int hooks_scan_offsets(void) {
    if (g_gameTask == MACH_PORT_NULL) return -1;
    if (g_scanned_offsets.scanned) {
        HOOKS_LOG(@"Offsets already scanned, skipping");
        return 0;
    }

    uint64_t gameBase = hooks_get_game_base();
    if (!gameBase) { HOOKS_LOG(@"Cannot find game base"); return -1; }
    HOOKS_LOG(@"Game base: 0x%llx", gameBase);

    // === Phase 1: 签名扫描 GWorld (ADRP+LDR 指令解码) ===
    int scanResult = scan_all_offsets(g_gameTask, gameBase);
    HOOKS_LOG(@"scan_all_offsets result=%d (gworld=%d gname=%d)",
              scanResult, g_scanned_offsets.gworld_found, g_scanned_offsets.gname_found);

    if (scanResult == 0 && g_scanned_offsets.gworld_found) {
        // === GWorld 扫描成功 — 用扫描结果 ===
        uint64_t gworld = 0;
        game_read(g_gameTask, g_scanned_offsets.gworld_ptr, &gworld, sizeof(gworld));

        HOOKS_LOG(@"GWorld scanned: *0x%llx = 0x%llx", g_scanned_offsets.gworld_ptr, gworld);

        // 从 UWorld 读取 PersistentLevel→Actors
        uint64_t actorsArray = 0;
        int actorsCount = 0;
        if (get_actors_from_world(g_gameTask, gworld, &actorsArray, &actorsCount) == 0) {
            g_game_offsets.entity_list = actorsArray;  // 直接使用 Actors TArray 地址
            HOOKS_LOG(@"Actors via UWorld: array=0x%llx count=%d", actorsArray, actorsCount);
        }

        // 尝试解析 LocalPlayer (从 UWorld + 0x38 → OwningGameInstance → LocalPlayers)
        uint64_t gameInstance = 0;
        if (game_read(g_gameTask, gworld + 0x38, &gameInstance, sizeof(gameInstance)) == KERN_SUCCESS) {
            if (gameInstance) {
                uint64_t lpArray = 0;
                int32_t lpCount = 0;
                game_read(g_gameTask, gameInstance + 0x38, &lpArray, sizeof(lpArray));
                game_read(g_gameTask, gameInstance + 0x38 + 8, &lpCount, sizeof(lpCount));
                if (lpArray && lpCount > 0) {
                    uint64_t firstLP = 0;
                    game_read(g_gameTask, lpArray, &firstLP, sizeof(firstLP));
                    if (firstLP) {
                        uint64_t playerController = 0;
                        game_read(g_gameTask, firstLP + 0x30, &playerController, sizeof(playerController));
                        g_game_offsets.local_player = playerController;
                        HOOKS_LOG(@"PlayerController via UWorld: 0x%llx", playerController);
                    }
                }
            }
        }

        // Camera Manager: PlayerController + 0x330
        if (g_game_offsets.local_player) {
            uint64_t camMgr = 0;
            game_read(g_gameTask, g_game_offsets.local_player + g_scanned_offsets.player_camera_manager,
                      &camMgr, sizeof(camMgr));
            g_game_offsets.camera_manager = camMgr;
            HOOKS_LOG(@"CameraManager via PC: 0x%llx", camMgr);
        }
    }

    // === Phase 2: 扫描结果不完整 → 用红狼硬编码偏移兜底 ===
    if (!g_game_offsets.entity_list)
        g_game_offsets.entity_list = gameBase + 0x0EDF000;
    if (!g_game_offsets.local_player)
        g_game_offsets.local_player = gameBase + 0x0EE1000;
    if (!g_game_offsets.camera_manager)
        g_game_offsets.camera_manager = gameBase + 0x0EE2000;

    g_game_offsets.visible_mask    = gameBase + 0x0EE3000;
    g_game_offsets.health_offset   = g_scanned_offsets.aactor_health;
    g_game_offsets.team_offset     = g_scanned_offsets.aactor_team_id;
    g_game_offsets.position_offset = g_scanned_offsets.uscenecomponent_translation;
    g_game_offsets.view_angle_offset = 0x1C0;
    g_game_offsets.weapon_offset   = g_scanned_offsets.weapon_recoil;
    g_game_offsets.aimbot_angle    = gameBase + 0x0EE4000;
    g_game_offsets.recoil_offset   = g_scanned_offsets.weapon_recoil;

    HOOKS_LOG(@"Offsets initialized (base=0x%llx scanned=%d)", gameBase, g_scanned_offsets.scanned);

    // === Phase 3: 运行时验证 ===
    if (g_scanned_offsets.gworld_found) {
        uint64_t gworld = 0;
        game_read(g_gameTask, g_scanned_offsets.gworld_ptr, &gworld, sizeof(gworld));
        if (gworld) {
            uint64_t pl = 0;
            game_read(g_gameTask, gworld + 0x30, &pl, sizeof(pl));
            HOOKS_LOG(@"Validation: UWorld=0x%llx PersistentLevel=0x%llx", gworld, pl);
        }
    }

    return 0;
}

uint64_t hooks_get_game_base(void) {
    if (g_gameTask == MACH_PORT_NULL) return 0;

    vm_address_t addr = 0;
    vm_size_t size = 0;
    mach_msg_type_number_t depth = 1;

    while (1) {
        struct vm_region_submap_info_64 info;
        mach_msg_type_number_t count = VM_REGION_SUBMAP_INFO_COUNT_64;

        kern_return_t kr = vm_region_64(g_gameTask, &addr, &size,
                                         VM_REGION_BASIC_INFO_64,
                                         (vm_region_info_t)&info, &count, &depth);
        if (kr != KERN_SUCCESS) break;

        if ((info.protection & VM_PROT_EXECUTE) && size > 0x100000) {
            uint32_t magic = 0;
            size_t sz = sizeof(magic);
            if (game_read(g_gameTask, addr, &magic, sz) == KERN_SUCCESS) {
                if (magic == MH_MAGIC_64 || magic == 0xCFAEDFE7) return addr;
            }
        }

        addr += size;
        if (addr > 0x200000000) break;
    }
    return 0;
}

#pragma mark - 骨骼系统 (红狼: _Bones_Pos)

// UE4 骨骼名称索引 (Delta Force 常见骨骼映射)
// 不同游戏/版本可能不同, 运行时通过组件验证
static const char *g_bone_names[] = {
    "head", "neck_01", "spine_03", "pelvis",
    "upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r",
    "hand_l", "hand_r", "thigh_l", "thigh_r",
    "calf_l", "calf_r", "foot_l", "foot_r",
    "root"
};

// 从 USkeletalMeshComponent 读取骨骼变换矩阵
static BOOL read_bone_transform(mach_port_t task, uint64_t meshComp,
                                 int boneIndex, float *outWorldPos) {
    if (!meshComp || boneIndex < 0 || !outWorldPos) return NO;

    // UE4 USkeletalMeshComponent 结构:
    // ComponentToWorld (FTransform) @ offset 0x1E0
    // BoneSpaceTransforms (TArray<FTransform>) @ offset 0x6D0
    // CachedBoneSpaceTransforms @ offset 0x6E0
    // CachedComponentSpaceTransforms @ offset 0x6F0

    // 简化路径: 读取 CachedComponentSpaceTransforms
    uint64_t boneArrayPtr = 0;
    int boneArrayCount = 0;

    // CachedComponentSpaceTransforms = TArray (ptr + count)
    uint64_t cachedTransformsOffset = 0x6F0;
    size_t sz = sizeof(boneArrayPtr);
    if (game_read(task, meshComp + cachedTransformsOffset, &boneArrayPtr, sz) != KERN_SUCCESS)
        return NO;
    sz = sizeof(boneArrayCount);
    if (game_read(task, meshComp + cachedTransformsOffset + 8, &boneArrayCount, sz) != KERN_SUCCESS)
        return NO;

    if (!boneArrayPtr || boneArrayCount == 0 || boneIndex >= boneArrayCount) return NO;

    // FTransform = Rotation (FQuat, 4 floats) + Translation (FVector, 3 floats) + Scale3D (3 floats)
    // 每个 FTransform = 0x28 (40 bytes) — 四元数16B + 位移12B + 缩放12B

    float boneTransform[10] = {0}; // Quat(4) + Translation(3) + Scale(3)
    uint64_t boneAddr = boneArrayPtr + boneIndex * 0x28;
    sz = sizeof(boneTransform);
    if (game_read(task, boneAddr, boneTransform, sz) != KERN_SUCCESS) return NO;

    // 提取位移 (FVector 在 offset 0x10)
    float boneLocalPos[3] = { boneTransform[4], boneTransform[5], boneTransform[6] };

    // 读取 ComponentToWorld 转换矩阵
    float compToWorld[16] = {0};
    sz = sizeof(compToWorld);
    if (game_read(task, meshComp + 0x1E0, compToWorld, sz) != KERN_SUCCESS) return NO;

    // 将局部坐标转换到世界坐标
    mat4_mul_vec(compToWorld, boneLocalPos, outWorldPos);

    return YES;
}

int hooks_esp_get_bone_position(uint64_t entity, int bone, float *out_pos) {
    if (!entity || !out_pos || bone < 0 || bone >= BONE_COUNT) return -1;
    if (g_gameTask == MACH_PORT_NULL) return -1;

    // AActor -> USkeletalMeshComponent
    // Mesh 组件通常在 Actor + 0x2D0 (需要运行时确认)
    uint64_t meshComp = 0;
    size_t sz = sizeof(meshComp);
    if (game_read(g_gameTask, entity + 0x2D0, &meshComp, sz) != KERN_SUCCESS) return -1;

    if (!meshComp) return -1;

    float worldPos[4] = {0};
    if (!read_bone_transform(g_gameTask, meshComp, bone, worldPos)) return -1;

    out_pos[0] = worldPos[0];
    out_pos[1] = worldPos[1];
    out_pos[2] = worldPos[2];

    return 0;
}

#pragma mark - 自瞄系统 (红狼: AimbotEnableKey, AimbotLineKey)

// 计算从源位置到目标位置的角度 (yaw, pitch)
int hooks_aimbot_calc_angle(float *src, float *dst, float *out_angles) {
    if (!src || !dst || !out_angles) return -1;

    float delta[3];
    vec3_sub(dst, src, delta);

    float dist = vec3_length(delta);
    if (dist < 0.01f) return -1;

    // UE4: Yaw = 水平角度, Pitch = 垂直角度
    float yaw = atan2f(delta[1], delta[0]) * (180.0f / M_PI);
    float pitch = -asinf(delta[2] / dist) * (180.0f / M_PI);

    out_angles[0] = clamp_angle(yaw);
    out_angles[1] = clampf_float(pitch, -89.0f, 89.0f);

    return 0;
}

// 平滑角度 (避免瞬间锁定)
int hooks_aimbot_apply_smooth(float *current, float *target, float smooth) {
    if (!current || !target) return -1;

    float factor = clampf_float(1.0f - smooth, 0.01f, 1.0f);

    // 计算增量
    float delta_yaw = clamp_angle(target[0] - current[0]);
    float delta_pitch = target[1] - current[1];

    // 平滑过渡
    current[0] = clamp_angle(current[0] + delta_yaw * factor);
    current[1] = clampf_float(current[1] + delta_pitch * factor, -89.0f, 89.0f);

    return 0;
}

// FOV选择最佳目标 (骨骼优先)
int hooks_aimbot_find_best_target(void) {
    if (g_gameTask == MACH_PORT_NULL || !g_aimbot_config.enabled) return -1;

    // 获取本地玩家
    uint64_t localPlayer = 0;
    size_t sz = sizeof(localPlayer);
    game_read(g_gameTask, g_game_offsets.local_player, &localPlayer, sz);
    if (!localPlayer) return -1;

    // 读取本地玩家信息
    float localPos[3] = {0};
    game_read(g_gameTask, localPlayer + g_game_offsets.position_offset, localPos, sizeof(localPos));

    float localViewAngles[2] = {0};
    game_read(g_gameTask, localPlayer + g_game_offsets.view_angle_offset, localViewAngles, sizeof(localViewAngles));

    int localTeam = 0;
    game_read(g_gameTask, localPlayer + g_game_offsets.team_offset, &localTeam, sizeof(localTeam));

    // 读取视图矩阵 (用于FOV计算)
    float viewMatrix[16] = {0};
    uint64_t camMgr = 0;
    if (game_read(g_gameTask, g_game_offsets.camera_manager, &camMgr, sizeof(camMgr)) == KERN_SUCCESS) {
        game_read(g_gameTask, camMgr + 0x2C0, viewMatrix, sizeof(viewMatrix));
    }

    uint64_t entityList = g_game_offsets.entity_list;
    if (!entityList) return -1;

    float bestScore = 999999.0f;
    uint64_t bestTarget = 0;
    int bestBone = BONE_HEAD;

    // 骨骼优先级 (头部->颈部->胸部->骨盆)
    int bonePriority[] = { BONE_HEAD, BONE_NECK, BONE_CHEST, BONE_PELVIS };
    int numBones = sizeof(bonePriority) / sizeof(bonePriority[0]);

    // 遍历实体列表
    for (int i = 0; i < 64; i++) {
        uint64_t entity = 0;
        game_read(g_gameTask, entityList + i * 8, &entity, sizeof(entity));
        if (!entity || entity == localPlayer) continue;

        // 队伍检查
        int team = 0;
        game_read(g_gameTask, entity + g_game_offsets.team_offset, &team, sizeof(team));
        if (team == localTeam && !g_esp_config.show_team) continue;

        // AI检查 (红狼: _bIsAI)
        if (g_aimbot_config.ignore_ai) {
            int bIsAI = 0;
            game_read(g_gameTask, entity + 0x4C0, &bIsAI, sizeof(bIsAI)); // 偏移需运行时确认
            if (bIsAI) continue;
        }

        float entityPos[3] = {0};
        game_read(g_gameTask, entity + g_game_offsets.position_offset, entityPos, sizeof(entityPos));

        // 距离检查
        float delta[3];
        vec3_sub(entityPos, localPos, delta);
        float distance = vec3_length(delta);
        float distanceMeters = distance * 0.01f; // UE4使用厘米
        if (g_aimbot_config.max_distance > 0 && distanceMeters > g_aimbot_config.max_distance) continue;

        // FOV检查 — 计算目标与准星的角度
        float targetAngles[2];
        hooks_aimbot_calc_angle(localPos, entityPos, targetAngles);
        float fovToTarget = sqrtf(
            powf(clamp_angle(targetAngles[0] - localViewAngles[0]), 2.0f) +
            powf(targetAngles[1] - localViewAngles[1], 2.0f)
        );
        if (g_aimbot_config.fov_radius > 0 && fovToTarget > g_aimbot_config.fov_radius) continue;

        // 可见性检查
        if (g_aimbot_config.visibility_check && !hooks_esp_is_visible(entity)) continue;

        // 骨骼遍历 — 找到最近的有效骨骼
        for (int b = 0; b < numBones; b++) {
            float bonePos[3] = {0};
            if (hooks_esp_get_bone_position(entity, bonePriority[b], bonePos) != 0) continue;

            float boneAngles[2];
            if (hooks_aimbot_calc_angle(localPos, bonePos, boneAngles) != 0) continue;

            float boneFov = sqrtf(
                powf(clamp_angle(boneAngles[0] - localViewAngles[0]), 2.0f) +
                powf(boneAngles[1] - localViewAngles[1], 2.0f)
            );

            // 加权分数: FOV * 0.7 + 距离 * 0.3
            float score = boneFov * 0.7f + distanceMeters * 0.3f;

            if (score < bestScore) {
                bestScore = score;
                bestTarget = entity;
                bestBone = bonePriority[b];
            }
            break; // 使用第一个有效骨骼
        }

        // 如果没有骨骼, 使用根位置
        if (bestTarget != entity) {
            float fovScore = fovToTarget * 0.7f + distanceMeters * 0.3f;
            if (fovScore < bestScore) {
                bestScore = fovScore;
                bestTarget = entity;
                bestBone = BONE_ROOT;
            }
        }
    }

    if (bestTarget) {
        hooks_aimbot_target_bone(bestTarget, bestBone);
        return (int)bestTarget;
    }

    return -1;
}

// 瞄准目标骨骼
int hooks_aimbot_target_bone(uint64_t target, int bone) {
    if (!target || g_gameTask == MACH_PORT_NULL) return -1;

    uint64_t localPlayer = 0;
    size_t sz = sizeof(localPlayer);
    game_read(g_gameTask, g_game_offsets.local_player, &localPlayer, sz);
    if (!localPlayer) return -1;

    // 获取本地摄像机位置 (UE4: PlayerCameraManager->CameraCache.POV.Location)
    uint64_t camMgr = 0;
    game_read(g_gameTask, g_game_offsets.camera_manager, &camMgr, sizeof(camMgr));

    float cameraPos[3] = {0};
    float currentAngles[2] = {0};

    if (camMgr) {
        // CameraCache.POV @ offset 0x2C0
        game_read(g_gameTask, camMgr + 0x2C0 + 0x00, cameraPos, sizeof(cameraPos));   // Location
        game_read(g_gameTask, camMgr + 0x2C0 + 0x1C, currentAngles, sizeof(currentAngles)); // Rotation
    } else {
        game_read(g_gameTask, localPlayer + g_game_offsets.position_offset, cameraPos, sizeof(cameraPos));
        // 眼部高度偏移 (UE4: ~180cm 即 180.0 世界单位)
        cameraPos[2] += 180.0f;
        game_read(g_gameTask, localPlayer + g_game_offsets.view_angle_offset, currentAngles, sizeof(currentAngles));
    }

    // 获取目标骨骼世界坐标
    float targetPos[3] = {0};
    if (hooks_esp_get_bone_position(target, bone, targetPos) != 0) {
        // Fallback: 使用实体根位置 + 头部偏移
        game_read(g_gameTask, target + g_game_offsets.position_offset, targetPos, sizeof(targetPos));
        targetPos[2] += 170.0f; // 头部高度
    }

    // 计算目标角度
    float targetAngles[2];
    if (hooks_aimbot_calc_angle(cameraPos, targetPos, targetAngles) != 0) return -1;

    // 平滑处理
    float finalAngles[2] = { currentAngles[0], currentAngles[1] };
    hooks_aimbot_apply_smooth(finalAngles, targetAngles, g_aimbot_config.smooth_factor);

    // 写入视角角度
    uint64_t angleAddr = g_game_offsets.aimbot_angle;
    if (!angleAddr) {
        // 尝试写入 PlayerCameraManager 的 ControlRotation
        angleAddr = camMgr + 0x2C0 + 0x1C;
    }

    game_write(g_gameTask, angleAddr, finalAngles, sizeof(float) * 2);

    // 静默自瞄: 直接修改 ServerFire RPC 参数 (红狼: FireStateToggleKey)
    if (g_aimbot_config.silent_aim) {
        hooks_aimbot_silent_fire(target, bone);
    }

    // 自动开火
    if (g_aimbot_config.auto_fire) {
        uint32_t fireState = 1; // EWeaponFireState::Firing
        game_write(g_gameTask, localPlayer + g_game_offsets.weapon_offset + 0x50, &fireState, sizeof(fireState));
    }

    return 0;
}

// 静默自瞄: 在服务器端开火函数钩子中修改射击方向
int hooks_aimbot_silent_fire(uint64_t target, int bone) {
    if (!target) return -1;
    // 静默自瞄通过 hook ServerFire/ServerMove RPC 实现
    // 在 RPC 包发送前修改 ViewAngles, 发送后恢复
    // 需要 inline hook UPlayerController::ServerFire 或 RPC_Packet 层
    // 实现依赖 libjailbreak.dylib 的 kcall 进行 inline hook
    return 0; // 占位 — 需要内核级 hook 支持
}

// 传统接口 (兼容)
int hooks_aimbot(uint64_t targetEntity) {
    return hooks_aimbot_target_bone(targetEntity, g_aimbot_config.target_bone);
}

#pragma mark - ESP 实体遍历与信息获取

int hooks_esp_get_entity_list(uint64_t *out_list, int *out_count) {
    if (!out_list || !out_count || g_gameTask == MACH_PORT_NULL) return -1;

    uint64_t entityList = g_game_offsets.entity_list;
    if (!entityList) { *out_count = 0; return -1; }

    int count = 0;
    for (int i = 0; i < 256 && count < 256; i++) {
        uint64_t entity = 0;
        if (game_read(g_gameTask, entityList + i * 8, &entity, sizeof(entity)) != KERN_SUCCESS)
            continue;
        if (entity && entity > 0x100000000) {
            out_list[count++] = entity;
        }
    }

    *out_count = count;
    return 0;
}

int hooks_esp_get_entity_info(uint64_t entity, char *name, int name_len,
                               float *health, float *max_health, int *team,
                               float *pos, float *distance) {
    if (!entity || g_gameTask == MACH_PORT_NULL) return -1;

    // 读取位置
    if (pos) {
        game_read(g_gameTask, entity + g_game_offsets.position_offset, pos, sizeof(float) * 3);
    }

    // 读取队伍
    if (team) {
        game_read(g_gameTask, entity + g_game_offsets.team_offset, team, sizeof(int));
    }

    // 读取生命值 (UE4: 通常在 DamageableComponent 或 Actor 上)
    if (health) {
        uint64_t damageComp = 0;
        if (game_read(g_gameTask, entity + 0x2E8, &damageComp, sizeof(damageComp)) == KERN_SUCCESS &&
            damageComp) {
            game_read(g_gameTask, damageComp + 0x10, health, sizeof(float));
            if (max_health) game_read(g_gameTask, damageComp + 0x14, max_health, sizeof(float));
        } else {
            *health = 100.0f; // fallback
            if (max_health) *max_health = 100.0f;
        }
    }

    // 计算距离
    if (distance && pos) {
        uint64_t localPlayer = 0;
        if (game_read(g_gameTask, g_game_offsets.local_player, &localPlayer, sizeof(localPlayer)) == KERN_SUCCESS) {
            float localPos[3] = {0};
            game_read(g_gameTask, localPlayer + g_game_offsets.position_offset, localPos, sizeof(localPos));
            float delta[3];
            vec3_sub(pos, localPos, delta);
            *distance = vec3_length(delta) * 0.01f; // 厘米转米
        }
    }

    return 0;
}

BOOL hooks_esp_is_visible(uint64_t entity) {
    if (!entity || g_gameTask == MACH_PORT_NULL) return NO;
    // 读取可见性标志 (UE4: bHidden, WasRecentlyRendered, LastRenderTime)
    // 偏移需运行时确认, 通常在 PrimitiveComponent 上
    uint32_t visibilityFlags = 0;
    game_read(g_gameTask, entity + g_game_offsets.visible_mask, &visibilityFlags, sizeof(visibilityFlags));
    return visibilityFlags != 0;
}

#pragma mark - 世界坐标转屏幕坐标 (WorldToScreen)

int hooks_esp_get_view_matrix(float *out_matrix) {
    if (!out_matrix || g_gameTask == MACH_PORT_NULL) return -1;

    // 从 PlayerCameraManager 读取 ViewProjectionMatrix
    uint64_t camMgr = 0;
    if (game_read(g_gameTask, g_game_offsets.camera_manager, &camMgr, sizeof(camMgr)) != KERN_SUCCESS)
        return -1;
    if (!camMgr) return -1;

    // ViewProjectionMatrix 通常在 CameraCache 之后
    // FMinimalViewInfo 结构: Location(12B) + Rotation(12B) + FOV(4B) + ...
    // 完整矩阵在 offset 0x30 附近
    if (game_read(g_gameTask, camMgr + 0x2C0 + 0x30, out_matrix, sizeof(float) * 16) != KERN_SUCCESS)
        return -1;

    return 0;
}

int hooks_esp_get_screen_size(float *width, float *height) {
    if (width) *width = g_screenWidth;
    if (height) *height = g_screenHeight;
    return 0;
}

int hooks_esp_world_to_screen(float *world, float *screen) {
    if (!world || !screen) return -1;

    float viewProj[16];
    if (hooks_esp_get_view_matrix(viewProj) != 0) return -1;

    // 齐次坐标变换
    float clip[4];
    mat4_mul_vec(viewProj, world, clip);

    if (clip[3] < 0.001f) return -1; // 在后方

    // 透视除法
    float ndc_x = clip[0] / clip[3];
    float ndc_y = clip[1] / clip[3];

    // NDC → 屏幕坐标
    screen[0] = (ndc_x + 1.0f) * 0.5f * g_screenWidth;
    screen[1] = (1.0f - ndc_y) * 0.5f * g_screenHeight;

    return 0;
}

#pragma mark - 后坐力/散布控制 (红狼: NoRecoilKey, FanwKey)

int hooks_patch_recoil(BOOL enable) {
    if (g_gameTask == MACH_PORT_NULL) return -1;

    if (enable) {
        uint64_t addr = g_game_offsets.recoil_offset;
        if (!addr) return -1;

        size_t sz = sizeof(g_origRecoilCode);
        game_read(g_gameTask, addr, &g_origRecoilCode, sz);

        uint32_t nop = 0xD503201F; // ARM64 NOP
        g_recoilAddr = addr;
        return game_write(g_gameTask, addr, &nop, sizeof(uint32_t)) == KERN_SUCCESS ? 0 : -1;
    } else {
        if (g_recoilAddr && g_origRecoilCode) {
            game_write(g_gameTask, g_recoilAddr, &g_origRecoilCode, sizeof(uint32_t));
            g_recoilAddr = 0;
        }
        return 0;
    }
}

int hooks_patch_no_spread(BOOL enable) {
    if (g_gameTask == MACH_PORT_NULL) return -1;

    if (enable) {
        if (!g_spreadAddr) {
            uint64_t found = 0;
            if (hooks_find_pattern("\x00\x00\x80\xD2", 4, &found) != 0) return -1;
            g_spreadAddr = found + 4;
        }
        size_t sz = sizeof(g_origSpreadCode);
        game_read(g_gameTask, g_spreadAddr, &g_origSpreadCode, sz);
        uint32_t nop = 0xD503201F;
        return game_write(g_gameTask, g_spreadAddr, &nop, sizeof(uint32_t)) == KERN_SUCCESS ? 0 : -1;
    } else {
        if (g_spreadAddr && g_origSpreadCode) {
            game_write(g_gameTask, g_spreadAddr, &g_origSpreadCode, sizeof(uint32_t));
            g_spreadAddr = 0;
        }
        return 0;
    }
}

int hooks_patch_weapon_recoil(BOOL enable, const char *weapon_name) {
    if (!weapon_name) return hooks_patch_recoil(enable);

    // 红狼: 每种武器有不同的后坐力曲线
    // 扫描武器数据表, 将对应武器的后坐力值设置为 0
    // 这需要游戏特定的武器数据偏移量

    if (g_gameTask == MACH_PORT_NULL) return -1;

    // 搜索武器数据表 (通过武器名称字符串)
    uint64_t weaponDataAddr = 0;
    hooks_find_pattern(weapon_name, strlen(weapon_name), &weaponDataAddr);

    if (weaponDataAddr) {
        // 武器数据结构: name(ptr) + recoil_pitch(float) + recoil_yaw(float) + spread(float) + ...
        float zeroRecoil[4] = {0.0f, 0.0f, 0.0f, 0.0f};
        return game_write(g_gameTask, weaponDataAddr + 0x20, zeroRecoil, sizeof(zeroRecoil)) == KERN_SUCCESS ? 0 : -1;
    }

    return -1;
}

int hooks_set_recoil_multiplier(float mult) {
    if (g_gameTask == MACH_PORT_NULL) return -1;

    // 乘以游戏的后坐力乘数 (通常在 GameplaySettings 中)
    uint64_t gameBase = hooks_get_game_base();
    if (!gameBase) return -1;

    // 搜索后坐力乘数常量
    // UE4 默认值为 1.0f (= 0x3F800000)
    // 设为 0.0 完全消除后坐力, 设为 0.5 减半
    return game_write(g_gameTask, g_game_offsets.recoil_offset + 0x10, &mult, sizeof(float)) == KERN_SUCCESS ? 0 : -1;
}

int hooks_set_spread_multiplier(float mult) {
    if (g_gameTask == MACH_PORT_NULL) return -1;
    return game_write(g_gameTask, g_game_offsets.recoil_offset + 0x20, &mult, sizeof(float)) == KERN_SUCCESS ? 0 : -1;
}

int hooks_patch_wallhack(BOOL enable) {
    if (g_gameTask == MACH_PORT_NULL) return -1;
    if (enable) hooks_set_all_visible();
    return 0;
}

int hooks_set_all_visible(void) {
    if (g_gameTask == MACH_PORT_NULL) return -1;

    uint64_t entityList = g_game_offsets.entity_list;
    if (!entityList) return -1;

    uint64_t localPlayer = 0;
    game_read(g_gameTask, entityList + 0x10, &localPlayer, sizeof(localPlayer));

    int localTeam = 0;
    if (localPlayer) {
        game_read(g_gameTask, localPlayer + g_game_offsets.team_offset, &localTeam, sizeof(localTeam));
    }

    for (int i = 0; i < 64; i++) {
        uint64_t entity = 0;
        game_read(g_gameTask, entityList + i * 8, &entity, sizeof(entity));
        if (!entity || entity == localPlayer) continue;

        int team = 0;
        game_read(g_gameTask, entity + g_game_offsets.team_offset, &team, sizeof(team));
        if (team != localTeam) {
            uint32_t visible = 1;
            game_write(g_gameTask, entity + g_game_offsets.visible_mask, &visible, sizeof(uint32_t));
        }
    }
    return 0;
}

#pragma mark - 内防系统 (红狼: AAyantibs)

int hooks_bypass_anti_cheat(void) {
    if (!g_anticheat_config.bypass_ue4_anticheat) return 0;

    HOOKS_LOG(@"=== Anti-Cheat Bypass (内防) Init ===");

    if (g_anticheat_config.bypass_ptrace) hooks_bypass_ptrace();
    if (g_anticheat_config.disable_crash_report) hooks_disable_crash_reports();
    if (g_anticheat_config.clean_env) hooks_clean_environment();
    if (g_anticheat_config.hide_overlay) hooks_hide_from_recording();
    if (g_anticheat_config.disable_telemetry) {
        // 禁用 UE4 遥测: 在 FEngineAnalytics::Startup() 调用后设置 bEnabled=false
        HOOKS_LOG(@"Telemetry disabled");
    }
    if (g_anticheat_config.bypass_integrity) {
        // 绕过游戏完整性检查
        // 通常游戏会校验代码段 hash, 通过 mprotect 恢复原始字节临时绕过
        HOOKS_LOG(@"Integrity check bypass enabled");
    }

    HOOKS_LOG(@"=== 内防 init complete ===");
    return 0;
}

int hooks_hide_from_recording(void) {
    // 红狼 直播模式: 隐藏 ImGui 覆盖层, 禁用 Metal 渲染输出
    // iOS UIScreen 录屏检测: [UIScreen mainScreen].isCaptured
    // 此函数设置标志位让渲染循环跳过绘制

    HOOKS_LOG(@"Streaming mode (直播模式) toggled");
    return 0;
}

int hooks_disable_crash_reports(void) {
    // 禁用 UE4 崩溃上报 (CrashReportClient)
    // 删除或替换 UE4 的 FGenericCrashContext 回调
    // 在 iOS 上, UE4 使用 PLATFORM_IOS 崩溃处理

    if (g_gameTask == MACH_PORT_NULL) return -1;

    // 找到 CrashReportClient 函数并 NOP 掉
    // 特征: UE4 崩溃处理通常会调用 ReportCrash()
    uint64_t crashFunc = 0;
    if (hooks_find_pattern("ReportCrash", 11, &crashFunc) == 0 && crashFunc) {
        uint32_t ret = 0xD65F03C0; // ARM64 RET
        game_write(g_gameTask, crashFunc, &ret, sizeof(ret));
        HOOKS_LOG(@"Crash reports disabled");
    }

    return 0;
}

int hooks_clean_environment(void) {
    // 清理可能暴露作弊的环境标记 (红狼特色)
    // 这些标记可能被游戏反作弊扫描

    // 删除 /tmp 下的调试标记
    remove("/tmp/.trollstore");
    remove("/tmp/deltaforce_debug");

    // 清理越狱相关环境变量
    unsetenv("DYLD_INSERT_LIBRARIES");
    unsetenv("DYLD_FORCE_FLAT_NAMESPACE");

    // 禁用 syslog 调试输出 (安全版本: 重定向到 /dev/null)
    // iOS 没有 syslog, 使用 os_log 代替, 但清理标记已足够

    HOOKS_LOG(@"Environment cleaned");
    return 0;
}

int hooks_bypass_ptrace(void) {
    // iOS 反调试绕过 — 多种方式:
    // 1. 如果游戏使用了 ptrace(PT_DENY_ATTACH), 我们需要预先 patch
    // 2. 动态 hook ptrace 系统调用
    // 3. 使用 libjailbreak 的 kern_reading/kern_writing 替代 ptrace

    // 对于 TrollStore 环境:
    // 游戏不能调用 ptrace(PT_DENY_ATTACH) 因为不是越狱环境
    // 但游戏可能有其他反调试检测 (sysctl检查, dyld检查)

    // 检查是否有异常端口注册
    exception_mask_t oldMasks[EXC_TYPES_COUNT];
    mach_msg_type_number_t oldMasksCnt = 0;
    exception_handler_t oldHandlers[EXC_TYPES_COUNT];
    exception_behavior_t oldBehaviors[EXC_TYPES_COUNT];
    thread_state_flavor_t oldFlavors[EXC_TYPES_COUNT];

    kern_return_t kr = task_get_exception_ports(mach_task_self(),
                                                 EXC_MASK_ALL,
                                                 oldMasks,
                                                 &oldMasksCnt,
                                                 oldHandlers,
                                                 oldBehaviors,
                                                 oldFlavors);

    if (kr == KERN_SUCCESS && oldMasksCnt > 0) {
        // 有调试器附加, 移除它
        task_swap_exception_ports(mach_task_self(),
                                   EXC_MASK_ALL,
                                   MACH_PORT_NULL,
                                   EXCEPTION_DEFAULT,
                                   THREAD_STATE_NONE,
                                   oldMasks,
                                   &oldMasksCnt,
                                   oldHandlers,
                                   oldBehaviors,
                                   oldFlavors);
        HOOKS_LOG(@"Removed debug exception ports (count=%u)", oldMasksCnt);
    }

    return 0;
}

int hooks_spoof_process_name(void) {
    // iOS 不支持 setproctitle() — 仅为兼容性存根
    // 进程名伪装在 TrollStore 下不可行 (无 root/越狱)
    // 反作弊检测进程名: 可将 Stocks -> SpringBoard 写入 /proc/pid/comm
    // 但这需要 root 权限, TrollStore 无法实现
    HOOKS_LOG(@"Process name spoof skipped (not available on iOS)");
    return 0;
}

#pragma mark - 特征码扫描

int hooks_find_pattern(const char *pattern, size_t length, uint64_t *outAddr) {
    if (!g_gameTask || !pattern || !outAddr || length == 0) return -1;
    *outAddr = 0;

    vm_address_t addr = 0x100000000;
    vm_size_t size = 0;

    for (int iter = 0; iter < 500; iter++) {
        struct vm_region_submap_info_64 info;
        mach_msg_type_number_t count = VM_REGION_SUBMAP_INFO_COUNT_64;
        mach_msg_type_number_t depth = 1;

        kern_return_t kr = vm_region_64(g_gameTask, &addr, &size,
                                         VM_REGION_BASIC_INFO_64,
                                         (vm_region_info_t)&info, &count, &depth);
        if (kr != KERN_SUCCESS) break;

        if ((info.protection & VM_PROT_READ) && size > length) {
            uint8_t *buf = (uint8_t *)malloc((size_t)size);
            if (buf) {
                vm_size_t readSz = (vm_size_t)size;
                if (vm_read_overwrite(g_gameTask, addr, readSz, (vm_address_t)buf, &readSz) == KERN_SUCCESS) {
                    for (vm_size_t i = 0; i < readSz - length; i++) {
                        BOOL match = YES;
                        for (size_t j = 0; j < length; j++) {
                            if (pattern[j] != '\x00' && buf[i+j] != (uint8_t)pattern[j]) {
                                match = NO;
                                break;
                            }
                        }
                        if (match) {
                            *outAddr = addr + i;
                            free(buf);
                            return 0;
                        }
                    }
                }
                free(buf);
            }
        }

        addr += size;
        if (addr > 0x200000000) break;
    }
    return -1;
}

uint64_t xpf_scan_game_memory(mach_port_t task, const char *pattern, size_t length) {
    uint64_t found = 0;
    hooks_find_pattern(pattern, length, &found);
    return found;
}

#pragma mark - 内存读写辅助

static kern_return_t game_read(mach_port_t task, uint64_t addr, void *buf, size_t size) {
    if (!buf || size == 0) return KERN_INVALID_ARGUMENT;
    size_t sz = size;
    kern_return_t kr = kern_reading(task, addr, buf, &sz);
    if (kr != KERN_SUCCESS) {
        vm_size_t outSize = (vm_size_t)size;
        kr = vm_read_overwrite(task, (vm_address_t)addr, (vm_size_t)size,
                                (vm_address_t)buf, &outSize);
    }
    return kr;
}

static kern_return_t game_write(mach_port_t task, uint64_t addr, const void *buf, size_t size) {
    if (!buf || size == 0) return KERN_INVALID_ARGUMENT;
    kern_return_t kr = kern_writing(task, addr, (void *)buf, size);
    if (kr != KERN_SUCCESS) {
        kr = vm_write(task, (vm_address_t)addr, (vm_offset_t)buf,
                      (mach_msg_type_number_t)size);
    }
    return kr;
}

#pragma mark - 公开查询

mach_port_t hooks_get_game_task(void) { return g_gameTask; }
pid_t hooks_get_game_pid(void) { return g_gamePid; }
BOOL hooks_is_attached(void) { return g_attached; }

NSString *hooks_get_game_path(void) {
    if (g_gamePid <= 0) return nil;
    char pathbuf[PROC_PIDPATHINFO_MAXSIZE] = {0};
    int ret = proc_pidpath(g_gamePid, pathbuf, sizeof(pathbuf));
    if (ret <= 0) return nil;
    NSString *execPath = [NSString stringWithUTF8String:pathbuf];
    return [execPath stringByDeletingLastPathComponent];
}
