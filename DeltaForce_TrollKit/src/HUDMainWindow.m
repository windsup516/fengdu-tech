// HUDMainWindow - 作弊菜单覆盖层窗口 (UIWindow 子类)
// 反编译: 0x100007480 -[HUDMainWindow initWithFrame:] (212 bytes)
//        0x100007554 +[HUDMainWindow _isSystemWindow]   (8 bytes)
//        0x100007564 -[HUDMainWindow _ignoresHitTest]    (8 bytes)
//        0x10000756C -[HUDMainWindow _isSecure]          (8 bytes)
//
// 重写系统方法将窗口伪装为系统窗口，规避游戏反作弊检测

#import "HUDMainWindow.h"

@implementation HUDMainWindow

+ (BOOL)_isSystemWindow {
    return YES;
}

+ (BOOL)_isWindowServerHostingManaged {
    return YES;
}

- (BOOL)_ignoresHitTest {
    return YES;
}

- (BOOL)_isSecure {
    return YES;
}

- (BOOL)_shouldCreateContextAsSecure {
    return YES;
}

@end
