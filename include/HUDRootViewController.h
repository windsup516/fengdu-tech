#ifndef HUD_ROOT_VIEW_CONTROLLER_H
#define HUD_ROOT_VIEW_CONTROLLER_H

#import <UIKit/UIKit.h>

@interface HUDRootViewController : UIViewController

// 渲染方法
- (void)renderFrame:(CADisplayLink *)displayLink;
- (void)loadImGui;
- (void)prepareForEntryAnimation;
- (void)syncCurrentOrientation;
- (void)handleSenderID:(uint64_t)senderID;

// 屏幕尺寸访问器 (供 TouchMainWindow timerFired 使用)
+ (float)screenScale;
+ (float)screenWidth;
+ (float)screenHeight;

@end
#endif
