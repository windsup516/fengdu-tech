// WeaponConfig.m — Full weapon database matching 太阳神 weapon system
// 50+ weapons across 7 categories, skins with rarity, ammo types

#import "WeaponConfig.h"

@implementation WeaponSkin
@end

@interface WeaponConfigManager ()
@property (nonatomic, strong) NSDictionary *configs;
@property (nonatomic, strong) NSArray<NSDictionary *> *skinsData;
@end

@implementation WeaponConfigManager

+ (instancetype)shared {
    static WeaponConfigManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[WeaponConfigManager alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        self.configs = @{
            // === ASSAULT RIFLES ===
            @"AKM": @{
                @"display": @"AKM", @"category": @0, @"ammo": @1, // 7.62
                @"mag": @30, @"fire_rate": @600.0, @"damage": @49.0, @"range": @80.0,
                @"recoil_x": @0.8, @"recoil_y": @0.6,
                @"aim_speed": @0.9, @"fov_scale": @1.0,
                @"auto_fire": @YES, @"aim_assist": @YES,
                @"no_recoil": @YES, @"wallhack": @YES, @"esp": @YES,
                @"aim_bone": @"head", @"aim_fov": @6.0, @"aim_smooth": @0.85,
            },
            @"QBZ95-1": @{
                @"display": @"QBZ95-1", @"category": @0, @"ammo": @2, // 5.45
                @"mag": @30, @"fire_rate": @650.0, @"damage": @41.0, @"range": @75.0,
                @"recoil_x": @0.6, @"recoil_y": @0.4,
                @"aim_speed": @0.8, @"fov_scale": @1.0,
                @"auto_fire": @YES, @"aim_assist": @YES,
                @"no_recoil": @YES, @"wallhack": @YES, @"esp": @YES,
                @"aim_bone": @"head", @"aim_fov": @5.0, @"aim_smooth": @0.9,
            },
            @"QBZ-17": @{
                @"display": @"QBZ-17", @"category": @0, @"ammo": @0, // 5.56
                @"mag": @30, @"fire_rate": @700.0, @"damage": @38.0, @"range": @70.0,
                @"recoil_x": @0.7, @"recoil_y": @0.5,
                @"aim_speed": @0.8, @"fov_scale": @1.0,
                @"auto_fire": @YES, @"aim_assist": @YES,
                @"no_recoil": @YES, @"wallhack": @YES, @"esp": @YES,
                @"aim_bone": @"head", @"aim_fov": @5.5, @"aim_smooth": @0.88,
            },
            @"M16A4": @{
                @"display": @"M16A4", @"category": @0, @"ammo": @0, // 5.56
                @"mag": @30, @"fire_rate": @800.0, @"damage": @36.0, @"range": @85.0,
                @"recoil_x": @0.5, @"recoil_y": @0.3,
                @"aim_speed": @0.8, @"fov_scale": @1.0,
                @"auto_fire": @NO, @"aim_assist": @YES,
                @"no_recoil": @YES, @"wallhack": @YES, @"esp": @YES,
                @"aim_bone": @"head", @"aim_fov": @4.5, @"aim_smooth": @0.92,
            },
            @"M4A1": @{
                @"display": @"M4A1", @"category": @0, @"ammo": @0, // 5.56
                @"mag": @30, @"fire_rate": @750.0, @"damage": @38.0, @"range": @75.0,
                @"recoil_x": @0.5, @"recoil_y": @0.3,
                @"aim_speed": @0.9, @"fov_scale": @1.0,
                @"auto_fire": @YES, @"aim_assist": @YES,
                @"no_recoil": @YES, @"wallhack": @YES, @"esp": @YES,
                @"aim_bone": @"head", @"aim_fov": @5.0, @"aim_smooth": @0.9,
            },
            @"K416": @{
                @"display": @"K416", @"category": @0, @"ammo": @0, // 5.56
                @"mag": @30, @"fire_rate": @750.0, @"damage": @39.0, @"range": @78.0,
                @"recoil_x": @0.5, @"recoil_y": @0.4,
                @"aim_speed": @0.9, @"fov_scale": @1.0,
                @"auto_fire": @YES, @"aim_assist": @YES,
                @"no_recoil": @YES, @"wallhack": @YES, @"esp": @YES,
                @"aim_bone": @"head", @"aim_fov": @5.0, @"aim_smooth": @0.9,
            },
            @"AUG": @{
                @"display": @"AUG", @"category": @0, @"ammo": @0, // 5.56
                @"mag": @30, @"fire_rate": @680.0, @"damage": @37.0, @"range": @80.0,
                @"recoil_x": @0.4, @"recoil_y": @0.3,
                @"aim_speed": @0.8, @"fov_scale": @1.0,
                @"auto_fire": @YES, @"aim_assist": @YES,
                @"no_recoil": @YES, @"wallhack": @YES, @"esp": @YES,
                @"aim_bone": @"head", @"aim_fov": @4.0, @"aim_smooth": @0.93,
            },
            @"SC17": @{
                @"display": @"SC17", @"category": @0, @"ammo": @0, // 5.56
                @"mag": @30, @"fire_rate": @650.0, @"damage": @40.0, @"range": @80.0,
                @"recoil_x": @0.6, @"recoil_y": @0.5,
                @"aim_speed": @0.9, @"fov_scale": @1.0,
                @"auto_fire": @YES, @"aim_assist": @YES,
                @"no_recoil": @YES, @"wallhack": @YES, @"esp": @YES,
                @"aim_bone": @"head", @"aim_fov": @5.0, @"aim_smooth": @0.88,
            },
            @"97M": @{
                @"display": @"97M", @"category": @0, @"ammo": @0, // 5.56
                @"mag": @30, @"fire_rate": @700.0, @"damage": @39.0, @"range": @75.0,
                @"recoil_x": @0.7, @"recoil_y": @0.5,
                @"aim_speed": @0.8, @"fov_scale": @1.0,
                @"auto_fire": @YES, @"aim_assist": @YES,
                @"no_recoil": @YES, @"wallhack": @YES, @"esp": @YES,
                @"aim_bone": @"head", @"aim_fov": @5.5, @"aim_smooth": @0.85,
            },
            @"HK416": @{
                @"display": @"HK416", @"category": @0, @"ammo": @0, // 5.56
                @"mag": @30, @"fire_rate": @720.0, @"damage": @38.0, @"range": @80.0,
                @"recoil_x": @0.5, @"recoil_y": @0.4,
                @"aim_speed": @0.9, @"fov_scale": @1.0,
                @"auto_fire": @YES, @"aim_assist": @YES,
                @"no_recoil": @YES, @"wallhack": @YES, @"esp": @YES,
                @"aim_bone": @"head", @"aim_fov": @5.0, @"aim_smooth": @0.88,
            },
            @"FAL": @{
                @"display": @"FAL", @"category": @0, @"ammo": @1, // 7.62
                @"mag": @20, @"fire_rate": @650.0, @"damage": @58.0, @"range": @90.0,
                @"recoil_x": @1.0, @"recoil_y": @0.8,
                @"aim_speed": @0.7, @"fov_scale": @1.0,
                @"auto_fire": @NO, @"aim_assist": @YES,
                @"no_recoil": @YES, @"wallhack": @YES, @"esp": @YES,
                @"aim_bone": @"head", @"aim_fov": @7.0, @"aim_smooth": @0.8,
            },
            @"ACE32": @{
                @"display": @"ACE 32", @"category": @0, @"ammo": @1, // 7.62
                @"mag": @30, @"fire_rate": @700.0, @"damage": @48.0, @"range": @82.0,
                @"recoil_x": @0.8, @"recoil_y": @0.6,
                @"aim_speed": @0.8, @"fov_scale": @1.0,
                @"auto_fire": @YES, @"aim_assist": @YES,
                @"no_recoil": @YES, @"wallhack": @YES, @"esp": @YES,
                @"aim_bone": @"head", @"aim_fov": @6.0, @"aim_smooth": @0.85,
            },

            // === SMGs ===
            @"AKS-74U": @{
                @"display": @"AKS-74U", @"category": @1, @"ammo": @2, // 5.45
                @"mag": @30, @"fire_rate": @720.0, @"damage": @35.0, @"range": @60.0,
                @"recoil_x": @0.9, @"recoil_y": @0.7,
                @"aim_speed": @0.9, @"fov_scale": @1.0,
                @"auto_fire": @YES, @"aim_assist": @YES,
                @"no_recoil": @YES, @"wallhack": @YES, @"esp": @YES,
                @"aim_bone": @"head", @"aim_fov": @6.5, @"aim_smooth": @0.8,
            },
            @"MP5": @{
                @"display": @"MP5", @"category": @1, @"ammo": @7, // 9mm
                @"mag": @30, @"fire_rate": @800.0, @"damage": @30.0, @"range": @50.0,
                @"recoil_x": @0.5, @"recoil_y": @0.4,
                @"aim_speed": @1.0, @"fov_scale": @1.0,
                @"auto_fire": @YES, @"aim_assist": @YES,
                @"no_recoil": @YES, @"wallhack": @YES, @"esp": @YES,
                @"aim_bone": @"head", @"aim_fov": @5.0, @"aim_smooth": @0.9,
            },
            @"P90": @{
                @"display": @"P90", @"category": @1, @"ammo": @8, // 5.7
                @"mag": @50, @"fire_rate": @900.0, @"damage": @28.0, @"range": @45.0,
                @"recoil_x": @0.4, @"recoil_y": @0.3,
                @"aim_speed": @1.0, @"fov_scale": @1.0,
                @"auto_fire": @YES, @"aim_assist": @YES,
                @"no_recoil": @YES, @"wallhack": @YES, @"esp": @YES,
                @"aim_bone": @"head", @"aim_fov": @4.0, @"aim_smooth": @0.92,
            },
            @"UMP45": @{
                @"display": @"UMP45", @"category": @1, @"ammo": @4, // .45
                @"mag": @25, @"fire_rate": @600.0, @"damage": @36.0, @"range": @55.0,
                @"recoil_x": @0.6, @"recoil_y": @0.5,
                @"aim_speed": @0.9, @"fov_scale": @1.0,
                @"auto_fire": @YES, @"aim_assist": @YES,
                @"no_recoil": @YES, @"wallhack": @YES, @"esp": @YES,
                @"aim_bone": @"head", @"aim_fov": @5.5, @"aim_smooth": @0.88,
            },
            @"VECTOR": @{
                @"display": @"Vector", @"category": @1, @"ammo": @4, // .45
                @"mag": @13, @"fire_rate": @1100.0, @"damage": @32.0, @"range": @40.0,
                @"recoil_x": @0.7, @"recoil_y": @0.6,
                @"aim_speed": @1.0, @"fov_scale": @1.0,
                @"auto_fire": @YES, @"aim_assist": @YES,
                @"no_recoil": @YES, @"wallhack": @YES, @"esp": @YES,
                @"aim_bone": @"head", @"aim_fov": @5.0, @"aim_smooth": @0.85,
            },

            // === SNIPERS ===
            @"M24": @{
                @"display": @"M24", @"category": @2, @"ammo": @1, // 7.62
                @"mag": @5, @"fire_rate": @45.0, @"damage": @95.0, @"range": @200.0,
                @"recoil_x": @1.5, @"recoil_y": @1.2,
                @"aim_speed": @0.5, @"fov_scale": @2.0,
                @"auto_fire": @NO, @"aim_assist": @YES,
                @"no_recoil": @YES, @"wallhack": @YES, @"esp": @YES,
                @"aim_bone": @"head", @"aim_fov": @3.0, @"aim_smooth": @0.95,
            },
            @"AWM": @{
                @"display": @"AWM", @"category": @2, @"ammo": @6, // .338
                @"mag": @5, @"fire_rate": @40.0, @"damage": @120.0, @"range": @250.0,
                @"recoil_x": @1.8, @"recoil_y": @1.5,
                @"aim_speed": @0.4, @"fov_scale": @3.0,
                @"auto_fire": @NO, @"aim_assist": @YES,
                @"no_recoil": @YES, @"wallhack": @YES, @"esp": @YES,
                @"aim_bone": @"head", @"aim_fov": @2.5, @"aim_smooth": @0.95,
            },
            @"AX50": @{
                @"display": @"AX50", @"category": @2, @"ammo": @5, // .50 BMG
                @"mag": @5, @"fire_rate": @38.0, @"damage": @135.0, @"range": @300.0,
                @"recoil_x": @2.0, @"recoil_y": @1.8,
                @"aim_speed": @0.3, @"fov_scale": @3.5,
                @"auto_fire": @NO, @"aim_assist": @NO,
                @"no_recoil": @YES, @"wallhack": @YES, @"esp": @YES,
                @"aim_bone": @"head", @"aim_fov": @2.0, @"aim_smooth": @0.98,
            },
            @"SV-98": @{
                @"display": @"SV-98", @"category": @2, @"ammo": @1, // 7.62
                @"mag": @10, @"fire_rate": @50.0, @"damage": @90.0, @"range": @190.0,
                @"recoil_x": @1.4, @"recoil_y": @1.1,
                @"aim_speed": @0.5, @"fov_scale": @2.2,
                @"auto_fire": @NO, @"aim_assist": @YES,
                @"no_recoil": @YES, @"wallhack": @YES, @"esp": @YES,
                @"aim_bone": @"head", @"aim_fov": @3.0, @"aim_smooth": @0.95,
            },

            // === SHOTGUNS ===
            @"M870": @{
                @"display": @"M870", @"category": @3, @"ammo": @3, // 12ga
                @"mag": @5, @"fire_rate": @80.0, @"damage": @100.0, @"range": @20.0,
                @"recoil_x": @2.0, @"recoil_y": @1.5,
                @"aim_speed": @0.7, @"fov_scale": @0.8,
                @"auto_fire": @NO, @"aim_assist": @YES,
                @"no_recoil": @YES, @"wallhack": @YES, @"esp": @YES,
                @"aim_bone": @"chest", @"aim_fov": @10.0, @"aim_smooth": @0.75,
            },
            @"S12K": @{
                @"display": @"S12K", @"category": @3, @"ammo": @3, // 12ga
                @"mag": @5, @"fire_rate": @70.0, @"damage": @95.0, @"range": @22.0,
                @"recoil_x": @1.8, @"recoil_y": @1.4,
                @"aim_speed": @0.7, @"fov_scale": @0.9,
                @"auto_fire": @NO, @"aim_assist": @YES,
                @"no_recoil": @YES, @"wallhack": @YES, @"esp": @YES,
                @"aim_bone": @"chest", @"aim_fov": @9.0, @"aim_smooth": @0.78,
            },
            @"AA12": @{
                @"display": @"AA-12", @"category": @3, @"ammo": @3, // 12ga
                @"mag": @8, @"fire_rate": @300.0, @"damage": @75.0, @"range": @18.0,
                @"recoil_x": @1.2, @"recoil_y": @1.0,
                @"aim_speed": @0.8, @"fov_scale": @0.8,
                @"auto_fire": @YES, @"aim_assist": @YES,
                @"no_recoil": @YES, @"wallhack": @YES, @"esp": @YES,
                @"aim_bone": @"chest", @"aim_fov": @8.0, @"aim_smooth": @0.82,
            },

            // === LMGs ===
            @"M249": @{
                @"display": @"M249", @"category": @4, @"ammo": @0, // 5.56
                @"mag": @100, @"fire_rate": @800.0, @"damage": @38.0, @"range": @85.0,
                @"recoil_x": @0.7, @"recoil_y": @0.5,
                @"aim_speed": @0.6, @"fov_scale": @1.0,
                @"auto_fire": @YES, @"aim_assist": @YES,
                @"no_recoil": @YES, @"wallhack": @YES, @"esp": @YES,
                @"aim_bone": @"chest", @"aim_fov": @7.0, @"aim_smooth": @0.8,
            },
            @"PKM": @{
                @"display": @"PKM", @"category": @4, @"ammo": @1, // 7.62
                @"mag": @100, @"fire_rate": @650.0, @"damage": @50.0, @"range": @90.0,
                @"recoil_x": @0.9, @"recoil_y": @0.7,
                @"aim_speed": @0.5, @"fov_scale": @1.0,
                @"auto_fire": @YES, @"aim_assist": @YES,
                @"no_recoil": @YES, @"wallhack": @YES, @"esp": @YES,
                @"aim_bone": @"chest", @"aim_fov": @8.0, @"aim_smooth": @0.75,
            },
            @"RPK": @{
                @"display": @"RPK", @"category": @4, @"ammo": @1, // 7.62
                @"mag": @40, @"fire_rate": @600.0, @"damage": @48.0, @"range": @85.0,
                @"recoil_x": @0.8, @"recoil_y": @0.6,
                @"aim_speed": @0.7, @"fov_scale": @1.0,
                @"auto_fire": @YES, @"aim_assist": @YES,
                @"no_recoil": @YES, @"wallhack": @YES, @"esp": @YES,
                @"aim_bone": @"chest", @"aim_fov": @7.5, @"aim_smooth": @0.78,
            },

            // === PISTOLS ===
            @"Glock17": @{
                @"display": @"Glock 17", @"category": @5, @"ammo": @7, // 9mm
                @"mag": @17, @"fire_rate": @400.0, @"damage": @26.0, @"range": @30.0,
                @"recoil_x": @0.5, @"recoil_y": @0.4,
                @"aim_speed": @1.2, @"fov_scale": @0.8,
                @"auto_fire": @NO, @"aim_assist": @YES,
                @"no_recoil": @YES, @"wallhack": @YES, @"esp": @YES,
                @"aim_bone": @"head", @"aim_fov": @8.0, @"aim_smooth": @0.9,
            },
            @"M1911": @{
                @"display": @"M1911", @"category": @5, @"ammo": @4, // .45
                @"mag": @7, @"fire_rate": @350.0, @"damage": @45.0, @"range": @25.0,
                @"recoil_x": @0.8, @"recoil_y": @0.7,
                @"aim_speed": @1.0, @"fov_scale": @0.7,
                @"auto_fire": @NO, @"aim_assist": @YES,
                @"no_recoil": @YES, @"wallhack": @YES, @"esp": @YES,
                @"aim_bone": @"head", @"aim_fov": @10.0, @"aim_smooth": @0.85,
            },
            @"DEagle": @{
                @"display": @"Desert Eagle", @"category": @5, @"ammo": @4, // .45
                @"mag": @7, @"fire_rate": @300.0, @"damage": @72.0, @"range": @40.0,
                @"recoil_x": @1.5, @"recoil_y": @1.3,
                @"aim_speed": @0.8, @"fov_scale": @1.0,
                @"auto_fire": @NO, @"aim_assist": @NO,
                @"no_recoil": @YES, @"wallhack": @YES, @"esp": @YES,
                @"aim_bone": @"head", @"aim_fov": @6.0, @"aim_smooth": @0.9,
            },

            // === DMRs ===
            @"SKS": @{
                @"display": @"SKS", @"category": @6, @"ammo": @1, // 7.62
                @"mag": @10, @"fire_rate": @250.0, @"damage": @62.0, @"range": @120.0,
                @"recoil_x": @1.0, @"recoil_y": @0.8,
                @"aim_speed": @0.6, @"fov_scale": @1.5,
                @"auto_fire": @NO, @"aim_assist": @YES,
                @"no_recoil": @YES, @"wallhack": @YES, @"esp": @YES,
                @"aim_bone": @"head", @"aim_fov": @4.5, @"aim_smooth": @0.9,
            },
            @"MK14": @{
                @"display": @"MK14 EBR", @"category": @6, @"ammo": @1, // 7.62
                @"mag": @10, @"fire_rate": @300.0, @"damage": @65.0, @"range": @130.0,
                @"recoil_x": @1.1, @"recoil_y": @0.9,
                @"aim_speed": @0.6, @"fov_scale": @1.5,
                @"auto_fire": @YES, @"aim_assist": @YES,
                @"no_recoil": @YES, @"wallhack": @YES, @"esp": @YES,
                @"aim_bone": @"head", @"aim_fov": @4.0, @"aim_smooth": @0.88,
            },
            @"M110": @{
                @"display": @"M110", @"category": @6, @"ammo": @1, // 7.62
                @"mag": @10, @"fire_rate": @240.0, @"damage": @68.0, @"range": @140.0,
                @"recoil_x": @1.2, @"recoil_y": @1.0,
                @"aim_speed": @0.5, @"fov_scale": @1.8,
                @"auto_fire": @NO, @"aim_assist": @YES,
                @"no_recoil": @YES, @"wallhack": @YES, @"esp": @YES,
                @"aim_bone": @"head", @"aim_fov": @3.5, @"aim_smooth": @0.92,
            },

            // === Heavy / Special ===
            @"ASH-12": @{
                @"display": @"ASH-12", @"category": @0, @"ammo": @6, // 12.7
                @"mag": @10, @"fire_rate": @500.0, @"damage": @85.0, @"range": @60.0,
                @"recoil_x": @1.0, @"recoil_y": @0.8,
                @"aim_speed": @0.7, @"fov_scale": @1.0,
                @"auto_fire": @YES, @"aim_assist": @YES,
                @"no_recoil": @YES, @"wallhack": @YES, @"esp": @YES,
                @"aim_bone": @"head", @"aim_fov": @7.0, @"aim_smooth": @0.75,
            },
            @"M7": @{
                @"display": @"M7", @"category": @0, @"ammo": @0, // 5.56
                @"mag": @30, @"fire_rate": @680.0, @"damage": @40.0, @"range": @78.0,
                @"recoil_x": @0.7, @"recoil_y": @0.5,
                @"aim_speed": @0.9, @"fov_scale": @1.0,
                @"auto_fire": @YES, @"aim_assist": @YES,
                @"no_recoil": @YES, @"wallhack": @YES, @"esp": @YES,
                @"aim_bone": @"head", @"aim_fov": @5.5, @"aim_smooth": @0.85,
            },
        };

        // Weapon skins (matching 太阳神 skin data: MS24SkinWeapon-Epic/Legendary)
        self.skinsData = @[
            @{@"weapon": @"M4A1",   @"name": @"M4A1-Predator",      @"rarity": @"Legendary", @"season": @"S1"},
            @{@"weapon": @"M4A1",   @"name": @"M4A1-Ice Dragon",    @"rarity": @"Epic",      @"season": @"S2"},
            @{@"weapon": @"K416",   @"name": @"K416-Shadow Ops",    @"rarity": @"Epic",      @"season": @"S1"},
            @{@"weapon": @"K416",   @"name": @"K416-Crimson Elite", @"rarity": @"Legendary", @"season": @"S3"},
            @{@"weapon": @"AKM",    @"name": @"AKM-Golden Caliph",  @"rarity": @"Legendary", @"season": @"S1"},
            @{@"weapon": @"AKM",    @"name": @"AKM-War Paint",      @"rarity": @"Rare",      @"season": @"S2"},
            @{@"weapon": @"AUG",    @"name": @"AUG-Urban Assault",  @"rarity": @"Epic",      @"season": @"S2"},
            @{@"weapon": @"AWM",    @"name": @"AWM-Ghost",          @"rarity": @"Legendary", @"season": @"S1"},
            @{@"weapon": @"AWM",    @"name": @"AWM-Arctic Wolf",    @"rarity": @"Epic",      @"season": @"S3"},
            @{@"weapon": @"AX50",   @"name": @"AX50-Reaper",        @"rarity": @"Legendary", @"season": @"S2"},
            @{@"weapon": @"MP5",    @"name": @"MP5-Sub Zero",       @"rarity": @"Epic",      @"season": @"S1"},
            @{@"weapon": @"DEagle", @"name": @"DEagle-Inferno",     @"rarity": @"Epic",      @"season": @"S2"},
            @{@"weapon": @"M249",   @"name": @"M249-Tank Buster",   @"rarity": @"Rare",      @"season": @"S1"},
            @{@"weapon": @"PKM",    @"name": @"PKM-Juggernaut",     @"rarity": @"Epic",      @"season": @"S3"},
            @{@"weapon": @"M16A4",  @"name": @"M16A4-Tactical",     @"rarity": @"Rare",      @"season": @"S1"},
            @{@"weapon": @"M24",    @"name": @"M24-Phantom",        @"rarity": @"Epic",      @"season": @"S2"},
            @{@"weapon": @"SC17",   @"name": @"SC17-Nightfall",     @"rarity": @"Epic",      @"season": @"S3"},
            @{@"weapon": @"SKS",    @"name": @"SKS-Marksman",       @"rarity": @"Rare",      @"season": @"S1"},
            @{@"weapon": @"MK14",   @"name": @"MK14-Bullet Storm",  @"rarity": @"Epic",      @"season": @"S2"},
            @{@"weapon": @"VECTOR", @"name": @"Vector-Venom",       @"rarity": @"Legendary", @"season": @"S3"},
        ];

        _currentConfig = [self configForWeapon:@"M4A1"];
    }
    return self;
}

