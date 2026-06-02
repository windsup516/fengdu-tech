// GameHooks - Delta Force 游戏内存钩子 (TrollStore 兼容版)
// 使用 mach_vm_read/write (无需内核 exploit)
// 支持运行时特征码扫描定位偏移

#import "GameHooks.h"
#import "XPFKernelInterface.h"
#import <mach/mach.h>
#import <mach/vm_map.h>
#import <mach-o/loader.h>

#import <dlfcn.h>

#ifndef GAME_PROCESS_NAME
#define GAME_PROCESS_NAME "DeltaForceClient"
#endif

// 额外的游戏进程名候选 (Delta Force 在不同地区/版本有不同的进程名)
static const char *g_game_process_names[] = {
    "DeltaForceClient",
    "DeltaForce",
    "DFM",
    "dfm",
    "tmgp",
    "Star",
    "Delta",
    NULL
};

// === 游戏偏移 (运行时扫描填充) ===
GameOffsets g_game_offsets = {0};

// 保存原始指令用于恢复
static uint32_t g_origRecoilCode = 0;
static uint32_t g_origSpreadCode = 0;
static uint64_t g_recoilAddr = 0;
static uint64_t g_spreadAddr = 0;

// 游戏进程句柄
static mach_port_t g_gameTask = MACH_PORT_NULL;
static pid_t g_gamePid = 0;
static BOOL g_attached = NO;

// 前向声明
static kern_return_t game_read(mach_port_t task, uint64_t addr, void *buf, size_t size);
static kern_return_t game_write(mach_port_t task, uint64_t addr, const void *buf, size_t size);

// 文件日志 — 与 main.m 的 SAFE_LOG 写入同一个 debug.log
static FILE *g_hooksLogFile = NULL;
static void hooks_log(NSString *fmt, ...) {
    if (!g_hooksLogFile) {
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        if (paths.count > 0) {
            NSString *logPath = [paths[0] stringByAppendingPathComponent:@"debug.log"];
            g_hooksLogFile = fopen([logPath UTF8String], "a");
        }
    }
    va_list args;
    va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    fprintf(stderr, "[Hooks] %s\n", [msg UTF8String]);
    if (g_hooksLogFile) {
        time_t now = time(NULL);
        struct tm *tm_info = localtime(&now);
        char time_buf[16];
        strftime(time_buf, sizeof(time_buf), "%H:%M:%S", tm_info);
        fprintf(g_hooksLogFile, "%s [Hooks] %s\n", time_buf, [msg UTF8String]);
        fflush(g_hooksLogFile);
    }
}

#pragma mark - 进程查找与附加

