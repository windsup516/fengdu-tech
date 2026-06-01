// ImGuiAdapter - Dear ImGui 适配层 + 完整作弊菜单
// Metal 后端渲染 60fps / TrollStore 兼容

#import "ImGuiAdapter.h"
#import "ESPOverlay.h"
#import "WeaponConfig.h"
#import "GameHooks.h"
#import "imgui.h"
#import "imgui_impl_metal.h"

@interface ImGuiAdapter ()
@property (nonatomic) int selectedTab;
@property (nonatomic, strong) NSString *statusMessage;
@property (nonatomic) float screenW, screenH;
@end

@implementation ImGuiAdapter

- (instancetype)init {
    self = [super init];
    if (self) {
        self.selectedTab = 0;
        self.menuOpen = YES;
        self.statusMessage = @"Ready";
        self.espEnabled = YES;
        self.wallhackEnabled = YES;
        self.aimbotEnabled = NO;
        self.noRecoilEnabled = YES;
        self.noSpreadEnabled = YES;
        self.showNames = YES;
        self.showHealth = YES;
        self.showDistance = YES;
        self.showSkeleton = YES;
        self.showItems = NO;
        self.showVehicles = NO;
        self.autoFire = NO;
        self.noReload = NO;
        self.rapidFire = NO;
        self.magicBullet = NO;
        self.noclip = NO;
        self.infiniteAmmo = NO;
        self.godMode = NO;
        self.speedHackEnabled = NO;
    }
    return self;
}

- (void)loadFonts {
    ImGuiIO &io = ImGui::GetIO();
    io.Fonts->AddFontDefault();
}

- (void)setupStyle {
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
    style.WindowRounding  = 12.0f;
    style.FrameRounding   = 8.0f;
    style.ScrollbarSize   = 6.0f;
    style.WindowBorderSize = 1.0f;
    style.WindowPadding   = ImVec2(12, 12);
}

- (void)beginFrame:(CGSize)drawableSize timestamp:(double)timestamp {
    self.screenW = drawableSize.width;
    self.screenH = drawableSize.height;

    ImGuiIO &io = ImGui::GetIO();
    io.DisplaySize = ImVec2(drawableSize.width, drawableSize.height);
    io.DeltaTime = 1.0f / 60.0f;
    (void)timestamp;
    ImGui::NewFrame();
}

- (void)renderCheatMenu:(id)hudRootVC {
    // 如果ESP开启, 渲染透视覆盖层
    [self renderPersistentOverlay:hudRootVC];

    if (!self.menuOpen) {
        // 显示一个小指示器表示菜单隐藏但仍在运行
        ImGui::SetNextWindowPos(ImVec2(self.screenW - 130, 10), ImGuiCond_Always);
        ImGui::SetNextWindowSize(ImVec2(120, 30), ImGuiCond_Always);
        ImGui::Begin("##minibar", NULL,
                     ImGuiWindowFlags_NoTitleBar | ImGuiWindowFlags_NoResize |
                     ImGuiWindowFlags_NoMove | ImGuiWindowFlags_NoScrollbar);
        ImGui::TextColored(ImVec4(0.2f, 0.8f, 0.4f, 1.0f), "CHEAT ON");
        ImGui::End();
        return;
    }

    // 主菜单窗口
    ImGui::SetNextWindowSize(ImVec2(400, 520), ImGuiCond_FirstUseEver);
    ImGui::SetNextWindowPos(ImVec2(20, 20), ImGuiCond_FirstUseEver);

    ImGui::Begin("DeltaForce TrollKit v2.1", &_menuOpen,
                 ImGuiWindowFlags_NoCollapse | ImGuiWindowFlags_NoResize);

    // Tab 栏
    const char *tabs[] = {"AIM", "VISUAL", "MISC", "WEAPON", "CONFIG"};
    for (int i = 0; i < 5; i++) {
        if (i > 0) ImGui::SameLine();
        if (ImGui::Button(tabs[i], ImVec2(70, 28))) {
            self.selectedTab = i;
        }
    }

    ImGui::Separator();

    switch (self.selectedTab) {
        case 0: [self renderAimTab]; break;
        case 1: [self renderVisualTab]; break;
        case 2: [self renderMiscTab]; break;
        case 3: [self renderWeaponTab]; break;
        case 4: [self renderConfigTab]; break;
    }

    ImGui::Separator();
    ImGui::TextColored(ImVec4(0.2f, 0.8f, 0.6f, 1.0f), "Status: %s",
                       self.statusMessage.UTF8String ?: "Ready");

    // 提示
    ImGui::TextDisabled("Press ESC or close window to hide menu");

    ImGui::End();
}

