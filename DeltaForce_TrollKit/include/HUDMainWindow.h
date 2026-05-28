#import <UIKit/UIKit.h>

@interface HUDMainWindow : UIWindow

+ (BOOL)_isSystemWindow;
+ (BOOL)_isWindowServerHostingManaged;

@end