// 通过进程名查找 PID — 三层 fallback
//   1. proc_listallpids (libproc, 不走 sysctl)
//   2. proc_listpids(PROC_ALL_PIDS) 备选
//   3. PID 暴力扫描 (task_for_pid + proc_name)
static pid_t find_pid_by_name_multi(const char **names) {
    int pidbuf[1024];
    int npids = 0;
    static BOOL dumpedOnce = NO;

    // === 方法1: proc_listallpids ===
    errno = 0;
    npids = proc_listallpids(pidbuf, sizeof(pidbuf));
    hooks_log(@"proc_listallpids: ret=%d errno=%d bufsize=%zu",
              npids, errno, sizeof(pidbuf));

    // === 方法2: proc_listpids (fallback) ===
    if (npids <= 0) {
        hooks_log(@"proc_listallpids returned %d, trying proc_listpids...", npids);
        errno = 0;
        npids = proc_listpids(1 /* PROC_ALL_PIDS */, 0, pidbuf, sizeof(pidbuf));
        hooks_log(@"proc_listpids: ret=%d errno=%d", npids, errno);
    }

    // === 方法3: PID 暴力扫描 ===
    if (npids <= 0) {
        hooks_log(@"libproc enumeration failed, falling back to PID brute force...");
        pid_t bf_found = -1;
        int scanned = 0, success = 0;
        // 游戏进程通常在 300-1500 范围
        for (pid_t p = 100; p < 2000; p++) {
            mach_port_t testTask = MACH_PORT_NULL;
            if (task_for_pid(mach_task_self(), p, &testTask) != KERN_SUCCESS) {
                continue;
            }
            success++;
            // task_for_pid 成功后必须释放端口
            mach_port_deallocate(mach_task_self(), testTask);

            char pname[64] = {0};
            proc_name(p, pname, sizeof(pname) - 1);
            if (pname[0] == '\0') continue;
            scanned++;

            for (const char **n = names; *n; n++) {
                if (strcasecmp(pname, *n) == 0) {
                    bf_found = p;
                    hooks_log(@"Brute force found: '%s' PID=%d (matched '%s', scanned=%d success=%d)",
                              [NSString stringWithUTF8String:pname], p,
                              [NSString stringWithUTF8String:*n], scanned, success);
                    return bf_found;
                }
            }
            // 子串匹配兜底
            if (strcasestr(pname, "delta") || strcasestr(pname, "dfm") ||
                strcasestr(pname, "tmgp") || strcasestr(pname, "force")) {
                bf_found = p;
                hooks_log(@"Brute force substring: '%s' PID=%d (scanned=%d success=%d)",
                          [NSString stringWithUTF8String:pname], p, scanned, success);
                return bf_found;
            }
        }
        hooks_log(@"PID brute force exhausted: scanned=%d task_for_pid_success=%d",
                  scanned, success);
        return bf_found;
    }

    int count = npids;
    if (!dumpedOnce) {
        dumpedOnce = YES;
        hooks_log(@"=== All running processes (first 200 of %d) ===", count);
        for (int i = 0; i < count && i < 200; i++) {
            char pname[64] = {0};
            proc_name(pidbuf[i], pname, sizeof(pname) - 1);
            hooks_log(@"  [%d] %s", pidbuf[i], pname);
        }
        hooks_log(@"=== End process list ===");
    }

    pid_t found = -1;

    for (int i = 0; i < count; i++) {
        char pname[64] = {0};
        proc_name(pidbuf[i], pname, sizeof(pname) - 1);
        if (pname[0] == '\0') continue;

        for (const char **n = names; *n; n++) {
            if (strcasecmp(pname, *n) == 0) {
                found = pidbuf[i];
                hooks_log(@"Found game process: '%s' PID=%d (matched '%s')",
                          [NSString stringWithUTF8String:pname], found,
                          [NSString stringWithUTF8String:*n]);
                return found;
            }
        }
    }

    for (int i = 0; i < count; i++) {
        char pname[64] = {0};
        proc_name(pidbuf[i], pname, sizeof(pname) - 1);
        if (strcasestr(pname, "delta") || strcasestr(pname, "dfm") ||
            strcasestr(pname, "tmgp") || strcasestr(pname, "force") ||
            strcasestr(pname, "star")) {
            found = pidbuf[i];
            hooks_log(@"Found game process via substring: '%s' PID=%d",
                      [NSString stringWithUTF8String:pname], found);
            return found;
        }
    }

    return -1;
}

int hooks_attach_to_game(void) {
    if (g_attached && g_gameTask != MACH_PORT_NULL) return 0;

    pid_t pid = find_pid_by_name_multi(g_game_process_names);
    if (pid < 0) {
        hooks_log(@"Game process not found");
        return -1;
    }

    g_gamePid = pid;
    kern_return_t kr = task_for_pid(mach_task_self(), pid, &g_gameTask);
    if (kr != KERN_SUCCESS) {
        hooks_log(@"task_for_pid(%d) failed: %d (need entitlement)", pid, kr);
        g_gameTask = MACH_PORT_NULL;
        return -2;
    }

    g_attached = YES;
    hooks_log(@"Attached to game PID=%d task=%x", pid, g_gameTask);

    // 后台扫描游戏基址
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        hooks_scan_offsets();
    });

    return 0;
}

#pragma mark - 运行时偏移扫描