- (void)renderAimTab {
    ImGui::Checkbox("Enable Aimbot", &_aimbotEnabled);
    ImGui::Checkbox("Auto Fire", &_autoFire);

    static int aimKey = 0;
    ImGui::Combo("Activation", &aimKey, "Always\0ADS\0Toggle\0");

    static float aimFov = 5.0f;
    ImGui::SliderFloat("Aimbot FOV", &aimFov, 1.0f, 30.0f, "%.1f deg");

    static float aimSmooth = 0.85f;
    ImGui::SliderFloat("Smoothness", &aimSmooth, 0.1f, 1.0f, "%.2f");

    static int aimBone = 0;
    ImGui::Combo("Target Bone", &aimBone, "Head\0Neck\0Chest\0Pelvis\0");

    static float maxDist = 300.0f;
    ImGui::SliderFloat("Max Distance", &maxDist, 10.0f, 500.0f, "%.0fm");

    if (ImGui::Button("Force Headshot", ImVec2(-1, 30))) {
        self.statusMessage = @"Headshot forced";
    }
}

- (void)renderVisualTab {
    ImGui::Checkbox("ESP Box", &_espEnabled);
    ImGui::SameLine();
    ImGui::Checkbox("Wallhack", &_wallhackEnabled);

    ImGui::Checkbox("Player Name", &_showNames);
    ImGui::SameLine();
    ImGui::Checkbox("Health Bar", &_showHealth);

    ImGui::Checkbox("Distance", &_showDistance);
    ImGui::SameLine();
    ImGui::Checkbox("Skeleton", &_showSkeleton);

    ImGui::Checkbox("Item ESP", &_showItems);
    ImGui::SameLine();
    ImGui::Checkbox("Vehicle ESP", &_showVehicles);

    ImGui::Separator();

    static float teamColor[3] = {0.0f, 1.0f, 0.0f};
    ImGui::ColorEdit3("Team Color", teamColor);
    static float enemyColor[3] = {1.0f, 0.0f, 0.0f};
    ImGui::ColorEdit3("Enemy Color", enemyColor);
    static float visibleColor[3] = {1.0f, 0.78f, 0.0f};
    ImGui::ColorEdit3("Visible Enemy", visibleColor);

    static float espThickness = 1.5f;
    ImGui::SliderFloat("Outline", &espThickness, 0.5f, 3.0f);

    // 应用 Wallhack
    if (self.wallhackEnabled) {
        static BOOL whApplied = NO;
        if (!whApplied) {
            hooks_patch_wallhack(YES);
            whApplied = YES;
        }
    }
}

- (void)renderMiscTab {
    if (ImGui::Checkbox("No Recoil", &_noRecoilEnabled)) {
        hooks_patch_recoil(self.noRecoilEnabled);
        self.statusMessage = self.noRecoilEnabled ? @"No Recoil ON" : @"No Recoil OFF";
    }

    if (ImGui::Checkbox("No Spread", &_noSpreadEnabled)) {
        hooks_patch_no_spread(self.noSpreadEnabled);
        self.statusMessage = self.noSpreadEnabled ? @"No Spread ON" : @"No Spread OFF";
    }

    ImGui::Checkbox("No Reload", &_noReload);
    ImGui::SameLine();
    ImGui::Checkbox("Rapid Fire", &_rapidFire);

    ImGui::Checkbox("Magic Bullet", &_magicBullet);

    ImGui::Separator();

    ImGui::Checkbox("Speed Hack", &_speedHackEnabled);
    static float speedMult = 1.5f;
    if (self.speedHackEnabled) {
        ImGui::SliderFloat("Multiplier", &speedMult, 1.0f, 5.0f, "%.1fx");
    }

    ImGui::Separator();

    ImGui::Checkbox("No Clip", &_noclip);
    ImGui::SameLine();
    ImGui::Checkbox("Infinite Ammo", &_infiniteAmmo);
    ImGui::Checkbox("God Mode", &_godMode);
}

- (void)renderWeaponTab {
    ImGui::Text("Current: %s",
                [WeaponConfigManager shared].currentConfig.name.UTF8String ?: "None");
    ImGui::Separator();

    static int selected = 5; // M4A1
    const char *weapons[] = {"AKM", "QBZ95-1", "QBZ-17", "AKS-74U", "ASH-12",
                            "M16A4", "M4A1", "K416", "AUG", "M7", "SC17", "97M"};
    ImGui::ListBox("Presets", &selected, weapons, 12, 6);

    if (ImGui::Button("Apply Config", ImVec2(-1, 30))) {
        NSArray *wa = @[@"AKM", @"QBZ95-1", @"QBZ-17", @"AKS-74U", @"ASH-12",
                        @"M16A4", @"M4A1", @"K416", @"AUG", @"M7", @"SC17", @"97M"];
        [[WeaponConfigManager shared] applyConfigForWeapon:wa[selected]];
        self.statusMessage = [NSString stringWithFormat:@"Applied: %@", wa[selected]];
    }

    ImGui::Separator();
    WeaponConfig *cfg = [WeaponConfigManager shared].currentConfig;
    float rx = (float)cfg.recoilCompensationX;
    float ry = (float)cfg.recoilCompensationY;
    ImGui::SliderFloat("Recoil X", &rx, 0.0f, 1.0f);
    ImGui::SliderFloat("Recoil Y", &ry, 0.0f, 1.0f);
}

