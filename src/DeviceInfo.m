// DeviceInfo - 设备信息采集器 (TrollStore 兼容)
// 使用 GameHooks 读取游戏内存

#import "DeviceInfo.h"
#import "GameHooks.h"
#import "ESPOverlay.h"
#import "XPFKernelInterface.h"

@implementation DeviceInfo

+ (instancetype)shared {
    static DeviceInfo *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ shared = [[DeviceInfo alloc] init]; });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        DeviceInfoData info = {0};
        info.fps = 60.0f;
        info.ping = 0.0f;
        info.playerCount = 0;
        strcpy(info.currentWeapon, "--");
        info.cheatActive = NO;
        _currentInfo = info;
    }
    return self;
}

- (void)updateFromGameMemory:(mach_port_t)gameTask {
    if (gameTask == MACH_PORT_NULL) return;

    // 更新玩家数量
    int playerCount = [[ESPOverlay shared] entityCount];
    _currentInfo.playerCount = playerCount;

    _currentInfo.cheatActive = hooks_is_attached();
}

@end
