// DeviceInfo - 设备信息采集器
// 通过 XPF 内核接口 + 游戏内存读取
// 更新 FPS, Ping, 玩家数量, 武器, 状态等

#import "DeviceInfo.h"
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
    
    // 读取游戏 FPS (通常在渲染模块)
    float fps = 0;
    kern_reading(gameTask, 0x100EE9000, &fps, sizeof(float));
    
    // 读取网络延迟
    float ping = 0;
    kern_reading(gameTask, 0x100EEA000, &ping, sizeof(float));
    
    // 读取武器名
    char weapon[64] = {0};
    kern_reading(gameTask, g_game_offsets.weapon_offset, weapon, 64);
    
    // 更新数据
    _currentInfo.fps = fps > 0 ? fps : 60.0;
    _currentInfo.ping = ping;
    const char *weaponStr = [NSString stringWithUTF8String:weapon] ? [NSString stringWithUTF8String:weapon].UTF8String : "Unknown";
    strncpy(_currentInfo.currentWeapon, weaponStr, 63);
    _currentInfo.currentWeapon[63] = '\0';
    
    // 玩家数量通过 ESP 更新
}

@end
