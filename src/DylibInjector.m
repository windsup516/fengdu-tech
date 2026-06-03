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
    if (magic != MH_MAGIC_64) { fclose(f); return -1; } // Thin arm64 only

    struct mach_header_64 hdr;
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

// Helper: encode a 64-bit immediate into movz/movk instructions for reg (Rd)
static void encode_mov64(uint32_t *out, int *ci, int rd, uint64_t val) {
    out[(*ci)++] = 0xD2800000 | ((val & 0xFFFF) << 5) | rd;
    out[(*ci)++] = 0xF2A00000 | (((val >> 16) & 0xFFFF) << 5) | rd;
    out[(*ci)++] = 0xF2C00000 | (((val >> 32) & 0xFFFF) << 5) | rd;
    out[(*ci)++] = 0xF2E00000 | (((val >> 48) & 0xFFFF) << 5) | rd;
}

// === Core injection: write dylib into game memory, shellcode writes to file + dlopen ===
// iOS /tmp/ is SANDBOXED per-app, so Stocks can't write a file the game can read.
// Instead: copy dylib bytes into game memory, shellcode writes them to game's own /tmp/
static kern_return_t inject_via_mach(pid_t pid, const char *localPath, const char *remotePath) {
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

    // Step 2: Read dylib file into local buffer + resolve shared cache functions
    void *dlopenPtr = dlsym(RTLD_DEFAULT, "dlopen");
    void *openPtr  = dlsym(RTLD_DEFAULT, "open");
    void *writePtr = dlsym(RTLD_DEFAULT, "write");
    void *closePtr = dlsym(RTLD_DEFAULT, "close");
    if (!dlopenPtr || !openPtr || !writePtr || !closePtr) {
        SAFE_LOG(@">> dlsym FAILED: dlopen=%p open=%p write=%p close=%p",
                 dlopenPtr, openPtr, writePtr, closePtr);
        mach_port_deallocate(mach_task_self(), remoteTask);
        return KERN_FAILURE;
    }
    SAFE_LOG(@">> dlopen=%p open=%p write=%p close=%p",
             dlopenPtr, openPtr, writePtr, closePtr);

    // Read dylib from local filesystem
    FILE *df = fopen(localPath, "rb");
    if (!df) {
        SAFE_LOG(@">> fopen(%s) FAILED", localPath);
        mach_port_deallocate(mach_task_self(), remoteTask);
        return KERN_FAILURE;
    }
    fseek(df, 0, SEEK_END);
    size_t dylibSize = ftell(df);
    fseek(df, 0, SEEK_SET);
    uint8_t *dylibData = (uint8_t *)malloc(dylibSize);
    if (!dylibData || fread(dylibData, 1, dylibSize, df) != dylibSize) {
        SAFE_LOG(@">> read dylib FAILED (size=%zu)", dylibSize);
        free(dylibData); fclose(df);
        mach_port_deallocate(mach_task_self(), remoteTask);
        return KERN_FAILURE;
    }
    fclose(df);
    SAFE_LOG(@">> dylib read: %zu bytes", dylibSize);

    // Step 3: Allocate remote memory: path + dylib_data + shellcode + stack
    size_t pathLen = strlen(remotePath) + 1;
    size_t pathOff = 0;
    size_t dataOff = (pathLen + 0xFF) & ~0xFF; // 256-byte align
    size_t dataSize = (dylibSize + 0xFF) & ~0xFF;
    size_t codeOff = dataOff + dataSize;
    size_t stackOff = codeOff + 0x2000;
    size_t allocSize = stackOff + 0x4000; // +16KB stack

    kr = mach_vm_allocate(remoteTask, &remoteBase, allocSize, VM_FLAGS_ANYWHERE);
    if (kr != KERN_SUCCESS) {
        SAFE_LOG(@">> vm_allocate FAILED: %s", mach_error_string(kr));
        free(dylibData);
        mach_port_deallocate(mach_task_self(), remoteTask);
        return kr;
    }
    SAFE_LOG(@">> remote mem @ 0x%llx (%zu bytes)", remoteBase, allocSize);

    // Step 4: Write remote path string (game's /tmp/DFOverlay.dylib)
    kr = mach_vm_write(remoteTask, remoteBase + pathOff,
                       (vm_offset_t)remotePath, (mach_msg_type_number_t)pathLen);
    if (kr != KERN_SUCCESS) {
        SAFE_LOG(@"Inject: path write failed: %s", mach_error_string(kr));
        goto cleanup;
    }

    // Step 5: Write dylib data bytes
    kr = mach_vm_write(remoteTask, remoteBase + dataOff,
                       (vm_offset_t)dylibData, (mach_msg_type_number_t)dylibSize);
    free(dylibData);
    if (kr != KERN_SUCCESS) {
        SAFE_LOG(@"Inject: dylib data write failed: %s", mach_error_string(kr));
        goto cleanup;
    }

    // Step 6: Build shellcode
    // Layout:
    //   x19 = path addr (callee-saved)
    //   x20 = dylib data addr
    //   x21 = dylib size
    //   x22 = fd (saved across calls)
    //
    //   sub sp, sp, #64
    //   stp x29, x30, [sp, #16]
    //   stp x21, x22, [sp, #32]
    //   stp x19, x20, [sp, #48]
    //   add x29, sp, #16
    //
    //   ; Load addresses into x19,x20,x21
    //   movz x19, path_lo; movk ...    ; path
    //   movz x20, data_lo; movk ...    ; dylib_data
    //   movz  w21, size_lo; movk ...   ; size (32-bit fits <4GB)
    //
    //   ; open(path, O_CREAT|O_WRONLY|O_TRUNC, 0644)
    //   mov x0, x19
    //   movz x1, #0x601
    //   movz x2, #0x1A4
    //   movz x16, open_lo; movk ...
    //   blr x16
    //   mov x22, x0           ; save fd
    //
    //   ; write(fd, data, size)
    //   mov x1, x20
    //   mov x2, x21           ; x0 still has fd
    //   movz x16, write_lo; movk ...
    //   blr x16
    //
    //   ; close(fd)
    //   mov x0, x22
    //   movz x16, close_lo; movk ...
    //   blr x16
    //
    //   ; dlopen(path, RTLD_LAZY|RTLD_GLOBAL)
    //   mov x0, x19
    //   movz x1, #9
    //   movz x16, dlopen_lo; movk ...
    //   blr x16
    //
    //   ; Cleanup & exit
    //   cbz x0, .Lexit
    //   ldp x19, x20, [sp, #48]
    //   ldp x21, x22, [sp, #32]
    //   ldp x29, x30, [sp, #16]
    //   add sp, sp, #64
    // .Lexit:
    //   mov x0, #0
    //   mov x16, #1
    //   svc #0x80

    uint64_t pathAddr = remoteBase + pathOff;
    uint64_t dataAddr = remoteBase + dataOff;
    uint64_t fn_dlopen = (uint64_t)dlopenPtr;
    uint64_t fn_open   = (uint64_t)openPtr;
    uint64_t fn_write  = (uint64_t)writePtr;
    uint64_t fn_close  = (uint64_t)closePtr;

    uint32_t sc[128];
    int ci = 0;

    // Prologue
    sc[ci++] = 0xD10103FF; // sub sp, sp, #64
    sc[ci++] = 0xA9027BFD; // stp x29, x30, [sp, #16]
    sc[ci++] = 0xA90355F6; // stp x22, x21, [sp, #32]  (note: x22 low, x21 high)
    sc[ci++] = 0xA9044FF4; // stp x20, x19, [sp, #48]  (x20 low, x19 high)
    sc[ci++] = 0x910043FD; // add x29, sp, #16

    // Load path addr into x19
    encode_mov64(sc, &ci, 19, pathAddr);

    // Load data addr into x20
    encode_mov64(sc, &ci, 20, dataAddr);

    // Load size into w21 (lower 32 bits; dylib < 4GB)
    encode_mov64(sc, &ci, 21, dylibSize);

    // open(path, O_CREAT|O_WRONLY|O_TRUNC, 0644)
    sc[ci++] = 0xAA1303E0; // mov x0, x19
    sc[ci++] = 0xD280C021; // movz x1, #0x601
    sc[ci++] = 0xD2803482; // movz x2, #0x1A4
    encode_mov64(sc, &ci, 16, fn_open);
    sc[ci++] = 0xD63F0200; // blr x16
    sc[ci++] = 0xAA0003F6; // mov x22, x0  (save fd)

    // write(fd, data, size)
    sc[ci++] = 0xAA1403E1; // mov x1, x20
    sc[ci++] = 0xAA1503E2; // mov x2, x21 (x0 still = fd)
    encode_mov64(sc, &ci, 16, fn_write);
    sc[ci++] = 0xD63F0200; // blr x16

    // close(fd)
    sc[ci++] = 0xAA1603E0; // mov x0, x22
    encode_mov64(sc, &ci, 16, fn_close);
    sc[ci++] = 0xD63F0200; // blr x16

    // dlopen(path, RTLD_LAZY|RTLD_GLOBAL)
    sc[ci++] = 0xAA1303E0; // mov x0, x19
    sc[ci++] = 0xD2800121; // mov x1, #9
    encode_mov64(sc, &ci, 16, fn_dlopen);
    sc[ci++] = 0xD63F0200; // blr x16

    // cbz x0, skip_cleanup
    sc[ci++] = 0xB4000060; // cbz x0, +12 bytes (skip 3 insns: ldp x2, ldp x2, add)
    // Restore callee-saved regs
    sc[ci++] = 0xA9444FF4; // ldp x20, x19, [sp, #48]
    sc[ci++] = 0xA94355F6; // ldp x22, x21, [sp, #32]
    sc[ci++] = 0xA9427BFD; // ldp x29, x30, [sp, #16]
    sc[ci++] = 0x910103FF; // add sp, sp, #64

    // Thread exit
    sc[ci++] = 0xD2800000; // mov x0, #0
    sc[ci++] = 0xD2800010; // mov x16, #1 (SYS_exit)
    sc[ci++] = 0xD4000801; // svc #0x80

    size_t codeSize = ci * sizeof(uint32_t);
    uint64_t codeAddr = remoteBase + codeOff;
    uint64_t stackAddr = remoteBase + stackOff;

    // Write shellcode
    kr = mach_vm_write(remoteTask, codeAddr, (vm_offset_t)sc,
                       (mach_msg_type_number_t)codeSize);
    if (kr != KERN_SUCCESS) {
        SAFE_LOG(@"Inject: shellcode write failed: %s", mach_error_string(kr));
        goto cleanup;
    }

    // Make code executable
    kr = mach_vm_protect(remoteTask, codeAddr, 0x4000, FALSE,
                         VM_PROT_READ | VM_PROT_EXECUTE);
    if (kr != KERN_SUCCESS) {
        SAFE_LOG(@"Inject: vm_protect failed: %s (continuing anyway)", mach_error_string(kr));
    }

    // Create remote thread
    arm_thread_state64_t state;
    memset(&state, 0, sizeof(state));
    state.__pc = codeAddr;
    state.__sp = stackAddr;
    state.__fp = 0;
    state.__lr = 0;
    state.__cpsr = 0;

    thread_act_t remoteThread = MACH_PORT_NULL;
    kr = thread_create_running(remoteTask, ARM_THREAD_STATE64,
                               (thread_state_t)&state, ARM_THREAD_STATE64_COUNT,
                               &remoteThread);
    if (kr != KERN_SUCCESS) {
        SAFE_LOG(@"Inject: thread_create failed: %s", mach_error_string(kr));
        goto cleanup;
    }

    SAFE_LOG(@">> remote thread RUNNING — shellcode writes %zu-byte dylib to game /tmp/, then dlopen", dylibSize);
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

    // inject_via_mach reads the dylib bytes and writes them into game memory.
    // Shellcode in game writes bytes to game's OWN /tmp/ (iOS sandbox per-app),
    // then dlopens that file. The path "/tmp/DFOverlay.dylib" is relative to
    // the game's sandbox container.
    const char *remotePath = "/tmp/DFOverlay.dylib";

    // Method 1: Try xpf_inject_dylib from libjailbreak (kernel-level, bypasses AMFI)
    typedef int (*xpf_inject_func)(int, const char*);
    xpf_inject_func xpf_inject = (xpf_inject_func)dlsym(RTLD_DEFAULT, "xpf_inject_dylib");
    if (xpf_inject) {
        // Copy dylib to /tmp/ WITHOUT stripping — xpf handles code signing itself
        NSString *tmpPath = @"/tmp/DFOverlay.dylib";
        [[NSFileManager defaultManager] removeItemAtPath:tmpPath error:nil];
        [[NSFileManager defaultManager] copyItemAtPath:fwPath toPath:tmpPath error:nil];
        int ret = xpf_inject(pid, [tmpPath UTF8String]);
        if (ret == 0) {
            SAFE_LOG(@">> xpf_inject_dylib OK");
            return 0;
        }
        SAFE_LOG(@">> xpf_inject_dylib returned %d, trying Mach VM...", ret);
    } else {
        SAFE_LOG(@">> xpf_inject_dylib not available, using Mach VM");
    }

    // Method 2: Mach VM injection — writes dylib bytes into game memory,
    // shellcode writes them to game's sandboxed /tmp/ then dlopen
    kern_return_t kr = inject_via_mach(pid, [fwPath UTF8String], remotePath);
    if (kr == KERN_SUCCESS) {
        SAFE_LOG(@">> Mach VM injection OK — dylib constructor should fire now");
        return 0;
    }

    SAFE_LOG(@">> ALL INJECTION METHODS FAILED (kr=%d: %s)", kr, mach_error_string(kr));
    return -1;
}
