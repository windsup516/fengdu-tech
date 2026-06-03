// NBMain.mm — nb-style in-process cheat dylib
// Framework replacement: dylib loaded by game process via dyld
// No Mach VM / task_for_pid needed — direct memory access
// Card key login (16 chars) → ImGui overlay + hooks

#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#import <mach/mach.h>
#import <stdio.h>
#import <time.h>
#import <stdarg.h>
#import <math.h>

// ImGui
#import "imgui.h"
#import "imgui_impl_metal.h"
#import "NBLoginManager.h"

// ============================================================
// Logging — writes to /tmp/nb_cheat.log in game's sandbox
// ============================================================
static FILE *g_nb_log = NULL;
static void nb_log(const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    NSLog(@"[NB] %@", [[NSString alloc] initWithFormat:[NSString stringWithUTF8String:fmt] arguments:args]);
    va_end(args);
    if (!g_nb_log) g_nb_log = fopen("/tmp/nb_cheat.log", "w");
    if (!g_nb_log) return;
    time_t now = time(NULL);
    struct tm *t = localtime(&now);
    fprintf(g_nb_log, "%02d:%02d:%02d ", t->tm_hour, t->tm_min, t->tm_sec);
    va_list args2;
    va_start(args2, fmt);
    vfprintf(g_nb_log, fmt, args2);
    fprintf(g_nb_log, "\n"); fflush(g_nb_log);
    va_end(args2);
}

// ============================================================
// ARM64 Inline Hook Engine (minimal — avoids Dobby dependency)
// ============================================================
static void arm64_patch_branch(uint64_t srcAddr, uint64_t dstAddr) {
    // Make memory writable
    uint64_t page = srcAddr & ~0xFFF;
    kern_return_t kr = mach_vm_protect(mach_task_self(), page, 0x4000, FALSE,
                                        VM_PROT_READ | VM_PROT_WRITE | VM_PROT_EXECUTE);
    if (kr != KERN_SUCCESS) {
        nb_log("mach_vm_protect FAILED: %s", mach_error_string(kr));
        return;
    }
    // ARM64 unconditional branch: B <offset> / 0x14000000 | (imm26)
    int64_t offset = (int64_t)(dstAddr - srcAddr) >> 2;
    if (offset < -0x2000000 || offset > 0x1FFFFFF) {
        nb_log("branch offset out of range: %lld", offset);
        return;
    }
    uint32_t instr = 0x14000000 | (offset & 0x03FFFFFF);
    *(uint32_t *)srcAddr = instr;
    __asm volatile("dsb ish; isb");
    nb_log("patched 0x%llx -> 0x%llx (B 0x%llx)", srcAddr, dstAddr, offset);
}

// ============================================================
// In-Process Memory Scanner (Cosmk-style: direct pointer access)
// ============================================================
static uint64_t g_game_base = 0;

// Find main executable base address (we're INSIDE the game process)
static uint64_t find_game_base(void) {
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (!name) continue;
        // Look for game binary (not system dylibs)
        if (strstr(name, "DeltaForce") || strstr(name, "deltaforce") ||
            strstr(name, "DFM") || strstr(name, "dfm")) {
            const struct mach_header_64 *hdr =
                (const struct mach_header_64 *)_dyld_get_image_header(i);
            uint64_t base = (uint64_t)hdr;
            intptr_t slide = _dyld_get_image_vmaddr_slide(i);
            nb_log("game module: %s base=0x%llx slide=0x%lx", name, base, slide);
            g_game_base = base;
            return base;
        }
    }
    // Fallback: use first non-system image
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (!name) continue;
        if (name[0] != '/' || strstr(name, "/System/") || strstr(name, "/usr/")) continue;
        const struct mach_header_64 *hdr =
            (const struct mach_header_64 *)_dyld_get_image_header(i);
        nb_log("fallback module: %s base=0x%llx", name, (uint64_t)hdr);
        g_game_base = (uint64_t)hdr;
        return g_game_base;
    }
    return 0;
}

