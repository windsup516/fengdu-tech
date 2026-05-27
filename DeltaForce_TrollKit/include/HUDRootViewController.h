#ifndef HUD_ROOT_VIEW_CONTROLLER_H
#define HUD_ROOT_VIEW_CONTROLLER_H

#import <UIKit/UIKit.h>

@interface HUDRootViewController : UIViewController
- (void)renderFrame:(CADisplayLink *)displayLink;
- (void)loadImGui;
- (void)prepareForEntryAnimation;
- (void)syncCurrentOrientation;
- (void)handleSenderID:(uint64_t)senderID;
@end
#endif