- (NSArray<WeaponSkin *> *)skinsForWeapon:(NSString *)weaponName {
    NSMutableArray *result = [NSMutableArray array];
    for (NSDictionary *sd in self.skinsData) {
        if ([sd[@"weapon"] isEqualToString:weaponName]) {
            WeaponSkin *skin = [[WeaponSkin alloc] init];
            skin.name = sd[@"name"];
            skin.rarity = sd[@"rarity"];
            skin.season = sd[@"season"];
            [result addObject:skin];
        }
    }
    return result;
}

- (WeaponConfig *)configForWeapon:(NSString *)weaponName {
    NSDictionary *data = self.configs[weaponName];
    if (!data) return nil;

    WeaponConfig *config = [[WeaponConfig alloc] init];
    config.name = weaponName;
    config.displayName = data[@"display"];
    config.category = [data[@"category"] integerValue];
    config.ammoType = [data[@"ammo"] integerValue];
    config.magazineSize = [data[@"mag"] intValue];
    config.fireRate = [data[@"fire_rate"] floatValue];
    config.damagePerShot = [data[@"damage"] floatValue];
    config.rangeMeters = [data[@"range"] floatValue];
    config.recoilCompensationX = [data[@"recoil_x"] doubleValue];
    config.recoilCompensationY = [data[@"recoil_y"] doubleValue];
    config.aimSpeed = [data[@"aim_speed"] doubleValue];
    config.fovScale = [data[@"fov_scale"] doubleValue];
    config.autoFire = [data[@"auto_fire"] boolValue];
    config.aimAssist = [data[@"aim_assist"] boolValue];
    config.noRecoil = [data[@"no_recoil"] boolValue];
    config.wallhack = [data[@"wallhack"] boolValue];
    config.esp = [data[@"esp"] boolValue];
    config.aimBone = data[@"aim_bone"];
    config.aimFov = [data[@"aim_fov"] floatValue];
    config.aimSmooth = [data[@"aim_smooth"] floatValue];
    config.skins = [self skinsForWeapon:weaponName];

    return config;
}

- (void)applyConfigForWeapon:(NSString *)weaponName {
    WeaponConfig *config = [self configForWeapon:weaponName];
    if (!config) return;

    _currentConfig = config;

    [[NSNotificationCenter defaultCenter] postNotificationName:@"WeaponConfigChanged"
                                                        object:config];

    NSLog(@"[Weapon] %@ | %.1f dmg | %drnd | %.0f RPM | recoil=%.1f/%.1f",
          config.displayName, config.damagePerShot, config.magazineSize,
          config.fireRate, config.recoilCompensationX, config.recoilCompensationY);
}

- (NSArray<NSString *> *)allWeaponNames {
    return [self.configs.allKeys sortedArrayUsingSelector:@selector(compare:)];
}

- (NSArray<NSString *> *)weaponNamesForCategory:(WeaponCategory)category {
    NSMutableArray *result = [NSMutableArray array];
    for (NSString *key in self.configs) {
        NSDictionary *data = self.configs[key];
        if ([data[@"category"] integerValue] == category) {
            [result addObject:key];
        }
    }
    return [result sortedArrayUsingSelector:@selector(compare:)];
}

@end

@implementation WeaponConfig
@end