// Scan for byte pattern in memory (direct pointer dereference — no mach_vm_read)
static uint64_t scan_pattern_direct(uint64_t start, size_t len, const uint8_t *pat, const char *mask) {
    size_t maskLen = strlen(mask);
    for (uint64_t addr = start; addr < start + len - maskLen; addr++) {
        bool match = true;
        for (size_t i = 0; i < maskLen; i++) {
            if (mask[i] == 'x' && *(uint8_t *)(addr + i) != pat[i]) {
                match = false;
                break;
            }
        }
        if (match) return addr;
    }
    return 0;
}

// ============================================================
// Game Offsets & State
// ============================================================
typedef struct {
    uint64_t base;
    uint64_t gworld;
    uint64_t uworld;       // UE4 World
    uint64_t gameInstance;
    uint64_t localPlayer;
    uint64_t playerController;
    uint64_t acknowledgedPawn;
    uint64_t weaponManager;
    uint64_t cameraManager;
    uint64_t actorArray;
    int32_t  actorCount;
    float    viewMatrix[16];
    bool     offsets_ready;
} NBGameState;

static NBGameState g_state = {0};

// Scan UE4 GWorld via known patterns
static uint64_t find_gworld(void) {
    if (!g_game_base) return 0;
    // UE4 GWorld is typically at a fixed offset from a known reference
    // Pattern: ADRP + LDR (accessing GWorld global)
    // In practice, scan for this in .text
    return 0; // Placeholder — needs game-specific offsets
}

// ============================================================
// Cheat Features (in-process, direct memory)
// ============================================================
static bool g_no_recoil = true;
static bool g_no_spread = true;
static bool g_esp_enabled = true;
static bool g_aimbot_enabled = false;

// Apply no-recoil by writing to weapon recoil values
static void apply_no_recoil(void) {
    if (!g_state.weaponManager || !g_no_recoil) return;
    // Weapon recoil multipliers in UE4 are floats at known offsets
    // Example: *(float *)(weaponMgr + 0x2C0) = 0.0f; etc.
}

// Apply no-spread by zeroing bullet spread
static void apply_no_spread(void) {
    if (!g_state.weaponManager || !g_no_spread) return;
}

// ============================================================
// ImGui Login Window
// ============================================================
static char g_card_key_buf[17] = {0};
static bool g_login_done = false;
static char g_error_msg[256] = {0};

static void RenderLoginWindow(void) {
    if (g_login_done && [[NBLoginManager shared] isActivated]) return;

    ImGui::SetNextWindowPos(ImVec2(100, 100), ImGuiCond_FirstUseEver);
    ImGui::SetNextWindowSize(ImVec2(380, 220), ImGuiCond_FirstUseEver);
    ImGui::Begin("NB Cheat — Login", NULL,
                 ImGuiWindowFlags_NoResize | ImGuiWindowFlags_NoCollapse);

    ImGui::Text("Input 16-char Card Key:");
    ImGui::Separator();
    ImGui::SetNextItemWidth(-1);
    bool enter_pressed = ImGui::InputText("##cardkey", g_card_key_buf, 17,
                                           ImGuiInputTextFlags_EnterReturnsTrue |
                                           ImGuiInputTextFlags_CharsNoBlank);
    if (enter_pressed || ImGui::Button("Activate", ImVec2(-1, 35))) {
        NSString *key = [NSString stringWithUTF8String:g_card_key_buf];
        if (key.length != 16) {
            snprintf(g_error_msg, sizeof(g_error_msg),
                     "Key must be exactly 16 characters (got %lu)", (unsigned long)key.length);
        } else if ([[NBLoginManager shared] verifyKey:key]) {
            g_login_done = true;
            nb_log("Card key activated: %.16s", g_card_key_buf);
        } else {
            snprintf(g_error_msg, sizeof(g_error_msg), "Activation failed");
        }
    }
    if (g_error_msg[0]) {
        ImGui::TextColored(ImVec4(1, 0.3f, 0.3f, 1), "%s", g_error_msg);
    }
    ImGui::TextColored(ImVec4(0.5f, 0.5f, 0.5f, 1),
                       "Any 16 characters accepted | Press Enter or click");

    ImGui::End();
}

// ============================================================
// ImGui Cheat Overlay
// ============================================================
static bool g_show_menu = true;
static int g_frame_count = 0;

