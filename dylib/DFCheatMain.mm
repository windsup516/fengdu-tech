// DFCheatMain.mm — Self-contained in-process cheat dylib
// Metal+ImGui overlay + ESP + Aimbot + Memory scanning
// Runs INSIDE game process via dlopen injection
// NO Mach VM needed — direct pointer dereference

#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#import <mach-o/loader.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#import <string.h>
#import <math.h>
#import <stdio.h>
#import <time.h>
#import <stdarg.h>

#import "imgui.h"
#import "imgui_impl_metal.h"
#import "DFGameData.h"
#import "EncryptedStrings.h"

// === Globals ===
DFScannedOffsets g_df_offsets = {0};
DFCheatConfig g_df_config = {
    .esp_enabled = true,
    .esp_box = true,
    .esp_health_bar = true,
    .esp_distance = true,
    .esp_name = true,
    .esp_skeleton = false,
    .esp_head_dot = true,
    .esp_line = false,
    .esp_visible_only = false,
    .esp_show_ai = false,
    .esp_show_team = false,
    .esp_max_distance = 300.0f,
    .aimbot_enabled = false,
    .aimbot_auto_fire = false,
    .aimbot_visibility_check = true,
    .aimbot_ignore_down = true,
    .aimbot_target_bone = 0, // BONE_HEAD
    .aimbot_fov = 5.0f,
    .aimbot_smooth = 0.85f,
    .aimbot_max_distance = 200.0f,
    .no_recoil = true,
    .no_spread = true,
    .enemy_color = {1.0f, 0.0f, 0.0f, 1.0f},
    .enemy_visible_color = {1.0f, 0.78f, 0.0f, 1.0f},
    .team_color = {0.0f, 1.0f, 0.0f, 1.0f},
    .ai_color = {0.5f, 0.5f, 1.0f, 1.0f},
    .box_thickness = 2.0f,
};

static FILE *g_log = NULL;
void df_log(const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    NSLog(@"%@ %@", DecryptString(ES_DFCheat), [[NSString alloc] initWithFormat:[NSString stringWithUTF8String:fmt] arguments:args]);
    va_end(args);
    if (!g_log) g_log = fopen(DecryptCString(ES__tmp_dfcheat_log), "w");
    if (!g_log) return;
    time_t now = time(NULL);
    struct tm *t = localtime(&now);
    fprintf(g_log, "%02d:%02d:%02d ", t->tm_hour, t->tm_min, t->tm_sec);
    va_list args2;
    va_start(args2, fmt);
    vfprintf(g_log, fmt, args2);
    fprintf(g_log, "\n");
    fflush(g_log);
    va_end(args2);
}

// === Forward Declarations ===
@interface DFCheatController : NSObject
+ (instancetype)shared;
- (void)startOverlay;
- (void)stopOverlay;
@end

// === Memory Scanner (in-process) ===
static uint64_t find_game_base(void) {
    const struct mach_header_64 *hdr = NULL;
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        hdr = (const struct mach_header_64 *)_dyld_get_image_header(i);
        if (hdr && hdr->filetype == MH_EXECUTE) {
            return (uint64_t)hdr;
        }
    }
    return 0;
}

static bool parse_segments(uint64_t base,
                           uint64_t *text_start, uint64_t *text_end,
                           uint64_t *data_start, uint64_t *data_end,
                           uint64_t *const_start, uint64_t *const_end) {
    struct mach_header_64 *hdr = (struct mach_header_64 *)base;
    if (hdr->magic != MH_MAGIC_64) return false;

    uint8_t *cursor = (uint8_t *)(base + sizeof(struct mach_header_64));
    for (uint32_t i = 0; i < hdr->ncmds; i++) {
        struct load_command *lc = (struct load_command *)cursor;
        if (lc->cmd == LC_SEGMENT_64) {
            struct segment_command_64 *seg = (struct segment_command_64 *)cursor;
            int64_t slide = (int64_t)(base - seg->vmaddr);
            uint64_t start = seg->vmaddr + slide;
            uint64_t end = start + seg->vmsize;

            if (strcmp(seg->segname, "__TEXT") == 0) {
                *text_start = start; *text_end = end;
            } else if (strcmp(seg->segname, "__DATA") == 0) {
                *data_start = start; *data_end = end;
            } else if (strcmp(seg->segname, "__DATA_CONST") == 0 ||
                       strcmp(seg->segname, "__AUTH_CONST") == 0) {
                *const_start = start; *const_end = end;
            }
        }
        cursor += lc->cmdsize;
    }
    return *text_start > 0;
}

static bool is_heap_ptr(uint64_t addr) {
    return addr > 0x100000000 && addr < 0x400000000 && (addr & 0x7) == 0;
}

