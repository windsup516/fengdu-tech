#ifndef ESP_OVERLAY_H
#define ESP_OVERLAY_H

#import <Foundation/Foundation.h>
#import <mach/mach.h>

#define MAX_ENTITIES 64

typedef struct {
    float position[3];
    float health;
    int team;
    uint32_t visible;
    char name[64];
    float head_y;
    BOOL is_valid;
} EntityData;

@interface ESPOverlay : NSObject

+ (instancetype)shared;
- (void)updateEntitiesFromGameMemory:(mach_port_t)gameTask;
- (void)renderESPWithViewMatrix:(float *)viewMatrix 
                    projectMatrix:(float *)projectMatrix
                           width:(float)screenW 
                          height:(float)screenH;
- (BOOL)worldToScreen:(float *)worldPos viewMatrix:(float *)viewMatrix 
          projectMatrix:(float *)projectMatrix 
                  width:(float)width height:(float)height 
                    out:(float *)screenPos;

@end
#endif
