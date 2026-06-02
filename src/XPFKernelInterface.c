// XPF Kernel Interface - 弱符号存根 (libjailbreak.dylib 可覆盖)
// 标记为 WEAK 的函数可被 dylib 中的真实实现覆盖

#include "XPFKernelInterface.h"
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <mach/mach.h>
#include <mach/mach_host.h>
#include <sys/sysctl.h>

#define XPF_WEAK __attribute__((weak))

// === Dylib 函数指针 (全局, 由 main.m 的 resolve_dylib_functions 赋值) ===
kern_return_t (*dylib_kern_reading)(mach_port_t task, uint64_t addr, void *buf, size_t *size) = NULL;
kern_return_t (*dylib_kern_writing)(mach_port_t task, uint64_t addr, void *buf, size_t size) = NULL;
uint64_t (*dylib_kcall)(uint64_t func, uint64_t *args, int arg_count, uint64_t *result) = NULL;
void * (*dylib_kalloc)(uint64_t size) = NULL;
uint64_t (*dylib_physread64)(uint64_t phys_addr) = NULL;
int (*dylib_physwritebuf)(uint64_t phys_addr, void *buffer, size_t size) = NULL;

// === 内核状态 ===
static struct {
    mach_port_t kernel_task;
    uint64_t kernel_base;
    uint64_t kernel_slide;
    bool initialized;
} g_kernel = {0};

// 环境检测函数 (在 ExternalStubs.c 中定义)
extern int is_trollstore(void);
extern int is_jailbroken(void);

// === API 实现 ===

int xpf_initialize_kernel(void) {
    if (g_kernel.initialized) return 0;

    // 检测环境
    if (is_jailbroken()) {
        // 越狱: 尝试获取 kernel_task
        kern_return_t kr = task_for_pid(mach_task_self(), 0, &g_kernel.kernel_task);
        if (kr == KERN_SUCCESS && g_kernel.kernel_task != MACH_PORT_NULL) {
            g_kernel.initialized = true;
            fprintf(stderr, "[XPF] Initialized (jailbreak, kernel_task=%x)\n", g_kernel.kernel_task);
            return 0;
        }
    }

    // TrollStore: 尝试通过 libjailbreak.dylib 的 exploit_get_kernel_task 获取内核端口
    // exploit_get_kernel_task 可能在 TS 环境下使用 CoreTrust 绕过获取内核 r/w
    {
        kern_return_t kr = exploit_get_kernel_task(&g_kernel.kernel_task);
        if (kr == KERN_SUCCESS && g_kernel.kernel_task != MACH_PORT_NULL) {
            g_kernel.initialized = true;
            fprintf(stderr, "[XPF] Initialized (TrollStore+kernel_task via exploit, task=%x)\n",
                    g_kernel.kernel_task);
            return 0;
        }
    }

    // 尝试 host_get_special_port (某些 iOS 版本允许)
    {
        kern_return_t kr = host_get_special_port(mach_host_self(), 0, 4, &g_kernel.kernel_task);
        if (kr == KERN_SUCCESS && g_kernel.kernel_task != MACH_PORT_NULL) {
            g_kernel.initialized = true;
            fprintf(stderr, "[XPF] Initialized (kernel_task via host_get_special_port, task=%x)\n",
                    g_kernel.kernel_task);
            return 0;
        }
    }

    // 无内核访问: 标记为已初始化但仅 userspace
    g_kernel.kernel_task = MACH_PORT_NULL;
    g_kernel.initialized = true;
    fprintf(stderr, "[XPF] Initialized (userspace-only mode, no kernel_task)\n");
    return 0;
}

int xpf_resolve_all_symbols(void) {
    if (!g_kernel.initialized) return -1;
    if (!is_jailbroken()) {
        // TrollStore: 无内核符号表, 需要使用运行时扫描
        return 0;
    }
    return 0;
}

uint64_t xpf_find_symbol(const char *name) {
    (void)name;
    return 0; // 需要内核符号表
}

uint64_t xpf_get_symbol(const char *name) {
    (void)name;
    return 0;
}

// === kcall 原语 (弱符号, dylib 可覆盖) ===

XPF_WEAK kern_return_t xpf_kcall(uint64_t func, uint64_t *args, int arg_count, uint64_t *result) {
    (void)func; (void)args; (void)arg_count;
    if (result) *result = 0;
    fprintf(stderr, "[XPF] xpf_kcall: WEAK stub\n");
    return KERN_FAILURE;
}

// === 物理内存 (仅越狱) ===

uint64_t xpf_phys_to_virt(uint64_t phys_addr) {
    (void)phys_addr;
    return 0;
}

int xpf_phys_read(uint64_t phys_addr, void *buffer, size_t size) {
    (void)phys_addr; (void)buffer; (void)size;
    return -1;
}

int xpf_phys_write(uint64_t phys_addr, void *buffer, size_t size) {
    (void)phys_addr; (void)buffer; (void)size;
    return -1;
}

// === 进程操作 ===

uint64_t xpf_find_process(const char *proc_name) {
    // 使用 sysctl 查找进程 (userspace, 无需特殊权限)
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0};
    size_t bufSize = 0;
    if (sysctl(mib, 4, NULL, &bufSize, NULL, 0) != 0) return 0;

    struct kinfo_proc *procs = (struct kinfo_proc *)malloc(bufSize);
    if (!procs) return 0;
    if (sysctl(mib, 4, procs, &bufSize, NULL, 0) != 0) { free(procs); return 0; }

    int count = (int)(bufSize / sizeof(struct kinfo_proc));
    uint64_t found = 0;
    for (int i = 0; i < count; i++) {
        if (strcmp(procs[i].kp_proc.p_comm, proc_name) == 0) {
            found = (uint64_t)procs[i].kp_proc.p_pid; // 返回 PID 作为标识
            break;
        }
    }
    free(procs);
    return found;
}

int xpf_get_process_pid(uint64_t proc) {
    return (int)proc; // proc 本身就是 PID (userspace fallback)
}

XPF_WEAK int xpf_sandbox_escape(uint64_t proc) {
    (void)proc;
    fprintf(stderr, "[XPF] xpf_sandbox_escape: WEAK stub (dylib not loaded or no exploit)\n");
    return 0;
}

// === PPL / AMFI / 开发者模式 (弱符号, dylib 可覆盖) ===

XPF_WEAK int xpf_ppl_bypass_init(void) {
    fprintf(stderr, "[XPF] xpf_ppl_bypass_init: WEAK stub\n");
    return 0;
}
XPF_WEAK int xpf_bypass_developer_mode(void) {
    fprintf(stderr, "[XPF] xpf_bypass_developer_mode: WEAK stub\n");
    return 0;
}
XPF_WEAK int xpf_disable_amfi(void) {
    fprintf(stderr, "[XPF] xpf_disable_amfi: WEAK stub\n");
    return 0;
}