static uint64_t scan_gworld_inprocess(uint64_t base,
                                       uint64_t data_start, uint64_t data_end,
                                       uint64_t text_start, uint64_t text_end,
                                       uint64_t const_start, uint64_t const_end) {
    df_log(DecryptCString(ES_scan_gworld__DATA_),
           data_start, data_end, (data_end - data_start) / 1048576.0);

    uint64_t best_addr = 0;
    int best_score = 0;

    for (uint64_t addr = data_start; addr + 8 <= data_end; addr += 8) {
        uint64_t candidate = *(uint64_t *)addr;
        if (!is_heap_ptr(candidate)) continue;

        // Read vtable
        uint64_t vtable = *(uint64_t *)candidate;
        bool valid_vtable = false;
        if ((vtable >= text_start && vtable < text_end) ||
            (vtable >= const_start && vtable < const_end)) {
            valid_vtable = true;
        }
        if (!valid_vtable) continue;

        // PersistentLevel at +0x30
        uint64_t plevel = *(uint64_t *)(candidate + OFFSET_UWORLD_PERSISTENTLEVEL);
        if (!is_heap_ptr(plevel)) continue;

        // Actors TArray at +0x98
        uint64_t actors_ptr = *(uint64_t *)(plevel + OFFSET_ULEVEL_ACTORS + TARRAY_OFFSET_DATA);
        int32_t actors_count = *(int32_t *)(plevel + OFFSET_ULEVEL_ACTORS + TARRAY_OFFSET_COUNT);
        if (!is_heap_ptr(actors_ptr)) continue;
        if (actors_count < 1 || actors_count > 5000) continue;

        int score = actors_count;
        if (score > best_score) {
            best_score = score;
            best_addr = addr;
        }
        if (actors_count > 50) break; // Good enough
    }

    if (best_addr) {
        df_log(DecryptCString(ES_GWorld_found),
               best_addr, *(uint64_t *)best_addr, best_score);
    }
    return best_addr;
}

static uint64_t scan_gname_inprocess(uint64_t data_start, uint64_t data_end,
                                      uint64_t text_start, uint64_t text_end,
                                      uint64_t const_start, uint64_t const_end) {
    for (uint64_t addr = data_start; addr + 8 <= data_end; addr += 8) {
        uint64_t candidate = *(uint64_t *)addr;
        if (!is_heap_ptr(candidate)) continue;

        // Read potential chunk pointers
        uint64_t cptrs[8];
        memcpy(cptrs, (void *)candidate, sizeof(cptrs));

        int valid = 0;
        for (int j = 0; j < 8; j++) {
            if (!cptrs[j] || !is_heap_ptr(cptrs[j])) break;
            // Check first entry header
            uint16_t hdr = *(uint16_t *)cptrs[j];
            uint16_t nlen = hdr >> 6;
            if (nlen < 1 || nlen > 128) break;
            valid++;
        }
        if (valid >= 3) {
            df_log(DecryptCString(ES_GName_found), addr, valid);
            return addr;
        }
    }
    return 0;
}

static int scan_all_inprocess(void) {
    uint64_t base = find_game_base();
    if (!base) { df_log(DecryptCString(ES_FATAL__game_base_not_found)); return -1; }
    g_df_offsets.game_base = base;
    df_log(DecryptCString(ES_Game_base_), base);

    uint64_t text_start = 0, text_end = 0;
    uint64_t data_start = 0, data_end = 0;
    uint64_t const_start = 0, const_end = 0;

    if (!parse_segments(base, &text_start, &text_end,
                         &data_start, &data_end,
                         &const_start, &const_end)) {
        df_log(DecryptCString(ES_FATAL__segment_parse_failed));
        return -1;
    }

    uint64_t gworld_addr = scan_gworld_inprocess(base, data_start, data_end,
                                                   text_start, text_end,
                                                   const_start, const_end);
    if (gworld_addr) {
        g_df_offsets.gworld_ptr = gworld_addr;
        g_df_offsets.gworld_found = true;
    }

    uint64_t gname_addr = scan_gname_inprocess(data_start, data_end,
                                                text_start, text_end,
                                                const_start, const_end);
    if (gname_addr) {
        g_df_offsets.gname_base = *(uint64_t *)gname_addr;
        g_df_offsets.gname_found = true;
    }

    g_df_offsets.scanned = true;
    df_log(DecryptCString(ES_Scan_done),
           g_df_offsets.gworld_found, g_df_offsets.gname_found);
    return g_df_offsets.gworld_found ? 0 : -2;
}

// === Entity Reader (in-process, direct pointer dereference) ===
static DFEntityData g_entities[DF_MAX_ENTITIES];
static int g_entity_count = 0;
static int g_local_team = 0;

// 4x4 matrix multiply
static void mat4_mul_vec4_df(const float m[16], const float v[4], float out[4]) {
    out[0] = m[0]*v[0] + m[4]*v[1] + m[8]*v[2]  + m[12]*v[3];
    out[1] = m[1]*v[0] + m[5]*v[1] + m[9]*v[2]  + m[13]*v[3];
    out[2] = m[2]*v[0] + m[6]*v[1] + m[10]*v[2] + m[14]*v[3];
    out[3] = m[3]*v[0] + m[7]*v[1] + m[11]*v[2] + m[15]*v[3];
}

