#ifndef DEVICE_INFO_H
#define DEVICE_INFO_H

#import <Foundation/Foundation.h>
#import <mach/mach.h>

typedef struct {
    float fps;
    float ping;
    int playerCount;
    char currentWeapon[64];
    BOOL cheatActive;
} DeviceInfoData;

@interface DeviceInfo : NSObject
@property (nonatomic) DeviceInfoData currentInfo;

+ (instancetype)shared;
- (void)updateFromGameMemory:(mach_port_t)gameTask;
@end
#endif
