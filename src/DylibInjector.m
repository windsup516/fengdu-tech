// DylibInjector — Mach VM dylib injection into game process
// Uses task_for_pid + Mach VM to inject DFOverlay.dylib into game
// Game process is ALWAYS foreground → render context never dies

#import <Foundation/Foundation.h>
#import <mach/mach.h>
#import <dlfcn.h>
#import "Logging.h"

// mach_vm functions (declared manually — mach_vm.h is unsupported in theos SDK)
extern kern_return_t mach_vm_allocate(task_t task, mach_vm_address_t *addr,
    mach_vm_size_t size, int flags);
extern kern_return_t mach_vm_deallocate(task_t task, mach_vm_address_t addr,
    mach_vm_size_t size);
extern kern_return_t mach_vm_write(task_t task, mach_vm_address_t addr,
    vm_offset_t data, mach_msg_type_number_t size);
extern kern_return_t mach_vm_protect(task_t task, mach_vm_address_t addr,
    mach_vm_size_t size, boolean_t set_maximum, vm_prot_t new_protection);

// arm_thread_state64_t and ARM_THREAD_STATE64_COUNT are from <mach/arm/thread_status.h>

// === Core injection: allocate + write + create remote thread ===
static kern_return_t inject_via_mach(pid_t pid, const char *dylibPath) {
    task_t remoteTask = MACH_PORT_NULL;
    kern_return_t kr;
    mach_vm_address_t remoteBase = 0;

    // Step 1: Get task port
    kr = task_for_pid(mach_task_self(), pid, &remoteTask);
    if (kr != KERN_SUCCESS) {
        SAFE_LOG(@"Inject: task_for_pid(%d) failed: %s", pid, mach_error_string(kr));
        return kr;
    }
    SAFE_LOG(@"Inject: task_for_pid(%d) OK", pid);

    // Step 2: Find dlopen in dyld_shared_cache (same address in all processes)
    void *dlopenPtr = dlsym(RTLD_DEFAULT, "dlopen");
    if (!dlopenPtr) {
        SAFE_LOG(@"Inject: dlsym(dlopen) failed");
        mach_port_deallocate(mach_task_self(), remoteTask);
        return KERN_FAILURE;
    }
    SAFE_LOG(@"Inject: dlopen @ %p", dlopenPtr);

    // Step 3: Allocate remote memory for dylib path + stack
    size_t pathLen = strlen(dylibPath) + 1;
    size_t allocSize = pathLen + 0x4000; // path + 16KB for stack

    kr = mach_vm_allocate(remoteTask, &remoteBase, allocSize, VM_FLAGS_ANYWHERE);
    if (kr != KERN_SUCCESS) {
        SAFE_LOG(@"Inject: vm_allocate failed: %s", mach_error_string(kr));
        mach_port_deallocate(mach_task_self(), remoteTask);
        return kr;
    }

    // Step 4: Write dylib path
    kr = mach_vm_write(remoteTask, remoteBase,
                       (vm_offset_t)dylibPath, (mach_msg_type_number_t)pathLen);
    if (kr != KERN_SUCCESS) {
        SAFE_LOG(@"Inject: vm_write failed: %s", mach_error_string(kr));
        goto cleanup;
    }

    // Step 5: Build ARM64 shellcode at remoteBase + pathLen + 0x1000
    // Align to page boundary
    uint64_t codeAddr = (remoteBase + 0x2000) & ~0xFFFULL;
    uint64_t stackAddr = codeAddr + 0x2000; // stack grows down

    // ARM64 assembly to call dlopen(path, RTLD_NOW):
    //   sub sp, sp, #16
    //   stp x29, x30, [sp]
    //   add x29, sp, #0
    //   mov x0, #<path_lo>
    //   movk x0, #<path_hi16>, lsl #16
    //   movk x0, #<path_hi32>, lsl #32
    //   movk x0, #<path_hi48>, lsl #48
    //   mov x1, #2                    // RTLD_NOW
    //   mov x16, #<dlopen_lo>
    //   movk x16, #<dlopen_hi16>, lsl #16
    //   movk x16, #<dlopen_hi32>, lsl #32
    //   movk x16, #<dlopen_hi48>, lsl #48
    //   blr x16
    //   ldp x29, x30, [sp]
    //   add sp, sp, #16
    //   mov x0, #0
    //   brk #0                        // trap to exit thread

    uint32_t shellcode[32];
    int ci = 0;
    uint64_t path = remoteBase;
    uint64_t fn = (uint64_t)dlopenPtr;

    shellcode[ci++] = 0xD10043FF; // sub sp, sp, #16
    shellcode[ci++] = 0xA9007BFD; // stp x29, x30, [sp]
    shellcode[ci++] = 0x910003FD; // add x29, sp, #0

    // movz/movk x0 with path address
    shellcode[ci++] = 0xD2800000 | ((path & 0xFFFF) << 5);
    shellcode[ci++] = 0xF2A00000 | (((path >> 16) & 0xFFFF) << 5);
    shellcode[ci++] = 0xF2C00000 | (((path >> 32) & 0xFFFF) << 5);
    shellcode[ci++] = 0xF2E00000 | (((path >> 48) & 0xFFFF) << 5);

    // RTLD_NOW = 2 (prefer NOW so constructor runs immediately)
    shellcode[ci++] = 0xD2800041; // mov x1, #2

    // movz/movk x16 with dlopen address, then blr
    shellcode[ci++] = 0xD2800000 | ((fn & 0xFFFF) << 5) | 0x10;
    shellcode[ci++] = 0xF2A00000 | (((fn >> 16) & 0xFFFF) << 5) | 0x10;
    shellcode[ci++] = 0xF2C00000 | (((fn >> 32) & 0xFFFF) << 5) | 0x10;
    shellcode[ci++] = 0xF2E00000 | (((fn >> 48) & 0xFFFF) << 5) | 0x10;
    shellcode[ci++] = 0xD63F0200; // blr x16

    shellcode[ci++] = 0xA9407BFD; // ldp x29, x30, [sp]
    shellcode[ci++] = 0x910043FF; // add sp, sp, #16
    shellcode[ci++] = 0xD2800000; // mov x0, #0
    shellcode[ci++] = 0xD4200000; // brk #0

    size_t codeSize = ci * sizeof(uint32_t);

    // Step 6: Write shellcode
    kr = mach_vm_write(remoteTask, codeAddr, (vm_offset_t)shellcode,
                       (mach_msg_type_number_t)codeSize);
    if (kr != KERN_SUCCESS) {
        SAFE_LOG(@"Inject: shellcode write failed: %s", mach_error_string(kr));
        goto cleanup;
    }

    // Step 7: Make code executable
    kr = mach_vm_protect(remoteTask, codeAddr, 0x4000, FALSE,
                         VM_PROT_READ | VM_PROT_EXECUTE);
    if (kr != KERN_SUCCESS) {
        SAFE_LOG(@"Inject: vm_protect failed: %s (continuing anyway)", mach_error_string(kr));
    }

    // Step 8: Create remote thread with proper ARM state
    arm_thread_state64_t state;
    memset(&state, 0, sizeof(state));
    state.pc = codeAddr;
    state.sp = stackAddr;
    state.fp = 0;
    state.lr = 0;
    state.x[0] = path;
    state.x[1] = 2; // RTLD_NOW
    state.cpsr = 0;

    thread_act_t remoteThread = MACH_PORT_NULL;
    kr = thread_create_running(remoteTask, ARM_THREAD_STATE64,
                               (thread_state_t)&state, ARM_THREAD_STATE64_COUNT,
                               &remoteThread);
    if (kr != KERN_SUCCESS) {
        SAFE_LOG(@"Inject: thread_create failed: %s", mach_error_string(kr));
        goto cleanup;
    }

    SAFE_LOG(@"Inject: remote thread created OK, dylib loading...");
    mach_port_deallocate(mach_task_self(), remoteThread);
    mach_port_deallocate(mach_task_self(), remoteTask);
    return KERN_SUCCESS;

cleanup:
    mach_vm_deallocate(remoteTask, remoteBase, allocSize);
    mach_port_deallocate(mach_task_self(), remoteTask);
    return kr;
}