static bool world_to_screen_df(const float world[3], const float vp[16],
                                float sw, float sh, float out[3]) {
    float clip[4], wpos[4] = {world[0], world[1], world[2], 1.0f};
    mat4_mul_vec4_df(vp, wpos, clip);
    if (clip[3] < 0.001f) return false;
    out[0] = (clip[0] / clip[3] + 1.0f) * 0.5f * sw;
    out[1] = (1.0f - clip[1] / clip[3]) * 0.5f * sh;
    out[2] = clip[3];
    return (out[0] >= 0 && out[0] <= sw && out[1] >= 0 && out[1] <= sh);
}

// Read view-projection matrix from camera
static bool read_camera_matrix(float vp[16]) {
    if (!g_df_offsets.gworld_found) return false;

    uint64_t gworld = *(uint64_t *)g_df_offsets.gworld_ptr;
    if (!is_heap_ptr(gworld)) return false;

    // UWorld -> OwningGameInstance (+0x190) -> LocalPlayers (+0x38) -> [0] -> PlayerController (+0x30)
    // -> CameraManager (+0x330) -> CameraCache (+0x2C0)
    // Simplified: walk the chain using common UE4 offsets
    uint64_t gameInstance = *(uint64_t *)(gworld + 0x190);
    if (!is_heap_ptr(gameInstance)) return false;

    uint64_t localPlayers = *(uint64_t *)(gameInstance + 0x38);
    if (!is_heap_ptr(localPlayers)) return false;

    uint64_t localPlayer = *(uint64_t *)localPlayers;
    if (!is_heap_ptr(localPlayer)) return false;

    uint64_t playerController = *(uint64_t *)(localPlayer + 0x30);
    if (!is_heap_ptr(playerController)) return false;

    uint64_t cameraMgr = *(uint64_t *)(playerController + OFFSET_PLAYER_CAMERA_MANAGER);
    if (!is_heap_ptr(cameraMgr)) return false;

    // CameraCacheEntry at +0x2C0: FMinimalViewInfo (16 floats)
    float *camData = (float *)(cameraMgr + 0x2C0);
    // Location (3 floats) + Rotation (3 floats) + FOV + PerspectiveNear + 16 floats viewproj
    // ViewProjectionMatrix is typically at offset 0x1D0 in CameraManager or derived
    // For UE4.27+ : CameraManager + 0x1D0 has the VP matrix

    float *matrixSource = (float *)(cameraMgr + 0x1D0);
    memcpy(vp, matrixSource, 16 * sizeof(float));
    return true;
}

static void read_entities(void) {
    g_entity_count = 0;
    g_local_team = 0;
    if (!g_df_offsets.gworld_found) return;

    uint64_t gworld = *(uint64_t *)g_df_offsets.gworld_ptr;
    if (!is_heap_ptr(gworld)) return;

    // Get local player team
    uint64_t gameInstance = *(uint64_t *)(gworld + 0x190);
    if (is_heap_ptr(gameInstance)) {
        uint64_t lpArr = *(uint64_t *)(gameInstance + 0x38);
        if (is_heap_ptr(lpArr)) {
            uint64_t lp = *(uint64_t *)lpArr;
            if (is_heap_ptr(lp)) {
                uint64_t pc = *(uint64_t *)(lp + 0x30);
                if (is_heap_ptr(pc)) {
                    uint64_t pawn = *(uint64_t *)(pc + 0x300);
                    if (is_heap_ptr(pawn)) {
                        g_local_team = *(int *)(pawn + OFFSET_AACTOR_TEAM_ID);
                    }
                }
            }
        }
    }

    // Read persistent level -> actors
    uint64_t plevel = *(uint64_t *)(gworld + OFFSET_UWORLD_PERSISTENTLEVEL);
    if (!is_heap_ptr(plevel)) return;

    uint64_t actorsPtr = *(uint64_t *)(plevel + OFFSET_ULEVEL_ACTORS + TARRAY_OFFSET_DATA);
    int32_t actorsCount = *(int32_t *)(plevel + OFFSET_ULEVEL_ACTORS + TARRAY_OFFSET_COUNT);
    if (!is_heap_ptr(actorsPtr) || actorsCount <= 0 || actorsCount > 5000) return;

    int count = 0;
    for (int i = 0; i < actorsCount && count < DF_MAX_ENTITIES; i++) {
        uint64_t actor = *(uint64_t *)(actorsPtr + i * 8);
        if (!is_heap_ptr(actor)) continue;

        // Skip local player
        uint64_t pc = *(uint64_t *)(gworld + 0x190); // game instance
        if (is_heap_ptr(pc)) {
            uint64_t lpArr = *(uint64_t *)(pc + 0x38);
            if (is_heap_ptr(lpArr)) {
                uint64_t lp = *(uint64_t *)lpArr;
                if (is_heap_ptr(lp)) {
                    uint64_t lpc = *(uint64_t *)(lp + 0x30);
                    if (is_heap_ptr(lpc)) {
                        uint64_t lpawn = *(uint64_t *)(lpc + 0x300);
                        if (actor == lpawn) continue;
                    }
                }
            }
        }

        // Health check
        float hp = *(float *)(actor + OFFSET_AACTOR_HEALTH);
        if (hp <= 0 || hp > 1000) continue;

        int team = *(int *)(actor + OFFSET_AACTOR_TEAM_ID);

        DFEntityData *ent = &g_entities[count];
        memset(ent, 0, sizeof(DFEntityData));
        ent->actor_ptr = actor;
        ent->health = hp;
        ent->max_health = *(float *)(actor + OFFSET_AACTOR_MAX_HEALTH);
        ent->team = team;

        // Read position from RootComponent
        uint64_t rootComp = *(uint64_t *)(actor + OFFSET_AACTOR_ROOTCOMPONENT);
        if (is_heap_ptr(rootComp)) {
            double *trans = (double *)(rootComp + OFFSET_USCENECOMPONENT_TRANSLATION);
            ent->position[0] = (float)trans[0];
            ent->position[1] = (float)trans[1];
            ent->position[2] = (float)trans[2];
        }

        // Visibility check
        uint8_t poseState = *(uint8_t *)(actor + OFFSET_AACTOR_POSE_STATE);
        ent->is_down = (poseState == 3); // Pose state 3 = downed
        ent->is_ai = false; // TODO: detect AI

        if (g_df_config.esp_show_team || team != g_local_team) {
            ent->is_valid = true;
        }
        if (g_df_config.esp_visible_only && !ent->visible) {
            ent->is_valid = false;
        }
        if (g_local_team && !g_df_config.esp_show_team && team == g_local_team) {
            ent->is_valid = false;
        }

        count++;
    }
    g_entity_count = count;
}

