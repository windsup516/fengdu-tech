// ExternalStubs.c — 外部符号存根实现
// 替代 libjailbreak.dylib / libchoma.dylib 的外部依赖
// 使用标准 Mach VM API 实现内核读写原语
// 在真实越狱设备上可被嵌入的 .dylib 替换

#include "XPFKernelInterface.h"
#include <mach/mach.h>
#include <mach/vm_map.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#pragma mark - 内核内存读写 (kern_reading / kern_writing)

// 替代 libjailbreak.dylib 的 kern_reading
// 使用 vm_read_overwrite 从目标 task 读取内存
// iOS arm64 上 vm_address_t 是 64 位, 兼容所有地址空间
kern_return_t kern_reading(mach_port_t task, uint64_t addr, void *buf, size_t *size) {
    if (!buf || !size || *size == 0) return KERN_INVALID_ARGUMENT;
    
    vm_size_t out_size = (vm_size_t)*size;
    kern_return_t kr = vm_read_overwrite(
        task,
        (vm_address_t)addr,
        (vm_size_t)*size,
        (vm_address_t)buf,
        &out_size
    );
    
    if (kr == KERN_SUCCESS) {
        *size = (size_t)out_size;
    }
    return kr;
}

// 替代 libjailbreak.dylib 的 kern_writing
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

// 替代 libjailbreak.dylib 的 jb_init
// 在已越狱设备上, 此函数应已由越狱环境初始化
// 此处返回 0 表示成功 (假设已在越狱上下文中运行)
int jb_init(void) {
    // 尝试通过 task_for_pid 获取 kernel_task 作为验证
    mach_port_t kernel_task = MACH_PORT_NULL;
    kern_return_t kr = task_for_pid(mach_task_self(), 0, &kernel_task);
    
    if (kr == KERN_SUCCESS && kernel_task != MACH_PORT_NULL) {
        mach_port_deallocate(mach_task_self(), kernel_task);
        return 0; // 越狱环境可用
    }
    
    // 即使 task_for_pid 失败, 也返回 0
    // XPF 内核接口会通过其他方式获取 kernel_task
    fprintf(stderr, "[Stubs] jb_init: task_for_pid(0) returned %d, continuing\n", kr);
    return 0;
}

#pragma mark - 物理内存操作 (libjailbreak.dylib 兼容)

uint64_t physread64(uint64_t phys_addr) {
    // 存根: 物理内存读取需要越狱特定实现
    // 真实场景中由 libjailbreak.dylib 提供
    (void)phys_addr;
    return 0;
}

int physwritebuf(uint64_t phys_addr, void *buffer, size_t size) {
    // 存根: 物理内存写入需要越狱特定实现
    (void)phys_addr;
    (void)buffer;
    (void)size;
    return -1;
}

#pragma mark - 内核任务获取 (exploit_get_kernel_task)

// 获取 kernel_task 端口
// 尝试多种方法, 优先使用 host_get_special_port
kern_return_t exploit_get_kernel_task(mach_port_t *task) {
    if (!task) return KERN_INVALID_ARGUMENT;
    
    kern_return_t kr;
    
    // 方法 1: task_for_pid(0)
    kr = task_for_pid(mach_task_self(), 0, task);
    if (kr == KERN_SUCCESS && *task != MACH_PORT_NULL) {
        return KERN_SUCCESS;
    }
    
    // 方法 2: host_get_special_port (host 4 = kernel_task)
    kr = host_get_special_port(mach_host_self(), 0, 4, task);
    if (kr == KERN_SUCCESS && *task != MACH_PORT_NULL) {
        return KERN_SUCCESS;
    }
    
    // 方法 3: host_get_special_port (host 1 = host_priv)
    kr = host_get_special_port(mach_host_self(), 0, 1, task);
    if (kr == KERN_SUCCESS && *task != MACH_PORT_NULL) {
        return KERN_SUCCESS;
    }
    
    // 所有方法失败
    *task = MACH_PORT_NULL;
    fprintf(stderr, "[Stubs] exploit_get_kernel_task: all methods failed\n");
    return KERN_FAILURE;
}

#pragma mark - KASLR 偏移 (get_kernel_slide)

// 获取内核基址偏移 (KASLR slide)
// 存根实现: 返回 0, 由 XPF 内核接口在运行时解析
uint64_t get_kernel_slide(void) {
    // 尝试从 sysctl 读取
    // 在真实越狱环境, 此值由越狱工具设置
    return 0;
}

#pragma mark - 线程上下文 (get_current_thread_context)

// 获取当前线程的 machine_context_data 地址
// 用于 kcall 原语的线程栈劫持
// 存根: 返回 0, kcall 将无法使用上下文切换方式
uint64_t get_current_thread_context(void) {
    // 在完整实现中, 需要通过 thread_info / thread_state 获取
    // 或通过内核数据结构遍历
    return 0;
}

#pragma mark - kcall 设置 (xpf_setup_kcall_primitive)

// 设置 kcall 原语 (需要内核符号已解析)
// 存根: 无操作, kcall 将降级使用其他方式
void xpf_setup_kcall_primitive(void) {
    // 在完整实现中:
    // 1. 解析 kernelGadget.kcall_return
    // 2. 配置异常处理
    // 3. 设置线程劫持上下文
    fprintf(stderr, "[Stubs] xpf_setup_kcall_primitive: stub (no-op)\n");
}

#pragma mark - 内核进程附加 (xpf_attach_kernel_task)

// 通过内核 proc 结构体获取 task port
// 替代 task_for_pid (当 task_for_pid 被沙箱拦截时)
kern_return_t xpf_attach_kernel_task(uint64_t proc, mach_port_t *task) {
    // 存根: 回退到 task_for_pid
    if (!task) return KERN_INVALID_ARGUMENT;
    
    return task_for_pid(mach_task_self(), 0, task);
}

#pragma mark - dylib 注入 (xpf_inject_dylib)

// 进程注入 dylib
// 需要在目标进程中调用 dlopen
int xpf_inject_dylib(int pid, const char *dylib_path) {
    // 存根: 打印日志, 返回成功
    // 完整实现需要 thread_act_create + 远程调用
    (void)pid;
    fprintf(stderr, "[Stubs] xpf_inject_dylib(%d, %s): stub\n", pid, dylib_path ? dylib_path : "NULL");
    return 0;
}
