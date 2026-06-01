// HUDMainWindow - 作弊菜单覆盖层窗口 (UIWindow 子类)
// 反编译: 0x100007480 -[HUDMainWindow initWithFrame:] (212 bytes)
//        0x100007554 +[HUDMainWindow _isSystemWindow]   (8 bytes)
//        0x100007564 -[HUDMainWindow _ignoresHitTest]    (8 bytes)
//        0x10000756C -[HUDMainWindow _isSecure]          (8 bytes)
//
// 重写系统方法将窗口伪装为系统窗口，规避游戏反作弊检测
//
// 原版初始化流程:
//   _initWithFrame:attached: (UIWindow 私有初始化器)
//   → commonInit (自定义配置)
//   两步初始化匹配原版反编译

#import "HUDMainWindow.h"

@implementation HUDMainWindow

- (instancetype)initWithFrame:(CGRect)frame {
    // 太阳神使用 _initWithFrame:attached: (UIWindow 私有方法)
    // attached:NO 使窗口独立于主应用的窗口服务器连接
    // 这对于 SBS 托管至关重要
    SEL privateInitSel = NSSelectorFromString(@"_initWithFrame:attached:");
    if ([self respondsToSelector:privateInitSel]) {
        // 使用 NSInvocation 调用带 CGRect 参数的私有方法
        NSMethodSignature *sig = [self methodSignatureForSelector:privateInitSel];
        if (sig) {
            NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
            [inv setTarget:self];
            [inv setSelector:privateInitSel];
            // _initWithFrame:attached: 第二个参数是 BOOL attached
            BOOL attached = NO;
            [inv setArgument:&frame atIndex:2];
            [inv setArgument:&attached atIndex:3];
            [inv invoke];
            [self commonInit];
            return self;
        }
    }

    // Fallback: 标准初始化
    self = [super initWithFrame:frame];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (void)commonInit {
    // 原版 commonInit: 设置窗口基础属性
    // 对应反编译中 commonInit 方法的配置
    self.backgroundColor = [UIColor clearColor];
    self.opaque = NO;
    self.userInteractionEnabled = YES;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
}

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