// === Aimbot ===
static uint64_t g_best_target = 0;
static float g_best_target_pos[3] = {0};

static void find_best_target(float sw, float sh, float vp[16]) {
    g_best_target = 0;
    if (!g_df_config.aimbot_enabled) return;
    if (!g_df_offsets.gworld_found) return;

    float best_dist = g_df_config.aimbot_fov > 0 ? g_df_config.aimbot_fov * 100.0f : 9999.0f;
    float cx = sw / 2, cy = sh / 2;

    for (int i = 0; i < g_entity_count; i++) {
        DFEntityData *ent = &g_entities[i];
        if (!ent->is_valid) continue;
        if (g_df_config.aimbot_ignore_down && ent->is_down) continue;
        if (ent->team == g_local_team && g_local_team) continue;

        // Use head position (approximate: position + (0, 0, 180) in UE units)
        float head[3] = {ent->position[0], ent->position[1], ent->position[2] + 180.0f};

        float screen[3];
        if (!world_to_screen_df(head, vp, sw, sh, screen)) continue;

        float dx = screen[0] - cx, dy = screen[1] - cy;
        float dist = sqrtf(dx*dx + dy*dy);

        if (dist < best_dist) {
            best_dist = dist;
            g_best_target = ent->actor_ptr;
            g_best_target_pos[0] = head[0];
            g_best_target_pos[1] = head[1];
            g_best_target_pos[2] = head[2];
        }
    }
}

// === Overlay Controller ===
@interface DFCheatController ()
@property (nonatomic) UIWindow *overlayWindow;
@property (nonatomic) CAMetalLayer *metalLayer;
@property (nonatomic) id<MTLCommandQueue> cmdQueue;
@property (nonatomic) CADisplayLink *displayLink;
@property (nonatomic) float screenW, screenH;
@property (nonatomic) int frameCount;
@property (nonatomic) BOOL initialized;
@property (nonatomic) BOOL menuOpen;
@property (nonatomic) int selectedTab;
@property (nonatomic) double lastEntityUpdate;
@end

@implementation DFCheatController

+ (instancetype)shared {
    static DFCheatController *inst = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ inst = [[DFCheatController alloc] init]; });
    return inst;
}

- (instancetype)init {
    self = [super init];
    if (self) { _menuOpen = YES; _selectedTab = 0; }
    return self;
}