- (void)renderConfigTab {
    if (ImGui::Button("Save Config", ImVec2(-1, 30))) { [self saveConfig]; }
    if (ImGui::Button("Load Config", ImVec2(-1, 30))) { [self loadConfig]; }
    if (ImGui::Button("Reset to Default", ImVec2(-1, 30))) { [self resetConfig]; }

    ImGui::Separator();
    ImGui::Text("Config: DeltaForce_TrollKit.json");
    ImGui::Separator();

    if (ImGui::Button("Close Menu (ESC)", ImVec2(-1, 30))) { self.menuOpen = NO; }
    if (ImGui::Button("EMERGENCY HIDE", ImVec2(-1, 35))) {
        self.menuOpen = NO;
        self.espEnabled = NO;
        self.wallhackEnabled = NO;
        self.aimbotEnabled = NO;
        hooks_patch_recoil(NO);
        hooks_patch_no_spread(NO);
        self.statusMessage = @"ALL DISABLED";
    }

    ImGui::TextDisabled("Kernel Level | iOS 13-18 | arm64");
}

// ESP 覆盖层渲染
- (void)renderPersistentOverlay:(id)hudRootVC {
    if (!self.espEnabled && !self.showItems && !self.showVehicles) return;

    mach_port_t gameTask = hooks_get_game_task();
    if (gameTask == MACH_PORT_NULL) return;

    // 更新实体数据
    static double lastUpdate = 0;
    double now = CACurrentMediaTime();
    if (now - lastUpdate > 0.05) { // 每50ms更新一次
        [[ESPOverlay shared] updateEntitiesFromGameMemory:gameTask];
        lastUpdate = now;
    }

    // 读取相机矩阵
    float viewMatrix[16] = {0};
    float projMatrix[16] = {0};
    if (![[ESPOverlay shared] readGameMatrices:gameTask
                                     viewMatrix:viewMatrix
                                  projectMatrix:projMatrix]) {
        return;
    }

    // 渲染 ESP
    [[ESPOverlay shared] renderESPWithViewMatrix:viewMatrix
                                   projectMatrix:projMatrix
                                           width:self.screenW
                                          height:self.screenH];
}

- (void)endFrame:(id<MTLCommandBuffer>)cmdBuffer
        drawable:(id<CAMetalDrawable>)drawable
  renderPassDesc:(MTLRenderPassDescriptor *)renderPassDesc {
    ImGui::Render();

    id<MTLRenderCommandEncoder> encoder = [cmdBuffer renderCommandEncoderWithDescriptor:renderPassDesc];
    [encoder pushDebugGroup:@"ImGui"];

    ImGui_ImplMetal_RenderDrawData(ImGui::GetDrawData(), cmdBuffer, encoder);

    [encoder popDebugGroup];
    [encoder endEncoding];

    [cmdBuffer presentDrawable:drawable];
}

#pragma mark - Config

- (void)saveConfig {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setBool:self.espEnabled forKey:@"esp"];
    [d setBool:self.wallhackEnabled forKey:@"wallhack"];
    [d setBool:self.aimbotEnabled forKey:@"aimbot"];
    [d setBool:self.noRecoilEnabled forKey:@"noRecoil"];
    [d setBool:self.noSpreadEnabled forKey:@"noSpread"];
    [d synchronize];
    self.statusMessage = @"Config saved";
}

- (void)loadConfig {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    self.espEnabled = [d boolForKey:@"esp"];
    self.wallhackEnabled = [d boolForKey:@"wallhack"];
    self.aimbotEnabled = [d boolForKey:@"aimbot"];
    self.noRecoilEnabled = [d boolForKey:@"noRecoil"];
    self.noSpreadEnabled = [d boolForKey:@"noSpread"];
    self.statusMessage = @"Config loaded";
}

- (void)resetConfig {
    self.espEnabled = YES;
    self.wallhackEnabled = YES;
    self.aimbotEnabled = YES;
    self.noRecoilEnabled = YES;
    self.noSpreadEnabled = YES;
    self.speedHackEnabled = NO;
    self.statusMessage = @"Defaults restored";
}

@end