int hooks_scan_offsets(void) {
    if (g_gameTask == MACH_PORT_NULL) return -1;

    // 获取游戏基址
    uint64_t gameBase = hooks_get_game_base();
    if (!gameBase) {
        hooks_log(@"Cannot find game base address");
        return -1;
    }
    hooks_log(@"Game base: 0x%llx", gameBase);

    // 扫描 __TEXT 段获取可执行内存范围
    uint64_t textStart = gameBase;
    uint64_t textEnd = gameBase + 0x20000000; // 256MB 范围

    // UE4/PhysX 引擎特征模式:
    // GWorld 通常通过 GEngine->GameViewport->World 访问
    // 实体列表在 ULevel->Actors

    // 扫描 GEngine 指针 (特征: 被多处引用的全局指针)
    // 扫描 UWorld 结构

    // 对于 DeltaForce (PhysX + 自定义引擎):
    // 实体列表通常在数据段中的固定结构
    // 我们需要通过已知偏移来验证

    // 暂时使用硬编码偏移作为 fallback, 运行时扫描作为增强
    // 这些偏移需要通过实际调试获取
    g_game_offsets.entity_list     = gameBase + 0x0EDF000;
    g_game_offsets.local_player    = gameBase + 0x0EE1000;
    g_game_offsets.camera_manager  = gameBase + 0x0EE2000;
    g_game_offsets.visible_mask    = gameBase + 0x0EE3000;
    g_game_offsets.health_offset   = 0x120;
    g_game_offsets.team_offset     = 0xF0;
    g_game_offsets.position_offset = 0x180;
    g_game_offsets.view_angle_offset = 0x1C0;
    g_game_offsets.weapon_offset   = 0x2A0;
    g_game_offsets.aimbot_angle    = gameBase + 0x0EE4000;
    g_game_offsets.recoil_offset   = 0x2B0;

    hooks_log(@" Offsets initialized (base=0x%llx)", gameBase);
    return 0;
}

uint64_t hooks_get_game_base(void) {
    if (g_gameTask == MACH_PORT_NULL) return 0;

    // 通过 vm_region 遍历获取第一个可执行区域
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

        // 查找第一个可执行的大区域 (>1MB)
        if ((info.protection & VM_PROT_EXECUTE) && size > 0x100000) {
            // 验证是否为 Mach-O 头部
            uint32_t magic = 0;
            size_t magicSz = sizeof(magic);
            if (game_read(g_gameTask, addr, &magic, magicSz) == KERN_SUCCESS) {
                if (magic == MH_MAGIC_64 || magic == 0xCFAEDFE7) { // FAT 或 arm64
                    return addr;
                }
            }
        }

        addr += size;
        if (addr > 0x200000000) break; // 安全上限
    }

    return 0;
}

#pragma mark - 内存补丁