- (void)startOverlay {
    if (self.initialized) return;
    if (![NSThread isMainThread]) {
        CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopCommonModes, ^{
            [self startOverlay];
        });
        CFRunLoopWakeUp(CFRunLoopGetMain());
        return;
    }

    df_log(DecryptCString(ES_DFCheat_starting), getpid(), getprogname());

    // Scan game offsets (in-process, direct memory access)
    scan_all_inprocess();

    UIScreen *screen = [UIScreen mainScreen];
    CGRect bounds = screen.bounds;
    self.screenW = bounds.size.width;
    self.screenH = bounds.size.height;
    CGFloat scale = screen.scale;

    if (!ImGui::GetCurrentContext()) {
        ImGui::CreateContext();
        ImGui::GetIO().IniFilename = NULL;
        ImGui::GetIO().DisplaySize = ImVec2(self.screenW, self.screenH);
    }

    // Style
    ImGuiStyle &style = ImGui::GetStyle();
    style.Colors[ImGuiCol_WindowBg]      = ImVec4(0.06f, 0.06f, 0.12f, 0.94f);
    style.Colors[ImGuiCol_TitleBg]       = ImVec4(0.10f, 0.10f, 0.20f, 1.0f);
    style.Colors[ImGuiCol_TitleBgActive] = ImVec4(0.15f, 0.15f, 0.30f, 1.0f);
    style.Colors[ImGuiCol_Button]        = ImVec4(0.20f, 0.35f, 0.60f, 0.60f);
    style.Colors[ImGuiCol_ButtonHovered] = ImVec4(0.25f, 0.45f, 0.80f, 0.80f);
    style.Colors[ImGuiCol_CheckMark]     = ImVec4(0.38f, 0.65f, 0.98f, 1.0f);
    style.Colors[ImGuiCol_FrameBg]       = ImVec4(0.12f, 0.15f, 0.25f, 0.54f);
    style.Colors[ImGuiCol_Text]          = ImVec4(0.90f, 0.90f, 0.95f, 1.0f);
    style.Colors[ImGuiCol_SliderGrab]    = ImVec4(0.38f, 0.65f, 0.98f, 1.0f);
    style.WindowRounding = 12.0f;
    style.FrameRounding = 8.0f;

    // Metal setup
    self.metalLayer = [CAMetalLayer layer];
    self.metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    self.metalLayer.framebufferOnly = NO;
    self.metalLayer.opaque = NO;
    self.metalLayer.maximumDrawableCount = 2;
    self.metalLayer.frame = bounds;
    self.metalLayer.drawableSize = CGSizeMake(self.screenW * scale, self.screenH * scale);

    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (!device) { df_log(DecryptCString(ES_FATAL__no_Metal_device)); return; }
    self.metalLayer.device = device;
    self.cmdQueue = [device newCommandQueue];

    ImGui_ImplMetal_Init(device);
    ImGui_ImplMetal_CreateDeviceObjects(device);

    // Window setup - overlay on top of game
    UIViewController *rootVC = [[UIViewController alloc] init];
    rootVC.view = [[UIView alloc] initWithFrame:bounds];
    rootVC.view.backgroundColor = [UIColor clearColor];
    rootVC.view.userInteractionEnabled = NO;
    [rootVC.view.layer addSublayer:self.metalLayer];

    self.overlayWindow = [[UIWindow alloc] initWithFrame:bounds];
    self.overlayWindow.backgroundColor = [UIColor clearColor];
    self.overlayWindow.windowLevel = UIWindowLevelStatusBar + 200;
    self.overlayWindow.rootViewController = rootVC;
    self.overlayWindow.hidden = NO;
    self.overlayWindow.userInteractionEnabled = NO;

    self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(renderFrame:)];
    if (@available(iOS 15.0, *))
        self.displayLink.preferredFrameRateRange = CAFrameRateRangeMake(60, 60, 60);
    else
        self.displayLink.preferredFramesPerSecond = 60;
    [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];

    self.initialized = YES;
    df_log(DecryptCString(ES_DFCheat_overlay_started), self.screenW, self.screenH);
}

- (void)stopOverlay {
    [self.displayLink invalidate];
    self.displayLink = nil;
    self.overlayWindow.hidden = YES;
    self.overlayWindow = nil;
    self.initialized = NO;
    df_log(DecryptCString(ES_DFCheat_stopped));
}

- (void)renderFrame:(CADisplayLink *)link {
    if (!self.initialized) return;
    self.frameCount++;

    @try {
    id<CAMetalDrawable> drawable = [self.metalLayer nextDrawable];
    if (!drawable) return;

    id<MTLCommandBuffer> cmdBuf = [self.cmdQueue commandBuffer];
    if (!cmdBuf) return;

    MTLRenderPassDescriptor *rpd = [MTLRenderPassDescriptor renderPassDescriptor];
    rpd.colorAttachments[0].texture = drawable.texture;
    rpd.colorAttachments[0].loadAction = MTLLoadActionClear;
    rpd.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0);
    rpd.colorAttachments[0].storeAction = MTLStoreActionStore;

    ImGui_ImplMetal_NewFrame(rpd);
    ImGui::NewFrame();

    // Update entities every 100ms
    double now = CACurrentMediaTime();
    if (now - self.lastEntityUpdate > 0.1) {
        read_entities();
        self.lastEntityUpdate = now;
    }

    // Read camera matrix
    float vp[16] = {0};
    bool hasMatrix = read_camera_matrix(vp);

    // Find aimbot target
    if (hasMatrix) {
        find_best_target(self.screenW, self.screenH, vp);
    }

    // === ESP Rendering ===
    if (g_df_config.esp_enabled && hasMatrix) {
        [self renderESP:vp];
    }

    // === ImGui Menu ===
    if (self.menuOpen) {
        [self renderCheatMenu:vp];
    } else {
        ImGui::SetNextWindowPos(ImVec2(self.screenW - 130, 10), ImGuiCond_Always);
        ImGui::SetNextWindowSize(ImVec2(120, 25), ImGuiCond_Always);
        ImGui::Begin("##minibar", NULL,
                     ImGuiWindowFlags_NoTitleBar | ImGuiWindowFlags_NoResize |
                     ImGuiWindowFlags_NoMove | ImGuiWindowFlags_NoScrollbar);
        ImGui::TextColored(ImVec4(0.2f, 0.8f, 0.4f, 1.0f), "%s", DecryptCString(ES_DFCheat_ON));
        ImGui::End();
    }

    // Render
    ImGui::Render();
    id<MTLRenderCommandEncoder> enc = [cmdBuf renderCommandEncoderWithDescriptor:rpd];
    [enc pushDebugGroup:DecryptString(ES_DFCheat)];
    ImGui_ImplMetal_RenderDrawData(ImGui::GetDrawData(), cmdBuf, enc);
    [enc popDebugGroup];
    [enc endEncoding];
    [cmdBuf presentDrawable:drawable];
    [cmdBuf commit];

    // Heartbeat
    if (self.frameCount == 1 || self.frameCount % 300 == 0) {
        df_log(DecryptCString(ES_heartbeat_frame_),
               self.frameCount, g_entity_count, g_df_offsets.gworld_found);
    }

    } @catch (NSException *e) {
        df_log(DecryptCString(ES_CRASH_renderFrame), self.frameCount, [[e description] UTF8String]);
    }
}

