// DylibInjector — Mach VM dylib injection into game process
// Uses task_for_pid + Mach VM to inject DFOverlay.dylib into game
// Game process is ALWAYS foreground → render context never dies

#import <Foundation/Foundation.h>
#import <mach/mach.h>
#import <mach-o/loader.h>
#import <dlfcn.h>
#import "Logging.h"

// Strip code signature from Mach-O binary so it can be loaded by a DIFFERENT process
// Without this, AMFI kills the game when dlopen sees Stocks-signed dylib loaded into DeltaForce
static int strip_macho_signature(const char *path) {
    FILE *f = fopen(path, "r+b");
    if (!f) return -1;

    uint32_t magic;
    if (fread(&magic, sizeof(magic), 1, f) != 1) { fclose(f); return -1; }

    // Handle FAT binary (shouldn't happen for our thin dylib, but be safe)
    uint32_t narch = 0;
    if (magic == FAT_MAGIC || magic == FAT_CIGAM) {
        if (magic == FAT_CIGAM) magic = FAT_MAGIC; // Big-endian FAT not supported
        if (fread(&narch, sizeof(narch), 1, f) != 1) { fclose(f); return -1; }
        if (narch > 4) { fclose(f); return -1; }
        // Read first arch offset
        struct { uint32_t cputype, cpusubtype; uint32_t offset, size, align; } arch;
        int found_arm64 = 0;
        for (uint32_t i = 0; i < narch; i++) {
            if (fread(&arch, sizeof(arch), 1, f) != 1) { fclose(f); return -1; }
            if (arch.cputype == CPU_TYPE_ARM64) { found_arm64 = 1; break; }
        }
        if (!found_arm64) { fclose(f); return -1; }
        fseek(f, arch.offset, SEEK_SET);
        if (fread(&magic, sizeof(magic), 1, f) != 1) { fclose(f); return -1; }
    }

    if (magic != MH_MAGIC_64) { fclose(f); return -1; }

    struct mach_header_64 hdr;
    // magic is already consumed (4 bytes) — read remaining header fields
    fread(&hdr.cputype, sizeof(hdr.cputype), 1, f);
    fread(&hdr.cpusubtype, sizeof(hdr.cpusubtype), 1, f);
    fread(&hdr.filetype, sizeof(hdr.filetype), 1, f);
    fread(&hdr.ncmds, sizeof(hdr.ncmds), 1, f);
    fread(&hdr.sizeofcmds, sizeof(hdr.sizeofcmds), 1, f);
    fread(&hdr.flags, sizeof(hdr.flags), 1, f);
    fread(&hdr.reserved, sizeof(hdr.reserved), 1, f);

    for (uint32_t i = 0; i < hdr.ncmds; i++) {
        long cmd_start = ftell(f);
        uint32_t cmd, cmdsize;
        if (fread(&cmd, sizeof(cmd), 1, f) != 1) break;
        if (fread(&cmdsize, sizeof(cmdsize), 1, f) != 1) break;

        if (cmd == LC_CODE_SIGNATURE) {
            // Null out the cmd type (keep cmdsize so dyld advances safely)
            // dyld treats unknown cmd=0 as a no-op and skips by cmdsize bytes
            fseek(f, cmd_start, SEEK_SET);
            uint32_t null_cmd = 0;
            fwrite(&null_cmd, sizeof(null_cmd), 1, f);
            fclose(f);
            SAFE_LOG(@">> Stripped LC_CODE_SIGNATURE from %s", path);
            return 0;
        }

        fseek(f, cmd_start + cmdsize, SEEK_SET);
    }

    fclose(f);
    return 0; // No signature found — already stripped
}

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
// dylibPath MUST be a path accessible to the remote process (e.g., /tmp/xxx)
static kern_return_t inject_via_mach(pid_t pid, const char *dylibPath) {
    task_t remoteTask = MACH_PORT_NULL;
    kern_return_t kr;
    mach_vm_address_t remoteBase = 0;

    // Step 1: Get task port
    kr = task_for_pid(mach_task_self(), pid, &remoteTask);
    if (kr != KERN_SUCCESS) {
        SAFE_LOG(@">> task_for_pid(%d) FAILED: %s", pid, mach_error_string(kr));
        return kr;
    }
    SAFE_LOG(@">> task_for_pid(%d) OK, task_port=0x%x", pid, remoteTask);

    // Step 2: Find dlopen in dyld_shared_cache (same address in all processes)
    void *dlopenPtr = dlsym(RTLD_DEFAULT, "dlopen");
    if (!dlopenPtr) {
        SAFE_LOG(@">> dlsym(dlopen) FAILED");
        mach_port_deallocate(mach_task_self(), remoteTask);
        return KERN_FAILURE;
    }
    SAFE_LOG(@">> dlopen @ %p", dlopenPtr);

    // Step 3: Allocate remote memory for dylib path + stack
    size_t pathLen = strlen(dylibPath) + 1;
    size_t allocSize = pathLen + 0x4000; // path + 16KB for stack

    kr = mach_vm_allocate(remoteTask, &remoteBase, allocSize, VM_FLAGS_ANYWHERE);
    if (kr != KERN_SUCCESS) {
        SAFE_LOG(@">> vm_allocate FAILED: %s", mach_error_string(kr));
        mach_port_deallocate(mach_task_self(), remoteTask);
        return kr;
    }
    SAFE_LOG(@">> remote mem @ 0x%llx (%zu bytes)", remoteBase, allocSize);

    // Step 4: Write dylib path
    kr = mach_vm_write(remoteTask, remoteBase,
                       (vm_offset_t)dylibPath, (mach_msg_type_number_t)pathLen);
    if (kr != KERN_SUCCESS) {
        SAFE_LOG(@"Inject: vm_write failed: %s", mach_error_string(kr));
        goto cleanup;
    }

    // Step 5: Build ARM64 shellcode at remoteBase + pathLen + 0x1000
    uint64_t codeAddr = (remoteBase + 0x2000) & ~0xFFFULL;
    uint64_t stackAddr = codeAddr + 0x2000;

    // ARM64 assembly:
    //   sub sp, sp, #32
    //   stp x29, x30, [sp, #16]
    //   add x29, sp, #16
    //   movz x0, #<path_lo> ; movk x0, #...   // path arg
    //   movz x1, #9                            // RTLD_LAZY | RTLD_GLOBAL
    //   movz x16, #<dlopen_lo> ; movk x16, #...
    //   blr x16                                // dlopen(path, RTLD_LAZY|RTLD_GLOBAL)
    //   cbz x0, .Lexit                         // if NULL, skip constructor call
    //   ldp x29, x30, [sp, #16]
    //   add sp, sp, #32
    // .Lexit:
    //   mov x0, #0
    //   mov x16, #1                            // SYS_exit
    //   svc #0x80                              // thread exit (no crash)

    uint32_t shellcode[40];
    int ci = 0;
    uint64_t path = remoteBase;
    uint64_t fn = (uint64_t)dlopenPtr;

    shellcode[ci++] = 0xD10083FF; // sub sp, sp, #32
    shellcode[ci++] = 0xA9017BFD; // stp x29, x30, [sp, #16]
    shellcode[ci++] = 0x910043FD; // add x29, sp, #16

    // movz/movk x0 with path address
    shellcode[ci++] = 0xD2800000 | ((path & 0xFFFF) << 5);
    shellcode[ci++] = 0xF2A00000 | (((path >> 16) & 0xFFFF) << 5);
    shellcode[ci++] = 0xF2C00000 | (((path >> 32) & 0xFFFF) << 5);
    shellcode[ci++] = 0xF2E00000 | (((path >> 48) & 0xFFFF) << 5);

    // x1 = RTLD_LAZY(1) | RTLD_GLOBAL(8) = 9
    shellcode[ci++] = 0xD2800121; // mov x1, #9

    // movz/movk x16 with dlopen address
    shellcode[ci++] = 0xD2800000 | ((fn & 0xFFFF) << 5) | 0x10;
    shellcode[ci++] = 0xF2A00000 | (((fn >> 16) & 0xFFFF) << 5) | 0x10;
    shellcode[ci++] = 0xF2C00000 | (((fn >> 32) & 0xFFFF) << 5) | 0x10;
    shellcode[ci++] = 0xF2E00000 | (((fn >> 48) & 0xFFFF) << 5) | 0x10;

    shellcode[ci++] = 0xD63F0200; // blr x16
    // x0 now = dlopen() return value (handle or NULL)

    shellcode[ci++] = 0xB4000040; // cbz x0, skip_cleanup (skip stack restore if NULL)
    shellcode[ci++] = 0xA9417BFD; // ldp x29, x30, [sp, #16]
    shellcode[ci++] = 0x910083FF; // add sp, sp, #32

    // skip_cleanup: thread exit via SYS_exit (no crash even if dlopen failed)
    shellcode[ci++] = 0xD2800000; // mov x0, #0
    shellcode[ci++] = 0xD2800021; // mov x1, #1 (= SYS_exit on iOS/arm64)
    shellcode[ci++] = 0xD2800010; // mov x16, #1
    shellcode[ci++] = 0xD4000801; // svc #0x80

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
    state.__pc = codeAddr;
    state.__sp = stackAddr;
    state.__fp = 0;
    state.__lr = 0;
    state.__x[0] = path;
    state.__x[1] = 9; // RTLD_LAZY | RTLD_GLOBAL
    state.__cpsr = 0;

    thread_act_t remoteThread = MACH_PORT_NULL;
    kr = thread_create_running(remoteTask, ARM_THREAD_STATE64,
                               (thread_state_t)&state, ARM_THREAD_STATE64_COUNT,
                               &remoteThread);
    if (kr != KERN_SUCCESS) {
        SAFE_LOG(@"Inject: thread_create failed: %s", mach_error_string(kr));
        goto cleanup;
    }

    SAFE_LOG(@">> remote thread RUNNING — dlopen(%s) executing in game", dylibPath);
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
    SAFE_LOG(@">> inject_dylib_to_pid: %s -> PID %d", dylibName, pid);

    // Resolve dylib path inside Stocks bundle
    NSString *fwPath = [[[NSBundle mainBundle] bundlePath]
        stringByAppendingPathComponent:[NSString stringWithFormat:@"Frameworks/%s", dylibName]];

    if (![[NSFileManager defaultManager] fileExistsAtPath:fwPath]) {
        fwPath = [[[NSBundle mainBundle] bundlePath]
            stringByAppendingPathComponent:[NSString stringWithUTF8String:dylibName]];
    }

    if (![[NSFileManager defaultManager] fileExistsAtPath:fwPath]) {
        SAFE_LOG(@">> INJECT FAIL: dylib file not found at %s", [fwPath UTF8String]);
        return -1;
    }

    SAFE_LOG(@">> dylib source: %s", [fwPath UTF8String]);

    // Copy to /tmp/ so game process can read it (iOS sandbox prevents cross-app bundle access)
    NSString *tmpPath = [NSString stringWithFormat:@"/tmp/%s", dylibName];
    NSError *copyErr = nil;
    [[NSFileManager defaultManager] removeItemAtPath:tmpPath error:nil];
    if (![[NSFileManager defaultManager] copyItemAtPath:fwPath toPath:tmpPath error:&copyErr]) {
        SAFE_LOG(@">> INJECT FAIL: copy to /tmp/ failed: %s", [[copyErr description] UTF8String]);
        return -1;
    }
    SAFE_LOG(@">> dylib copied to: %s", [tmpPath UTF8String]);

    // CRITICAL: Strip code signature — dylib is signed for Stocks.app
    // but loaded by DeltaForce game process. AMFI kills the game if
    // it sees a foreign-signed dylib being dlopen'd.
    strip_macho_signature([tmpPath UTF8String]);

    const char *path = [tmpPath UTF8String];

    // Method 1: Try xpf_inject_dylib from libjailbreak
    typedef int (*xpf_inject_func)(int, const char*);
    xpf_inject_func xpf_inject = (xpf_inject_func)dlsym(RTLD_DEFAULT, "xpf_inject_dylib");
    if (xpf_inject) {
        int ret = xpf_inject(pid, path);
        if (ret == 0) {
            SAFE_LOG(@">> xpf_inject_dylib OK");
            return 0;
        }
        SAFE_LOG(@">> xpf_inject_dylib returned %d, trying Mach VM...", ret);
    } else {
        SAFE_LOG(@">> xpf_inject_dylib not available, using Mach VM");
    }

    // Method 2: Mach VM injection
    kern_return_t kr = inject_via_mach(pid, path);
    if (kr == KERN_SUCCESS) {
        SAFE_LOG(@">> Mach VM injection OK — dylib constructor should fire now");
        return 0;
    }

    SAFE_LOG(@">> ALL INJECTION METHODS FAILED (kr=%d: %s)", kr, mach_error_string(kr));
    return -1;
}