int hooks_patch_recoil(BOOL enable) {
    if (g_gameTask == MACH_PORT_NULL) return -1;

    if (enable) {
        uint64_t addr = g_game_offsets.recoil_offset;
        if (!addr) return -1;

        // 保存原始值
        size_t sz = sizeof(g_origRecoilCode);
        game_read(g_gameTask, addr, &g_origRecoilCode, sz);

        // ARM64 NOP (4字节)
        uint32_t nop = 0xD503201F;
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
            // 需要扫描散布函数
            uint64_t found = 0;
            if (hooks_find_pattern("\x00\x00\x80\xD2", 4, &found) != 0) return -1;
            g_spreadAddr = found + 4; // 跳过前4字节
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
    size_t lpSz = sizeof(localPlayer);
    game_read(g_gameTask, entityList + 0x10, &localPlayer, lpSz);

    int localTeam = 0;
    if (localPlayer) {
        size_t ltSz = sizeof(localTeam);
        game_read(g_gameTask, localPlayer + g_game_offsets.team_offset, &localTeam, ltSz);
    }

    for (int i = 0; i < 64; i++) {
        uint64_t entity = 0;
        size_t enSz = sizeof(entity);
        game_read(g_gameTask, entityList + i * 8, &entity, enSz);
        if (!entity || entity == localPlayer) continue;

        int team = 0;
        size_t tmSz = sizeof(team);
        game_read(g_gameTask, entity + g_game_offsets.team_offset, &team, tmSz);
        if (team != localTeam) {
            uint32_t visible = 1;
            game_write(g_gameTask, entity + g_game_offsets.visible_mask, &visible, sizeof(uint32_t));
        }
    }
    return 0;
}

#pragma mark - 自瞄

int hooks_aimbot(uint64_t targetEntity) {
    if (g_gameTask == MACH_PORT_NULL || !targetEntity) return -1;

    float targetPos[3] = {0};
    size_t tpSz = sizeof(targetPos);
    game_read(g_gameTask, targetEntity + g_game_offsets.position_offset, targetPos, tpSz);

    uint64_t localPlayer = 0;
    size_t lpSz = sizeof(localPlayer);
    game_read(g_gameTask, g_game_offsets.local_player, &localPlayer, lpSz);
    if (!localPlayer) return -1;

    float localPos[3] = {0};
    size_t lposSz = sizeof(localPos);
    game_read(g_gameTask, localPlayer + g_game_offsets.position_offset, localPos, lposSz);

    float dx = targetPos[0] - localPos[0];
    float dy = targetPos[1] - localPos[1];
    float dz = targetPos[2] - localPos[2];
    float dist = sqrtf(dx*dx + dy*dy + dz*dz);
    if (dist < 0.1f) return 0;

    float yaw = atan2f(dy, dx) * (180.0f / M_PI);
    float pitch = -asinf(dz / dist) * (180.0f / M_PI);

    float angles[2] = {yaw, pitch};
    game_write(g_gameTask, g_game_offsets.aimbot_angle, angles, sizeof(float) * 2);
    return 0;
}

#pragma mark - 特征码扫描

int hooks_find_pattern(const char *pattern, size_t length, uint64_t *outAddr) {
    if (!g_gameTask || !pattern || !outAddr || length == 0) return -1;
    *outAddr = 0;

    vm_address_t addr = 0x100000000; // 从常见基址开始
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
    vm_size_t outSize = (vm_size_t)size;
    return vm_read_overwrite(task, (vm_address_t)addr, (vm_size_t)size,
                              (vm_address_t)buf, &outSize);
}

static kern_return_t game_write(mach_port_t task, uint64_t addr, const void *buf, size_t size) {
    if (!buf || size == 0) return KERN_INVALID_ARGUMENT;
    return vm_write(task, (vm_address_t)addr, (vm_offset_t)buf,
                    (mach_msg_type_number_t)size);
}

#pragma mark - 公开查询

mach_port_t hooks_get_game_task(void) { return g_gameTask; }
pid_t hooks_get_game_pid(void) { return g_gamePid; }
BOOL hooks_is_attached(void) { return g_attached; }

NSString *hooks_get_game_path(void) {
    if (g_gamePid <= 0) return nil;
    char pathbuf[PROC_PIDPATHINFO_MAXSIZE] = {0};
    int ret = proc_pidpath(g_gamePid, pathbuf, sizeof(pathbuf));
    if (ret <= 0) {
        hooks_log(@" proc_pidpath(%d) failed: %d (%s)", g_gamePid, ret, strerror(errno));
        return nil;
    }
    // pathbuf = /var/.../DeltaForceClient.app/DeltaForceClient
    NSString *execPath = [NSString stringWithUTF8String:pathbuf];
    // .app 目录就是父目录
    return [execPath stringByDeletingLastPathComponent];
}

// XPF 兼容的内核附加 (TrollStore 下仅回退到 task_for_pid)
__unused static kern_return_t game_hooks_attach_kernel_task(uint64_t proc, mach_port_t *task) {
    (void)proc;
    *task = g_gameTask;
    return g_gameTask != MACH_PORT_NULL ? KERN_SUCCESS : KERN_FAILURE;
}