- (void)renderESP:(float *)vp {
    ImDrawList *dl = ImGui::GetBackgroundDrawList();

    // Draw aimbot FOV circle
    if (g_df_config.aimbot_enabled && g_df_config.aimbot_fov > 0) {
        dl->AddCircle(ImVec2(self.screenW/2, self.screenH/2),
                      g_df_config.aimbot_fov * 10.0f, IM_COL32(255,255,255,60), 64, 1.0f);
    }

    for (int i = 0; i < g_entity_count; i++) {
        DFEntityData *ent = &g_entities[i];
        if (!ent->is_valid) continue;

        float screen[3];
        if (!world_to_screen_df(ent->position, vp, self.screenW, self.screenH, screen))
            continue;

        float dist = screen[2];
        if (g_df_config.esp_max_distance > 0 && dist / 100.0f > g_df_config.esp_max_distance)
            continue;

        // Color: enemy visible/enemy/team/AI
        ImU32 color;
        if (ent->team == g_local_team && g_local_team) {
            color = IM_COL32((int)(g_df_config.team_color[0]*255),
                            (int)(g_df_config.team_color[1]*255),
                            (int)(g_df_config.team_color[2]*255), 255);
        } else if (ent->is_ai) {
            color = IM_COL32((int)(g_df_config.ai_color[0]*255),
                            (int)(g_df_config.ai_color[1]*255),
                            (int)(g_df_config.ai_color[2]*255), 255);
        } else if (ent->visible) {
            color = IM_COL32((int)(g_df_config.enemy_visible_color[0]*255),
                            (int)(g_df_config.enemy_visible_color[1]*255),
                            (int)(g_df_config.enemy_visible_color[2]*255), 255);
        } else {
            color = IM_COL32((int)(g_df_config.enemy_color[0]*255),
                            (int)(g_df_config.enemy_color[1]*255),
                            (int)(g_df_config.enemy_color[2]*255), 255);
        }

        // Box dimensions based on distance
        float boxH = (2000.0f / (dist + 1.0f)) * (self.screenH / 1080.0f);
        float boxW = boxH * 0.5f;
        float x = screen[0], y = screen[1];
        float x1 = x - boxW/2, y1 = y - boxH;
        float x2 = x + boxW/2, y2 = y;

        // === ESP Box ===
        if (g_df_config.esp_box) {
            dl->AddRect(ImVec2(x1-1, y1-1), ImVec2(x2+1, y2+1),
                        IM_COL32(0,0,0,180), 0, 0, g_df_config.box_thickness + 0.5f);
            dl->AddRect(ImVec2(x1, y1), ImVec2(x2, y2), color, 0, 0, g_df_config.box_thickness);

            // Corner highlights
            float cl = boxW * 0.25f;
            dl->AddLine(ImVec2(x1, y1), ImVec2(x1 + cl, y1), IM_COL32(255,255,255,50), 1.0f);
            dl->AddLine(ImVec2(x1, y1), ImVec2(x1, y1 + cl), IM_COL32(255,255,255,50), 1.0f);
            dl->AddLine(ImVec2(x2, y1), ImVec2(x2 - cl, y1), IM_COL32(255,255,255,50), 1.0f);
            dl->AddLine(ImVec2(x2, y1), ImVec2(x2, y1 + cl), IM_COL32(255,255,255,50), 1.0f);
        }

        // === Health Bar ===
        if (g_df_config.esp_health_bar) {
            float hpPct = ent->health / (ent->max_health > 0 ? ent->max_health : 100.0f);
            if (hpPct > 1.0f) hpPct = 1.0f;
            float barX = x1 - 8;
            dl->AddRectFilled(ImVec2(barX-2, y1-1), ImVec2(barX+2, y2+1), IM_COL32(0,0,0,120));
            ImU32 hpColor = hpPct > 0.6f ? IM_COL32(0,255,100,220) :
                            hpPct > 0.3f ? IM_COL32(255,200,0,220) :
                                           IM_COL32(255,50,50,220);
            dl->AddRectFilled(ImVec2(barX-1.5f, y2 - boxH * hpPct),
                             ImVec2(barX+1.5f, y2), hpColor);
        }

        // === Distance ===
        if (g_df_config.esp_distance) {
            char buf[32];
            snprintf(buf, sizeof(buf), "%.0fm", dist / 100.0f);
            dl->AddText(ImVec2(x, y2 + 2), IM_COL32(255,255,255,200), buf);
        }

        // === Name ===
        if (g_df_config.esp_name && strlen(ent->name) > 0) {
            dl->AddText(ImVec2(x, y1 - 15), IM_COL32(255,255,255,200), ent->name);
        }

        // === Health text ===
        char hpText[16];
        snprintf(hpText, sizeof(hpText), "%.0fHP", ent->health);
        dl->AddText(ImVec2(x, y1 - (g_df_config.esp_name ? 28 : 15)), color, hpText);

        // === Head dot ===
        if (g_df_config.esp_head_dot) {
            float headScreen[3];
            float headWorld[3] = {ent->position[0], ent->position[1], ent->position[2] + 180.0f};
            if (world_to_screen_df(headWorld, vp, self.screenW, self.screenH, headScreen)) {
                dl->AddCircleFilled(ImVec2(headScreen[0], headScreen[1]),
                                   boxW * 0.1f, IM_COL32(255,255,255,200), 8);
            }
        }

        // === Line to bottom ===
        if (g_df_config.esp_line) {
            dl->AddLine(ImVec2(x, y2), ImVec2(x, self.screenH), color, 1.0f);
        }
    }
}

