// ExternalStubs.c — 外部符号存根实现
// 替代 libjailbreak.dylib / libchoma.dylib 的外部依赖
// TrollStore 安全版本: 不使用任何内核漏洞原语
// 使用标准 Mach VM API 实现进程间内存读写
// 所有函数标记为 weak — dylib 版本优先，存根作为 fallback

#define WEAK_STUB __attribute__((weak))

#include "XPFKernelInterface.h"
#include <mach/mach.h>
#include <mach/mach_host.h>
#include <mach/vm_map.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/sysctl.h>
#include <mach-o/dyld.h>

// === TrollStore 环境检测 ===
static int g_env_type = -1; // -1=未检测, 0=普通, 1=TrollStore, 2=越狱

static int detect_environment(void) {
    if (g_env_type >= 0) return g_env_type;

    // 检测越狱
    if (access("/Applications/Cydia.app", F_OK) == 0 ||
        access("/Library/MobileSubstrate", F_OK) == 0 ||
        access("/usr/lib/libjailbreak.dylib", F_OK) == 0 ||
        access("/var/jb", F_OK) == 0) {
        g_env_type = 2;
        return g_env_type;
    }

    // 检测 TrollStore — 通过包路径特征判断
    // TrollStore 安装的 App 总是在 /var/containers/Bundle/Application/<UUID>/
    char path[1024];
    uint32_t size_path = sizeof(path);
    if (_NSGetExecutablePath(path, &size_path) == 0) {
        if (strstr(path, "/var/containers/Bundle/Application/") ||
            strstr(path, "/private/var/containers/Bundle/Application/")) {
            g_env_type = 1; // TrollStore — 路径匹配就确定
            return g_env_type;
        }
    }

    // 检查 /tmp/.trollstore 标记文件
    FILE *f = fopen("/tmp/.trollstore", "r");
    if (f) {
        fclose(f);
        g_env_type = 1;
        return g_env_type;
    }

    g_env_type = 0;
    return g_env_type;
}

int is_trollstore(void) { return detect_environment() == 1; }
int is_jailbroken(void)  { return detect_environment() == 2; }

#pragma mark - 内核内存读写 (kern_reading / kern_writing)

// 使用 vm_read_overwrite 从目标 task 读取内存
// iOS arm64: vm_address_t 是 64 位
WEAK_STUB kern_return_t kern_reading(mach_port_t task, uint64_t addr, void *buf, size_t *size) {
    // TODO: 确认 dylib 函数签名后再启用路由
    // if (dylib_kern_reading) return dylib_kern_reading(task, addr, buf, size);

    if (!buf || !size || *size == 0) return KERN_INVALID_ARGUMENT;

    vm_size_t out_size = (vm_size_t)(*size);
    kern_return_t kr = vm_read_overwrite(
        task,
        (vm_address_t)addr,
        (vm_size_t)(*size),
        (vm_address_t)buf,
        &out_size
    );

    if (kr == KERN_SUCCESS) {
        *size = (size_t)out_size;
    }
    return kr;
}

// 使用 vm_write 向目标 task 写入内存
WEAK_STUB kern_return_t kern_writing(mach_port_t task, uint64_t addr, void *buf, size_t size) {
    // TODO: 确认 dylib 函数签名后再启用路由
    // if (dylib_kern_writing) return dylib_kern_writing(task, addr, buf, size);

    if (!buf || size == 0) return KERN_INVALID_ARGUMENT;

    return vm_write(
        task,
        (vm_address_t)addr,
        (vm_offset_t)buf,
        (mach_msg_type_number_t)size
    );
}

#pragma mark - 越狱初始化 (jb_init)

// 安全版本: 检测环境,不调用危险操作
// 重要: TrollStore 下不需要 jb_init 做任何事
// kern_reading/kern_writing 的 WEAK stub 直接用 vm_read_overwrite/vm_write
// 配合 task_for_pid-allow 就能读写游戏内存
WEAK_STUB int jb_init(void) {
    int env = detect_environment();

    switch (env) {
        case 2: // 越狱
            fprintf(stderr, "[Stubs] jb_init: jailbreak — attempting kernel_task\n");
            {
                mach_port_t kt = MACH_PORT_NULL;
                if (task_for_pid(mach_task_self(), 0, &kt) == KERN_SUCCESS && kt != MACH_PORT_NULL) {
                    fprintf(stderr, "[Stubs] jb_init: kernel_task=%x\n", kt);
                    mach_port_deallocate(mach_task_self(), kt);
                }
            }
            break;
        case 1: // TrollStore
            fprintf(stderr, "[Stubs] jb_init: TrollStore mode — using userspace Mach VM API\n");
            fprintf(stderr, "[Stubs] jb_init: no kernel exploit needed, task_for_pid works via entitlement\n");
            break;
        default:
            fprintf(stderr, "[Stubs] jb_init: normal sandboxed app — limited functionality\n");
            break;
    }
    return 0;
}

#pragma mark - 物理内存操作 (仅越狱可用)

WEAK_STUB uint64_t physread64(uint64_t phys_addr) {
    (void)phys_addr;
    if (!is_jailbroken()) return 0;
    // 需要 libjailbreak.dylib 提供真实实现
    fprintf(stderr, "[Stubs] physread64: not available (need jailbreak)\n");
    return 0;
}

WEAK_STUB int physwritebuf(uint64_t phys_addr, void *buffer, size_t size) {
    (void)phys_addr; (void)buffer; (void)size;
    if (!is_jailbroken()) return -1;
    fprintf(stderr, "[Stubs] physwritebuf: not available (need jailbreak)\n");
    return -1;
}

