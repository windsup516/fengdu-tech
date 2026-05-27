#ifndef TOUCH_MAIN_WINDOW_H
#define TOUCH_MAIN_WINDOW_H

#import <UIKit/UIKit.h>

@class HUDRootViewController;

@interface TouchMainWindow : UIWindow
@property (nonatomic, strong) UIView *Background;
@property (nonatomic, weak) HUDRootViewController *hudController;
- (void)timerFired:(NSTimer *)timer;
- (BOOL)shouldInterceptTouchAtPoint:(CGPoint)point;
@end
#endif
