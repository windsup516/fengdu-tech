#ifndef HUD_CONTROLLER_H
#define HUD_CONTROLLER_H

#import <UIKit/UIKit.h>

@class TouchMainWindow, HUDRootViewController, TouchViewController;

@interface HUDController : NSObject

@property (nonatomic, strong) UIWindow *hudWindow;
@property (nonatomic, strong) TouchMainWindow *touchWindow;
@property (nonatomic, strong) HUDRootViewController *rootVC;
@property (nonatomic, strong) TouchViewController *touchVC;
@property (nonatomic, strong) id hostingController;
@property (nonatomic) BOOL showing;
@property (nonatomic) BOOL windowsCreated;

+ (instancetype)shared;
- (void)show;
- (void)hide;
- (void)createWindowsOnScene:(id)scene;
- (void)registerHIDEventCallback;
- (void)syncTouchWindowToPanel;
- (void)setupHostingController;

@end
#endif
