// WeaponConfig.h — Expanded weapon configuration system
// Matches 太阳神 full weapon database: 12 weapons with skins, ammo, categories

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, WeaponCategory) {
    WeaponCategoryAssaultRifle = 0,
    WeaponCategorySMG,
    WeaponCategorySniper,
    WeaponCategoryShotgun,
    WeaponCategoryLMG,
    WeaponCategoryPistol,
    WeaponCategoryDMR,
};

typedef NS_ENUM(NSInteger, AmmoType) {
    AmmoType556 = 0,
    AmmoType762,
    AmmoType545,
    AmmoType92,
    AmmoType45,
    AmmoType50BMG,
    AmmoType127,
    AmmoType9mm,
    AmmoType57,
    AmmoType46,
    AmmoType300,
    AmmoType338,
};

@interface WeaponSkin : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *rarity; // Common, Rare, Epic, Legendary
@property (nonatomic, copy) NSString *season;
@end

@interface WeaponConfig : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, assign) WeaponCategory category;
@property (nonatomic, assign) AmmoType ammoType;
@property (nonatomic, assign) int magazineSize;
@property (nonatomic, assign) float fireRate;
@property (nonatomic, assign) float damagePerShot;
@property (nonatomic, assign) float rangeMeters;
@property (nonatomic, assign) double recoilCompensationX;
@property (nonatomic, assign) double recoilCompensationY;
@property (nonatomic, assign) double aimSpeed;
@property (nonatomic, assign) double fovScale;
@property (nonatomic, assign) BOOL autoFire;
@property (nonatomic, assign) BOOL aimAssist;
@property (nonatomic, assign) BOOL noRecoil;
@property (nonatomic, assign) BOOL wallhack;
@property (nonatomic, assign) BOOL esp;
@property (nonatomic, copy) NSString *aimBone;
@property (nonatomic, assign) float aimFov;
@property (nonatomic, assign) float aimSmooth;
@property (nonatomic, strong) NSArray<WeaponSkin *> *skins;
@end

@interface WeaponConfigManager : NSObject
@property (nonatomic, strong) WeaponConfig *currentConfig;

+ (instancetype)shared;
- (WeaponConfig *)configForWeapon:(NSString *)weaponName;
- (void)applyConfigForWeapon:(NSString *)weaponName;
- (NSArray<NSString *> *)allWeaponNames;
- (NSArray<NSString *> *)weaponNamesForCategory:(WeaponCategory)category;

@end