- (void)renderCheatMenu:(float *)vp {
    ImGui::SetNextWindowSize(ImVec2(400, 520), ImGuiCond_FirstUseEver);
    ImGui::SetNextWindowPos(ImVec2(20, 20), ImGuiCond_FirstUseEver);

    ImGui::Begin(DecryptCString(ES_DFCheat___三角洲), &_menuOpen,
                 ImGuiWindowFlags_NoCollapse | ImGuiWindowFlags_NoResize);

    // Tab bar
    const char *tabs[] = {DecryptCString(ES_AIM), DecryptCString(ES_VISUAL), DecryptCString(ES_MISC), DecryptCString(ES_WEAPON), DecryptCString(ES_INFO)};
    for (int i = 0; i < 5; i++) {
        if (i > 0) ImGui::SameLine();
        if (ImGui::Button(tabs[i], ImVec2(70, 28))) self.selectedTab = i;
    }
    ImGui::Separator();

    switch (self.selectedTab) {
        case 0: [self aimTab]; break;
        case 1: [self visualTab]; break;
        case 2: [self miscTab]; break;
        case 3: [self weaponTab]; break;
        case 4: [self infoTab]; break;
    }

    ImGui::End();
}

- (void)aimTab {
    ImGui::Checkbox(DecryptCString(ES_Aimbot), (bool *)&g_df_config.aimbot_enabled);
    ImGui::Checkbox(DecryptCString(ES_Auto_Fire), (bool *)&g_df_config.aimbot_auto_fire);
    ImGui::Checkbox(DecryptCString(ES_Visibility_Check), (bool *)&g_df_config.aimbot_visibility_check);
    ImGui::Checkbox(DecryptCString(ES_Ignore_Downed), (bool *)&g_df_config.aimbot_ignore_down);

    ImGui::SliderFloat(DecryptCString(ES_FOV), &g_df_config.aimbot_fov, 1.0f, 30.0f, "%.1f deg");
    ImGui::SliderFloat(DecryptCString(ES_Smooth), &g_df_config.aimbot_smooth, 0.1f, 1.0f, "%.2f");
    ImGui::SliderFloat(DecryptCString(ES_Max_Dist), &g_df_config.aimbot_max_distance, 10.0f, 500.0f, "%.0fm");

    static int bone = 0;
    const char *bones[] = {DecryptCString(ES_Head), DecryptCString(ES_Neck), DecryptCString(ES_Chest), DecryptCString(ES_Pelvis)};
    ImGui::Combo(DecryptCString(ES_Target_Bone), &bone, bones, 4);
    g_df_config.aimbot_target_bone = bone;
}

