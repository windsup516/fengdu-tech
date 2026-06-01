#ifndef WEAPON_CONFIG_H
#define WEAPON_CONFIG_H

#import <Foundation/Foundation.h>

@interface WeaponConfig : NSObject
@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong) NSString *displayName;

// 后坐力补偿
@property (nonatomic) double recoilCompensationX;
@property (nonatomic) double recoilCompensationY;

// 自瞄参数
@property (nonatomic) double aimSpeed;
@property (nonatomic) double fovScale;
@property (nonatomic) BOOL autoFire;
@property (nonatomic) BOOL aimAssist;

// 作弊功能
@property (nonatomic) BOOL noRecoil;
@property (nonatomic) BOOL wallhack;
@property (nonatomic) BOOL esp;
@property (nonatomic) NSString *aimBone;
@property (nonatomic) float aimFov;
@property (nonatomic) float aimSmooth;
@end

@interface WeaponConfigManager : NSObject
@property (nonatomic, readonly) WeaponConfig *currentConfig;

+ (instancetype)shared;
- (WeaponConfig *)configForWeapon:(NSString *)weaponName;
- (void)applyConfigForWeapon:(NSString *)weaponName;
@end
#endif
