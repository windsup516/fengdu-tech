// DeviceInfo - 设备信息采集器
// 通过 XPF 内核接口 + 游戏内存读取
// 更新 FPS, Ping, 玩家数量, 武器, 状态等

#import "DeviceInfo.h"
#import "GameHooks.h"
#import "XPFKernelInterface.h"

@implementation DeviceInfo

+ (instancetype)shared {
    static DeviceInfo *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[DeviceInfo alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        DeviceInfoData info = {0};
        info.fps = 60.0;
        info.ping = 0.0;
        info.playerCount = 0;
        strcpy(info.currentWeapon, "--");
        info.cheatActive = NO;
        _currentInfo = info;
    }
    return self;
}

- (void)updateFromGameMemory:(mach_port_t)gameTask {
    if (gameTask == MACH_PORT_NULL) return;

    float fps = 0;
    size_t fps_sz = sizeof(fps);
    kern_reading(gameTask, 0x100EE9000, &fps, &fps_sz);

    float ping = 0;
    size_t ping_sz = sizeof(ping);
    kern_reading(gameTask, 0x100EEA000, &ping, &ping_sz);

    char weapon[64] = {0};
    size_t wpn_sz = 64;
    kern_reading(gameTask, g_game_offsets.weapon_offset, weapon, &wpn_sz);

    _currentInfo.fps = fps > 0 ? fps : 60.0f;
    _currentInfo.ping = ping;

    NSString *weaponStr = [NSString stringWithUTF8String:weapon];
    const char *cweapon = weaponStr ? weaponStr.UTF8String : "Unknown";
    strncpy(_currentInfo.currentWeapon, cweapon, 63);
    _currentInfo.currentWeapon[63] = '\0';
}

@end
