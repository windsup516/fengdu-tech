#ifndef IMGUI_ADAPTER_H
#define IMGUI_ADAPTER_H

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>

@interface ImGuiAdapter : NSObject

@property (nonatomic) BOOL menuOpen;
@property (nonatomic) BOOL espEnabled;
@property (nonatomic) BOOL wallhackEnabled;
@property (nonatomic) BOOL aimbotEnabled;
@property (nonatomic) BOOL noRecoilEnabled;
@property (nonatomic) BOOL noSpreadEnabled;
@property (nonatomic) BOOL speedHackEnabled;

// Tab 状态 (占位, ImGui 内部使用)
@property (nonatomic) BOOL showNames;
@property (nonatomic) BOOL showHealth;
@property (nonatomic) BOOL showDistance;
@property (nonatomic) BOOL showSkeleton;
@property (nonatomic) BOOL showItems;
@property (nonatomic) BOOL showVehicles;
@property (nonatomic) BOOL autoFire;
@property (nonatomic) BOOL noReload;
@property (nonatomic) BOOL rapidFire;
@property (nonatomic) BOOL magicBullet;
@property (nonatomic) BOOL noclip;
@property (nonatomic) BOOL infiniteAmmo;
@property (nonatomic) BOOL godMode;

- (void)loadFonts;
- (void)setupStyle;
- (void)beginFrame:(CGSize)drawableSize timestamp:(double)timestamp;
- (void)renderCheatMenu:(id)hudRootVC;
- (void)renderPersistentOverlay:(id)hudRootVC;
- (void)endFrame:(id<MTLCommandBuffer>)cmdBuffer drawable:(id<CAMetalDrawable>)drawable renderPassDesc:(MTLRenderPassDescriptor *)renderPassDesc;

- (void)renderAimTab;
- (void)renderVisualTab;
- (void)renderMiscTab;
- (void)renderWeaponTab;
- (void)renderConfigTab;

- (void)saveConfig;
- (void)loadConfig;
- (void)resetConfig;

@end
#endif