WEAK_STUB uint64_t phystokv(uint64_t phys_addr) {
    (void)phys_addr;
    return 0;
}

WEAK_STUB uint64_t vtophys(uint64_t virt_addr) {
    (void)virt_addr;
    return 0;
}

#pragma mark - 内核任务获取 (安全版本)

// 安全获取 kernel_task 端口
WEAK_STUB kern_return_t exploit_get_kernel_task(mach_port_t *task) {
    if (!task) return KERN_INVALID_ARGUMENT;
    *task = MACH_PORT_NULL;

    int env = detect_environment();

    // 越狱: 标准路径
    if (env == 2) {
        kern_return_t kr = task_for_pid(mach_task_self(), 0, task);
        if (kr == KERN_SUCCESS && *task != MACH_PORT_NULL) {
            return KERN_SUCCESS;
        }
        kr = host_get_special_port(mach_host_self(), 0, 4, task);
        if (kr == KERN_SUCCESS && *task != MACH_PORT_NULL) {
            return KERN_SUCCESS;
        }
    }

    // TrollStore: kernel_task 不可用 (这是正常的)
    // task_for_pid-allow 给了我们访问游戏进程 task port 的能力
    // 但 kernel_task (pid=0) 需要 system-task-ports, TrollStore 没有
    if (env == 1) {
        // 尝试但不指望成功
        kern_return_t kr = host_get_special_port(mach_host_self(), 0, 4, task);
        if (kr == KERN_SUCCESS && *task != MACH_PORT_NULL) {
            fprintf(stderr, "[Stubs] kernel_task obtained via host_get_special_port (rare!)\n");
            return KERN_SUCCESS;
        }
        fprintf(stderr, "[Stubs] kernel_task not available on TrollStore (expected — using task_for_pid per-game)\n");
        return KERN_FAILURE;
    }

    // 通用 fallback: task_for_pid(0) — 越狱下有戏, 正常情况下不行
    {
        kern_return_t kr = task_for_pid(mach_task_self(), 0, task);
        if (kr == KERN_SUCCESS && *task != MACH_PORT_NULL) {
            fprintf(stderr, "[Stubs] kernel_task via task_for_pid(0)\n");
            return KERN_SUCCESS;
        }
    }

    fprintf(stderr, "[Stubs] kernel_task not available (env=%d, expected on TrollStore)\n", env);
    return KERN_FAILURE;
}

#pragma mark - KASLR 偏移

WEAK_STUB uint64_t get_kernel_slide(void) {
    if (!is_jailbroken()) return 0;

    // 从 sysctl 读取内核基址
    size_t size = 0;
    sysctlbyname("kern.osrelease", NULL, &size, NULL, 0);
    return 0; // 存根, 需要 libjailbreak 提供
}

#pragma mark - 线程上下文

WEAK_STUB uint64_t get_current_thread_context(void) {
    // kcall 需要越狱 + 内核符号
    return 0;
}

#pragma mark - kcall 设置

WEAK_STUB void xpf_setup_kcall_primitive(void) {
    if (is_jailbroken()) {
        fprintf(stderr, "[Stubs] xpf_setup_kcall_primitive: stub (need libjailbreak)\n");
    }
}

#pragma mark - 内核进程附加

WEAK_STUB kern_return_t xpf_attach_kernel_task(uint64_t proc, mach_port_t *task) {
    if (!task) return KERN_INVALID_ARGUMENT;
    *task = MACH_PORT_NULL;

    pid_t pid = (pid_t)proc;

    // 方法1: 直接 task_for_pid (越狱或 TrollStore 都可能失败)
    kern_return_t kr = task_for_pid(mach_task_self(), pid, task);
    if (kr == KERN_SUCCESS && *task != MACH_PORT_NULL) {
        return KERN_SUCCESS;
    }

    // 方法2: 通过 kernel_task 读取目标进程的 task port
    // 如果有 kernel_task, 可以从内核内存直接读取目标进程的 ipc_entry
    // 这需要 libjailbreak.dylib 的真实实现
    mach_port_t kt = MACH_PORT_NULL;
    if (exploit_get_kernel_task(&kt) == KERN_SUCCESS && kt != MACH_PORT_NULL) {
        fprintf(stderr, "[Stubs] xpf_attach_kernel_task: have kernel_task=%x, need real dylib for kread\n", kt);
        // 真实 dylib 的 kern_reading 可以读内核地址空间的 task 结构
        // 这里作为 fallback, 返回 kernel_task 本身
        // 调用者应使用 kern_reading(kernel_task, ...) 进行内存访问
    }

    // 方法3: host_get_special_port 获取游戏进程的 task port
    // 在 TrollStore 下可能被拦截
    kr = host_get_special_port(mach_host_self(), 0, pid, task);
    if (kr == KERN_SUCCESS && *task != MACH_PORT_NULL) {
        fprintf(stderr, "[Stubs] xpf_attach_kernel_task: got task via host_get_special_port\n");
        return KERN_SUCCESS;
    }

    fprintf(stderr, "[Stubs] xpf_attach_kernel_task(%llu): all methods failed\n", proc);
    return KERN_FAILURE;
}

#pragma mark - dylib 注入

WEAK_STUB int xpf_inject_dylib(int pid, const char *dylib_path) {
    fprintf(stderr, "[Stubs] xpf_inject_dylib(%d, %s): not supported without jailbreak\n",
            pid, dylib_path ? dylib_path : "NULL");
    return -1;
}

#pragma mark - phystokv / vtophys 补充

WEAK_STUB uint64_t phystokv_impl(uint64_t phys_addr) {
    (void)phys_addr;
    return 0;
}