static void RenderCheatOverlay(int screenW, int screenH) {
    g_frame_count++;

    // Minimap: small status in corner
    ImGui::SetNextWindowPos(ImVec2(screenW - 130, 10), ImGuiCond_Always);
    ImGui::SetNextWindowSize(ImVec2(120, 25), ImGuiCond_Always);
    ImGui::Begin("##minibar", NULL,
                 ImGuiWindowFlags_NoTitleBar | ImGuiWindowFlags_NoResize |
                 ImGuiWindowFlags_NoMove | ImGuiWindowFlags_NoScrollbar);
    ImGui::TextColored(ImVec4(0.3f, 0.9f, 0.4f, 1), "NB v1.0 ON");
    ImGui::End();

    // Main menu
    if (g_show_menu) {
        ImGui::SetNextWindowPos(ImVec2(20, 60), ImGuiCond_FirstUseEver);
        ImGui::SetNextWindowSize(ImVec2(300, 400), ImGuiCond_FirstUseEver);
        ImGui::Begin("NB Cheat v1.0", &g_show_menu);

        if (ImGui::BeginTabBar("##tabs")) {

            if (ImGui::BeginTabItem("Aim")) {
                ImGui::Checkbox("Aimbot", &g_aimbot_enabled);
                ImGui::SliderFloat("FOV", (float[]){1, 30}, NULL, 5);
                ImGui::SliderFloat("Smooth", (float[]){0, 1}, NULL, 0.85f);
                ImGui::EndTabItem();
            }

            if (ImGui::BeginTabItem("Visuals")) {
                ImGui::Checkbox("ESP", &g_esp_enabled);
                ImGui::Checkbox("Box", (bool[]){true}, NULL);
                ImGui::Checkbox("Health Bar", (bool[]){true}, NULL);
                ImGui::Checkbox("Distance", (bool[]){true}, NULL);
                ImGui::Checkbox("Skeleton", (bool[]){false}, NULL);
                ImGui::SliderFloat("Max Distance", (float[]){0, 500}, NULL, 300);
                ImGui::EndTabItem();
            }

            if (ImGui::BeginTabItem("Weapon")) {
                ImGui::Checkbox("No Recoil", &g_no_recoil);
                ImGui::Checkbox("No Spread", &g_no_spread);
                ImGui::EndTabItem();
            }

            if (ImGui::BeginTabItem("Info")) {
                ImGui::Text("Frame: %d", g_frame_count);
                ImGui::Text("Game Base: 0x%llx", g_game_base);
                ImGui::Text("GWorld: 0x%llx", g_state.gworld);
                ImGui::Text("Card: %.16s", g_card_key_buf);
                ImGui::Separator();
                ImGui::Text("Module count: %d", _dyld_image_count());
                ImGui::EndTabItem();
            }

            ImGui::EndTabBar();
        }
        ImGui::End();
    }
}

// ============================================================
// Metal Renderer — drives ImGui in-process via CADisplayLink
// ============================================================
@interface NBMetalRenderer : NSObject {
    CADisplayLink *_displayLink;
    UIWindow *_overlayWindow;
    MTKView *_metalView;
    id<MTLDevice> _device;
    id<MTLCommandQueue> _cmdQueue;
    int _screenW, _screenH;
}
+ (instancetype)shared;
- (void)start;
- (void)stop;
@end

@implementation NBMetalRenderer

+ (instancetype)shared {
    static NBMetalRenderer *inst = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ inst = [[NBMetalRenderer alloc] init]; });
    return inst;
}

- (void)start {
    nb_log("NBMetalRenderer starting...");
    dispatch_async(dispatch_get_main_queue(), ^{
        [self _setupOnMainThread];
    });
}

