// DFOverlayController — Overlay manager for injected dylib
// Manages Metal+ImGui rendering in game process

#import <Foundation/Foundation.h>

@interface DFOverlayController : NSObject

+ (instancetype)shared;
- (void)startOverlay;
- (void)stopOverlay;

@end