// === Public API ===
int inject_dylib_to_pid(pid_t pid, const char *dylibName) {
    SAFE_LOG(@"=== Inject: %s -> PID %d ===", dylibName, pid);

    // Resolve dylib path
    NSString *fwPath = [[[NSBundle mainBundle] bundlePath]
        stringByAppendingPathComponent:[NSString stringWithFormat:@"Frameworks/%s", dylibName]];

    if (![[NSFileManager defaultManager] fileExistsAtPath:fwPath]) {
        fwPath = [[[NSBundle mainBundle] bundlePath]
            stringByAppendingPathComponent:[NSString stringWithUTF8String:dylibName]];
    }

    if (![[NSFileManager defaultManager] fileExistsAtPath:fwPath]) {
        SAFE_LOG(@"Inject: dylib file not found: %s", [fwPath UTF8String]);
        return -1;
    }

    const char *path = [fwPath UTF8String];
    SAFE_LOG(@"Inject: dylib path = %s", path);

    // Method 1: Try xpf_inject_dylib from libjailbreak (kernel approach, more reliable)
    typedef int (*xpf_inject_func)(int, const char*);
    xpf_inject_func xpf_inject = (xpf_inject_func)dlsym(RTLD_DEFAULT, "xpf_inject_dylib");
    if (xpf_inject) {
        int ret = xpf_inject(pid, path);
        if (ret == 0) {
            SAFE_LOG(@"Inject: xpf_inject_dylib OK");
            return 0;
        }
        SAFE_LOG(@"Inject: xpf_inject_dylib returned %d, falling back to Mach VM", ret);
    }

    // Method 2: Mach VM injection
    kern_return_t kr = inject_via_mach(pid, path);
    if (kr == KERN_SUCCESS) {
        SAFE_LOG(@"Inject: Mach VM injection OK");
        return 0;
    }

    SAFE_LOG(@"Inject: FAILED (kr=%d: %s)", kr, mach_error_string(kr));
    return -1;
}