- (void)_setupOnMainThread {
    CGSize sz = [UIScreen mainScreen].bounds.size;
    CGFloat scale = [UIScreen mainScreen].scale;
    _screenW = (int)sz.width;
    _screenH = (int)sz.height;

    _device = MTLCreateSystemDefaultDevice();
    if (!_device) { nb_log("FATAL: no Metal device"); return; }
    _cmdQueue = [_device newCommandQueue];

    // Create overlay window
    _overlayWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    _overlayWindow.windowLevel = UIWindowLevelAlert + 100;
    _overlayWindow.backgroundColor = [UIColor clearColor];
    _overlayWindow.userInteractionEnabled = YES;
    _overlayWindow.rootViewController = [[UIViewController alloc] init];
    _overlayWindow.hidden = NO;

    // Metal view
    _metalView = [[MTKView alloc] initWithFrame:_overlayWindow.bounds device:_device];
    _metalView.clearColor = MTLClearColorMake(0, 0, 0, 0);
    _metalView.backgroundColor = [UIColor clearColor];
    _metalView.opaque = NO;
    _metalView.paused = NO;
    _metalView.enableSetNeedsDisplay = NO;
    _metalView.delegate = (id<MTKViewDelegate>)self;
    [_overlayWindow.rootViewController.view addSubview:_metalView];

    // Init ImGui
    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGuiIO &io = ImGui::GetIO();
    io.DisplaySize = ImVec2(_screenW, _screenH);
    io.IniFilename = NULL;
    io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;

    ImGui::StyleColorsDark();
    ImGui_ImplMetal_Init(_device);

    nb_log("ImGui initialized, Metal view ready (%.0fx%.0f @%.0f)", sz.width, sz.height, scale);
}

- (void)drawInMTKView:(MTKView *)view {
    if (!g_login_done || ![[NBLoginManager shared] isActivated]) {
        // Still in login phase — render login window
    }

    id<MTLCommandBuffer> cmdBuf = [_cmdQueue commandBuffer];
    MTLRenderPassDescriptor *rpd = view.currentRenderPassDescriptor;
    if (!rpd || !cmdBuf) return;

    ImGui_ImplMetal_NewFrame(rpd);
    ImGui::NewFrame();

    if (g_login_done && [[NBLoginManager shared] isActivated]) {
        RenderCheatOverlay(_screenW, _screenH);
    } else {
        RenderLoginWindow();
    }

    // Apply cheats every frame when activated
    if (g_login_done && [[NBLoginManager shared] isActivated]) {
        apply_no_recoil();
        apply_no_spread();
    }

    ImGui::Render();
    id<MTLRenderCommandEncoder> enc = [cmdBuf renderCommandEncoderWithDescriptor:rpd];
    ImGui_ImplMetal_RenderDrawData(ImGui::GetDrawData(), cmdBuf, enc);
    [enc endEncoding];
    [cmdBuf presentDrawable:view.currentDrawable];
    [cmdBuf commit];
}

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {
    _screenW = (int)size.width;
    _screenH = (int)size.height;
}

- (void)stop {
    _overlayWindow.hidden = YES;
    _overlayWindow = nil;
    ImGui_ImplMetal_Shutdown();
    ImGui::DestroyContext();
}

@end

// ============================================================
// Dylib Constructor — entry point when game loads this dylib
// ============================================================
__attribute__((constructor))
static void NB_Init(void) {
    nb_log("=== NB Cheat dylib loaded into PID %d ===", getpid());

    // Step 1: Find game base address (we're in-process!)
    find_game_base();
    nb_log("Game base: 0x%llx", g_game_base);

    // Step 2: Check if already activated (persistent)
    [[NBLoginManager shared] loadSavedState];
    if ([[NBLoginManager shared] isActivated]) {
        g_login_done = true;
        const char *key = [[[NBLoginManager shared] currentKey] UTF8String];
        snprintf(g_card_key_buf, 17, "%.16s", key ? key : "");
        nb_log("Restored saved activation: %.16s", g_card_key_buf);
    }

    // Step 3: Start Metal overlay (shows login or cheat menu)
    [[NBMetalRenderer shared] start];

    nb_log("NB_Init complete — PID=%d base=0x%llx activated=%d",
           getpid(), g_game_base, g_login_done);
}

__attribute__((destructor))
static void NB_Cleanup(void) {
    [[NBMetalRenderer shared] stop];
    nb_log("=== NB Cheat dylib unloaded ===");
    if (g_nb_log) { fclose(g_nb_log); g_nb_log = NULL; }
}
