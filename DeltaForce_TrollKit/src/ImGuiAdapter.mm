// ImGuiAdapter - Dear ImGui 适配层
// 使用 Metal 后端渲染作弊菜单 UI (60fps)

#import "ImGuiAdapter.h"
#import "ESPOverlay.h"
#import "WeaponConfig.h"
#import "GameHooks.h"
#import "imgui.h"
#import "imgui_impl_metal.h"

@interface ImGuiAdapter ()
@property (nonatomic) int selectedTab;
@property (nonatomic, strong) NSString *statusMessage;
@end

@implementation ImGuiAdapter

- (instancetype)init {
    self = [super init];
    if (self) {
        self.selectedTab = 0;
        self.statusMessage = @"Ready";
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
    style.WindowRounding  = 12.0f;
    style.FrameRounding   = 8.0f;
    style.ScrollbarSize   = 6.0f;
}

- (void)beginFrame:(CGSize)drawableSize timestamp:(double)timestamp {
    ImGuiIO &io = ImGui::GetIO();
    io.DisplaySize = ImVec2(drawableSize.width, drawableSize.height);
    io.DeltaTime = 1.0f / 60.0f;
    (void)timestamp;
    ImGui::NewFrame();
}

- (void)renderCheatMenu:(id)hudRootVC {
    if (!self.menuOpen) {
        [self renderPersistentOverlay:hudRootVC];
        return;
    }

    ImGui::SetNextWindowSize(ImVec2(380, 500), ImGuiCond_FirstUseEver);
    ImGui::SetNextWindowPos(ImVec2(50, 50), ImGuiCond_FirstUseEver);

    ImGui::Begin("DeltaForce TrollKit v2.1", &self.menuOpen,
                 ImGuiWindowFlags_NoCollapse | ImGuiWindowFlags_NoResize);

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

    ImGui::End();
}

- (void)renderAimTab {
    ImGui::Checkbox("Enable Aimbot", &self.aimbotEnabled);
    ImGui::Checkbox("Auto Fire", &self.autoFire);

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

    if (ImGui::Button("Force Headshot", ImVec2(-1, 30))) {}
}

- (void)renderVisualTab {
    ImGui::Checkbox("ESP Box", &self.espEnabled);
    ImGui::Checkbox("Wallhack (See Through Walls)", &self.wallhackEnabled);
    ImGui::Checkbox("Player Name", &self.showNames);
    ImGui::Checkbox("Health Bar", &self.showHealth);
    ImGui::Checkbox("Distance", &self.showDistance);
    ImGui::Checkbox("Skeleton / Bones", &self.showSkeleton);
    ImGui::Checkbox("Item ESP", &self.showItems);
    ImGui::Checkbox("Vehicle ESP", &self.showVehicles);

    ImGui::Separator();
    static float teamColor[3] = {0,1,0};
    ImGui::ColorEdit3("Team Color", teamColor);
    static float enemyColor[3] = {1,0,0};
    ImGui::ColorEdit3("Enemy Color", enemyColor);
    static float visibleColor[3] = {1,0.78f,0};
    ImGui::ColorEdit3("Visible Enemy", visibleColor);

    static float espThickness = 1.5f;
    ImGui::SliderFloat("Outline Thickness", &espThickness, 0.5f, 3.0f);
}

- (void)renderMiscTab {
    ImGui::Checkbox("No Recoil", &self.noRecoilEnabled);
    ImGui::Checkbox("No Spread", &self.noSpreadEnabled);
    ImGui::Checkbox("No Reload", &self.noReload);
    ImGui::Checkbox("Rapid Fire", &self.rapidFire);
    ImGui::Checkbox("Magic Bullet", &self.magicBullet);

    ImGui::Separator();
    ImGui::Checkbox("Speed Hack", &self.speedHackEnabled);
    static float speedMult = 1.5f;
    if (self.speedHackEnabled) {
        ImGui::SliderFloat("Speed Multiplier", &speedMult, 1.0f, 5.0f, "%.1fx");
    }

    ImGui::Separator();
    ImGui::Checkbox("No Clip", &self.noclip);
    ImGui::Checkbox("Infinite Ammo", &self.infiniteAmmo);
    ImGui::Checkbox("God Mode", &self.godMode);
}

- (void)renderWeaponTab {
    ImGui::Text("Current Weapon: %s",
                [WeaponConfigManager shared].currentConfig.name.UTF8String);

    ImGui::Separator();

    NSArray *weapons = @[@"AKM", @"QBZ95-1", @"QBZ-17", @"AKS-74U", @"ASH-12",
                          @"M16A4", @"M4A1", @"K416", @"AUG", @"M7", @"SC17", @"97M"];

    static int selected = 3;
    ImGui::ListBox("Presets", &selected,
                   [self cStringArray:weapons], (int)weapons.count, 6);

    if (ImGui::Button("Apply Weapon Config", ImVec2(-1, 30))) {
        [[WeaponConfigManager shared] applyConfigForWeapon:weapons[selected]];
    }

    ImGui::Separator();
    WeaponConfig *cfg = [WeaponConfigManager shared].currentConfig;
    float rx = cfg.recoilCompensationX;
    float ry = cfg.recoilCompensationY;
    ImGui::SliderFloat("Recoil X", &rx, 0.0f, 1.0f);
    ImGui::SliderFloat("Recoil Y", &ry, 0.0f, 1.0f);
}

- (void)renderConfigTab {
    if (ImGui::Button("Save Config", ImVec2(-1, 30))) { [self saveConfig]; }
    if (ImGui::Button("Load Config", ImVec2(-1, 30))) { [self loadConfig]; }
    if (ImGui::Button("Reset to Default", ImVec2(-1, 30))) { [self resetConfig]; }

    ImGui::Separator();
    ImGui::Text("Config File: DeltaForce_TrollKit.json");

    ImGui::Separator();
    if (ImGui::Button("Close Menu (ESC)", ImVec2(-1, 30))) { self.menuOpen = NO; }
    if (ImGui::Button("Emergency Hide", ImVec2(-1, 30))) { self.menuOpen = NO; }

    ImGui::TextDisabled("Kernel Level | iOS 15-18 | arm64/arm64e");
}

- (void)renderPersistentOverlay:(id)hudRootVC {
    (void)hudRootVC;
}

- (void)endFrame:(id<MTLCommandBuffer>)cmdBuffer drawable:(id<CAMetalDrawable>)drawable {
    ImGui::Render();
    ImGui_ImplMetal_RenderDrawData(ImGui::GetDrawData(), cmdBuffer, nil);
}

#pragma mark - Config

- (void)saveConfig {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:self.espEnabled forKey:@"esp"];
    [defaults setBool:self.wallhackEnabled forKey:@"wallhack"];
    [defaults setBool:self.aimbotEnabled forKey:@"aimbot"];
    [defaults setBool:self.noRecoilEnabled forKey:@"noRecoil"];
    [defaults synchronize];
    self.statusMessage = @"Config saved";
}

- (void)loadConfig {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    self.espEnabled = [defaults boolForKey:@"esp"];
    self.wallhackEnabled = [defaults boolForKey:@"wallhack"];
    self.aimbotEnabled = [defaults boolForKey:@"aimbot"];
    self.noRecoilEnabled = [defaults boolForKey:@"noRecoil"];
    self.statusMessage = @"Config loaded";
}

- (void)resetConfig {
    self.espEnabled = YES;
    self.wallhackEnabled = YES;
    self.aimbotEnabled = YES;
    self.noRecoilEnabled = YES;
    self.noSpreadEnabled = YES;
    self.speedHackEnabled = NO;
    self.statusMessage = @"Default config restored";
}

#pragma mark - Helpers

- (const char **)cStringArray:(NSArray *)array {
    static const char *cstrings[32];
    for (int i = 0; i < array.count && i < 32; i++) {
        cstrings[i] = [array[i] UTF8String];
    }
    return cstrings;
}

@end
