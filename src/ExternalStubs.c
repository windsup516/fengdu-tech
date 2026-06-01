// ExternalStubs.c — 外部符号存根实现
// 替代 libjailbreak.dylib / libchoma.dylib 的外部依赖
// TrollStore 安全版本: 不使用任何内核漏洞原语
// 使用标准 Mach VM API 实现进程间内存读写

#include "XPFKernelInterface.h"
#include <mach/mach.h>
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

    // 检测 TrollStore (CoreTrust bug)
    if (access("/var/mobile/Library/Caches/com.apple.mobile.installation.plist", F_OK) != 0) {
        // 检查是否有 /var/containers/Bundle/tmp/.trollstore 标记
        FILE *f = fopen("/tmp/.trollstore", "r");
        if (f) { fclose(f); g_env_type = 1; return g_env_type; }
    }

    // 检查是否通过 TrollStore 安装 (包路径特征)
    char path[1024];
    uint32_t size = sizeof(path);
    if (_NSGetExecutablePath(path, &size) == 0) {
        if (strstr(path, "/var/containers/Bundle/Application/") ||
            strstr(path, "/private/var/containers/Bundle/Application/")) {
            // 检查是否有 task_for_pid 权限
            mach_port_t test = MACH_PORT_NULL;
            kern_return_t kr = task_for_pid(mach_task_self(), getpid(), &test);
            if (kr == KERN_SUCCESS) {
                mach_port_deallocate(mach_task_self(), test);
                g_env_type = 1; // TrollStore with tfp0
            } else {
                g_env_type = 0;
            }
            return g_env_type;
        }
    }

    g_env_type = 0;
    return g_env_type;
}

int is_trollstore(void) { return detect_environment() == 1; }
int is_jailbroken(void)  { return detect_environment() == 2; }

#pragma mark - 内核内存读写 (kern_reading / kern_writing)

// 使用 vm_read_overwrite 从目标 task 读取内存
// iOS arm64: vm_address_t 是 64 位
kern_return_t kern_reading(mach_port_t task, uint64_t addr, void *buf, size_t *size) {
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
kern_return_t kern_writing(mach_port_t task, uint64_t addr, void *buf, size_t size) {
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
int jb_init(void) {
    int env = detect_environment();

    if (env == 2) {
        fprintf(stderr, "[Stubs] jb_init: jailbreak detected\n");
        // 越狱环境: 尝试获取 kernel_task
        mach_port_t kt = MACH_PORT_NULL;
        kern_return_t kr = task_for_pid(mach_task_self(), 0, &kt);
        if (kr == KERN_SUCCESS && kt != MACH_PORT_NULL) {
            mach_port_deallocate(mach_task_self(), kt);
            return 0;
        }
        // 越狱但没有 tfp0, 降级使用 userspace
        return 0;
    }

    if (env == 1) {
        fprintf(stderr, "[Stubs] jb_init: TrollStore detected, using userspace only\n");
        return 0;
    }

    // 普通环境: 无任何特殊权限
    fprintf(stderr, "[Stubs] jb_init: normal environment, limited functionality\n");
    return 0;
}

#pragma mark - 物理内存操作 (仅越狱可用)

uint64_t physread64(uint64_t phys_addr) {
    (void)phys_addr;
    if (!is_jailbroken()) return 0;
    // 需要 libjailbreak.dylib 提供真实实现
    fprintf(stderr, "[Stubs] physread64: not available (need jailbreak)\n");
    return 0;
}

int physwritebuf(uint64_t phys_addr, void *buffer, size_t size) {
    (void)phys_addr; (void)buffer; (void)size;
    if (!is_jailbroken()) return -1;
    fprintf(stderr, "[Stubs] physwritebuf: not available (need jailbreak)\n");
    return -1;
}

uint64_t phystokv(uint64_t phys_addr) {
    (void)phys_addr;
    return 0;
}

uint64_t vtophys(uint64_t virt_addr) {
    (void)virt_addr;
    return 0;
}

#pragma mark - 内核任务获取 (安全版本)

// 安全获取 kernel_task 端口
kern_return_t exploit_get_kernel_task(mach_port_t *task) {
    if (!task) return KERN_INVALID_ARGUMENT;
    *task = MACH_PORT_NULL;

    int env = detect_environment();

    if (env == 2) {
        // 越狱环境: 尝试获取
        kern_return_t kr = task_for_pid(mach_task_self(), 0, task);
        if (kr == KERN_SUCCESS && *task != MACH_PORT_NULL) {
            return KERN_SUCCESS;
        }

        kr = host_get_special_port(mach_host_self(), 0, 4, task);
        if (kr == KERN_SUCCESS && *task != MACH_PORT_NULL) {
            return KERN_SUCCESS;
        }
    }

    // TrollStore 或普通环境: 无内核访问
    fprintf(stderr, "[Stubs] kernel_task not available in current environment\n");
    return KERN_FAILURE;
}

#pragma mark - KASLR 偏移

uint64_t get_kernel_slide(void) {
    if (!is_jailbroken()) return 0;

    // 从 sysctl 读取内核基址
    size_t size = 0;
    sysctlbyname("kern.osrelease", NULL, &size, NULL, 0);
    return 0; // 存根, 需要 libjailbreak 提供
}

#pragma mark - 线程上下文

uint64_t get_current_thread_context(void) {
    // kcall 需要越狱 + 内核符号
    return 0;
}

#pragma mark - kcall 设置

void xpf_setup_kcall_primitive(void) {
    if (is_jailbroken()) {
        fprintf(stderr, "[Stubs] xpf_setup_kcall_primitive: stub (need libjailbreak)\n");
    }
}

#pragma mark - 内核进程附加

kern_return_t xpf_attach_kernel_task(uint64_t proc, mach_port_t *task) {
    if (!task) return KERN_INVALID_ARGUMENT;
    if (!is_jailbroken()) {
        *task = MACH_PORT_NULL;
        return KERN_FAILURE;
    }
    return task_for_pid(mach_task_self(), 0, task);
}

#pragma mark - dylib 注入

int xpf_inject_dylib(int pid, const char *dylib_path) {
    fprintf(stderr, "[Stubs] xpf_inject_dylib(%d, %s): not supported without jailbreak\n",
            pid, dylib_path ? dylib_path : "NULL");
    return -1;
}

#pragma mark - phystokv / vtophys 补充

uint64_t phystokv_impl(uint64_t phys_addr) {
    (void)phys_addr;
    return 0;
}