- (void)visualTab {
    ImGui::Checkbox(DecryptCString(ES_ESP), (bool *)&g_df_config.esp_enabled);
    ImGui::SameLine(); ImGui::Checkbox("Box", (bool *)&g_df_config.esp_box);
    ImGui::Checkbox(DecryptCString(ES_Health_Bar), (bool *)&g_df_config.esp_health_bar);
    ImGui::SameLine(); ImGui::Checkbox(DecryptCString(ES_Distance), (bool *)&g_df_config.esp_distance);
    ImGui::Checkbox("Name", (bool *)&g_df_config.esp_name);
    ImGui::SameLine(); ImGui::Checkbox(DecryptCString(ES_Skeleton), (bool *)&g_df_config.esp_skeleton);
    ImGui::Checkbox(DecryptCString(ES_Head_Dot), (bool *)&g_df_config.esp_head_dot);
    ImGui::SameLine(); ImGui::Checkbox(DecryptCString(ES_Line), (bool *)&g_df_config.esp_line);

    ImGui::Separator();
    ImGui::Checkbox(DecryptCString(ES_Only_Visible), (bool *)&g_df_config.esp_visible_only);
    ImGui::Checkbox(DecryptCString(ES_Show_AI), (bool *)&g_df_config.esp_show_ai);
    ImGui::Checkbox(DecryptCString(ES_Show_Team), (bool *)&g_df_config.esp_show_team);
    ImGui::SliderFloat(DecryptCString(ES_Max_Distance), &g_df_config.esp_max_distance, 10.0f, 500.0f, "%.0fm");
    ImGui::SliderFloat(DecryptCString(ES_Box_Thick), &g_df_config.box_thickness, 0.5f, 4.0f, "%.1f");

    ImGui::Separator();
    ImGui::ColorEdit3(DecryptCString(ES_Enemy_Color), g_df_config.enemy_color);
    ImGui::ColorEdit3(DecryptCString(ES_Visible_Color), g_df_config.enemy_visible_color);
    ImGui::ColorEdit3(DecryptCString(ES_Team_Color), g_df_config.team_color);
    ImGui::ColorEdit3(DecryptCString(ES_AI_Color), g_df_config.ai_color);
}

- (void)miscTab {
    ImGui::Checkbox(DecryptCString(ES_No_Recoil), (bool *)&g_df_config.no_recoil);
    ImGui::SameLine(); ImGui::Checkbox(DecryptCString(ES_No_Spread), (bool *)&g_df_config.no_spread);
}

- (void)weaponTab {
    ImGui::Text("%s", DecryptCString(ES_Weapon_presets_loaded_from_Stocks_config));
    ImGui::Text("%s", DecryptCString(ES_Current__Default));
    ImGui::Separator();
    static int sel = 0;
    const char *weps[] = {"AKM","QBZ95-1","QBZ-17","AKS-74U","ASH-12",
                          "M16A4","M4A1","K416","AUG","M7","SC17","97M"};
    ImGui::ListBox("##weps", &sel, weps, 12, 6);
    if (ImGui::Button(DecryptCString(ES_Apply), ImVec2(-1, 30))) {
        df_log("Weapon selected: %s", weps[sel]);
    }
}

- (void)infoTab {
    ImGui::TextColored(ImVec4(0.2f, 0.8f, 0.6f, 1.0f), "%s", DecryptCString(ES_DFCheat_v1_0));
    ImGui::Text(DecryptCString(ES_PID_), getpid());
    ImGui::Text(DecryptCString(ES_Frame_), self.frameCount);
    ImGui::Text(DecryptCString(ES_Resolution_), self.screenW, self.screenH);

    ImGui::Separator();
    ImGui::Text("Game Base: 0x%llx", g_df_offsets.game_base);
    ImGui::Text("GWorld: %s (0x%llx)",
                g_df_offsets.gworld_found ? "FOUND" : "MISSING",
                g_df_offsets.gworld_ptr);
    ImGui::Text("GName: %s (0x%llx)",
                g_df_offsets.gname_found ? "FOUND" : "MISSING",
                g_df_offsets.gname_base);
    ImGui::Text(DecryptCString(ES_Entities_), g_entity_count);
    ImGui::Text(DecryptCString(ES_Local_Team_), g_local_team);

    ImGui::Separator();
    ImGui::Text(DecryptCString(ES_Aimbot_Target_), g_best_target ? "Locked" : "None");

    if (ImGui::Button(DecryptCString(ES_Rescan_Offsets), ImVec2(-1, 30))) {
        scan_all_inprocess();
    }
    if (ImGui::Button(DecryptCString(ES_Hide_Menu__ESC_), ImVec2(-1, 30))) {
        self.menuOpen = NO;
    }
}

@end

// === Dylib Constructor ===
__attribute__((constructor))
static void DFCheatInit(void) {
    df_log(DecryptCString(ES_DFCheat_dylib_loaded), getpid());
    @try {
        if ([NSThread isMainThread]) {
            [[DFCheatController shared] startOverlay];
        } else {
            CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopCommonModes, ^{
                @try {
                    [[DFCheatController shared] startOverlay];
                } @catch (NSException *e) {
                    df_log(DecryptCString(ES_CRASH_in_startOverlay), [[e description] UTF8String]);
                }
            });
            CFRunLoopWakeUp(CFRunLoopGetMain());
        }
    } @catch (NSException *e) {
        df_log(DecryptCString(ES_CRASH_in_constructor), [[e description] UTF8String]);
    }
}

__attribute__((destructor))
static void DFCheatCleanup(void) {
    [[DFCheatController shared] stopOverlay];
    df_log(DecryptCString(ES_DFCheat_dylib_unloaded));
    if (g_log) { fclose(g_log); g_log = NULL; }
}
