#ifndef ESP_OVERLAY_H
#define ESP_OVERLAY_H

#import <Foundation/Foundation.h>
#import <mach/mach.h>

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
