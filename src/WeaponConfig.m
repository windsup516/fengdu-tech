// WeaponConfig - 武器配置文件
// 基于反编译 flavorSelector 的武器预设系统
// 每种武器有独立的后坐力/弹道/自瞄参数

#import "WeaponConfig.h"

@interface WeaponConfigManager ()
@property (nonatomic, strong) NSDictionary *configs;
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
        // 从反编译恢复的武器配置
        self.configs = @{
            @"AKM": @{
                @"recoil_x": @0.8, @"recoil_y": @0.6,
                @"aim_speed": @0.9, @"fov_scale": @1.0,
                @"auto_fire": @YES, @"aim_assist": @YES,
                @"no_recoil": @YES, @"wallhack": @YES, @"esp": @YES,
                @"aim_bone": @"head", @"aim_fov": @6.0,
                @"aim_smooth": @0.85,
            },
            @"QBZ95-1": @{
                @"recoil_x": @0.6, @"recoil_y": @0.4,
                @"aim_speed": @0.8, @"fov_scale": @1.0,
                @"auto_fire": @YES, @"aim_assist": @YES,
                @"no_recoil": @YES, @"wallhack": @YES, @"esp": @YES,
                @"aim_bone": @"head", @"aim_fov": @5.0,
                @"aim_smooth": @0.9,
            },
            @"QBZ-17": @{
                @"recoil_x": @0.7, @"recoil_y": @0.5,
                @"aim_speed": @0.8, @"fov_scale": @1.0,
                @"auto_fire": @YES, @"aim_assist": @YES,
                @"no_recoil": @YES, @"wallhack": @YES, @"esp": @YES,
                @"aim_bone": @"head", @"aim_fov": @5.5,
                @"aim_smooth": @0.88,
            },
            @"AKS-74U": @{
                @"recoil_x": @0.9, @"recoil_y": @0.7,
                @"aim_speed": @0.9, @"fov_scale": @1.0,
                @"auto_fire": @YES, @"aim_assist": @YES,
                @"no_recoil": @YES, @"wallhack": @YES, @"esp": @YES,
                @"aim_bone": @"head", @"aim_fov": @6.5,
                @"aim_smooth": @0.8,
            },
            @"ASH-12": @{
                @"recoil_x": @1.0, @"recoil_y": @0.8,
                @"aim_speed": @0.7, @"fov_scale": @1.0,
                @"auto_fire": @YES, @"aim_assist": @YES,
                @"no_recoil": @YES, @"wallhack": @YES, @"esp": @YES,
                @"aim_bone": @"head", @"aim_fov": @7.0,
                @"aim_smooth": @0.75,
            },
            @"M16A4": @{
                @"recoil_x": @0.5, @"recoil_y": @0.3,
                @"aim_speed": @0.8, @"fov_scale": @1.0,
                @"auto_fire": @NO, @"aim_assist": @YES,
                @"no_recoil": @YES, @"wallhack": @YES, @"esp": @YES,
                @"aim_bone": @"head", @"aim_fov": @4.5,
                @"aim_smooth": @0.92,
            },
            @"M4A1": @{
                @"recoil_x": @0.5, @"recoil_y": @0.3,
                @"aim_speed": @0.9, @"fov_scale": @1.0,
                @"auto_fire": @YES, @"aim_assist": @YES,
                @"no_recoil": @YES, @"wallhack": @YES, @"esp": @YES,
                @"aim_bone": @"head", @"aim_fov": @5.0,
                @"aim_smooth": @0.9,
            },
            @"K416": @{
                @"recoil_x": @0.5, @"recoil_y": @0.4,
                @"aim_speed": @0.9, @"fov_scale": @1.0,
                @"auto_fire": @YES, @"aim_assist": @YES,
                @"no_recoil": @YES, @"wallhack": @YES, @"esp": @YES,
                @"aim_bone": @"head", @"aim_fov": @5.0,
                @"aim_smooth": @0.9,
            },
            @"AUG": @{
                @"recoil_x": @0.4, @"recoil_y": @0.3,
                @"aim_speed": @0.8, @"fov_scale": @1.0,
                @"auto_fire": @YES, @"aim_assist": @YES,
                @"no_recoil": @YES, @"wallhack": @YES, @"esp": @YES,
                @"aim_bone": @"head", @"aim_fov": @4.0,
                @"aim_smooth": @0.93,
            },
            @"M7": @{
                @"recoil_x": @0.7, @"recoil_y": @0.5,
                @"aim_speed": @0.9, @"fov_scale": @1.0,
                @"auto_fire": @YES, @"aim_assist": @YES,
                @"no_recoil": @YES, @"wallhack": @YES, @"esp": @YES,
                @"aim_bone": @"head", @"aim_fov": @5.5,
                @"aim_smooth": @0.85,
            },
            @"SC17": @{
                @"recoil_x": @0.6, @"recoil_y": @0.5,
                @"aim_speed": @0.9, @"fov_scale": @1.0,
                @"auto_fire": @YES, @"aim_assist": @YES,
                @"no_recoil": @YES, @"wallhack": @YES, @"esp": @YES,
                @"aim_bone": @"head", @"aim_fov": @5.0,
                @"aim_smooth": @0.88,
            },
            @"97M": @{
                @"recoil_x": @0.7, @"recoil_y": @0.5,
                @"aim_speed": @0.8, @"fov_scale": @1.0,
                @"auto_fire": @YES, @"aim_assist": @YES,
                @"no_recoil": @YES, @"wallhack": @YES, @"esp": @YES,
                @"aim_bone": @"head", @"aim_fov": @5.5,
                @"aim_smooth": @0.85,
            },
        };
        
        _currentConfig = [self configForWeapon:@"M4A1"];
    }
    return self;
}

- (WeaponConfig *)configForWeapon:(NSString *)weaponName {
    NSDictionary *data = self.configs[weaponName];
    if (!data) return nil;
    
    WeaponConfig *config = [[WeaponConfig alloc] init];
    config.name = weaponName;
    config.displayName = weaponName;
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
    
    return config;
}

- (void)applyConfigForWeapon:(NSString *)weaponName {
    WeaponConfig *config = [self configForWeapon:weaponName];
    if (!config) return;
    
    _currentConfig = config;
    
    // 通过 GameHooks 应用配置
    [[NSNotificationCenter defaultCenter] postNotificationName:@"WeaponConfigChanged" 
                                                        object:config];
    
    NSLog(@"[Weapon] Applied config: %@ (recoil=%.1f/%.1f, aim=%.1f, fov=%.1f)",
          config.name, config.recoilCompensationX, config.recoilCompensationY,
          config.aimSpeed, config.fovScale);
}

@end

@implementation WeaponConfig
@end
