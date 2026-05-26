// TouchMainWindow - 触摸事件捕获窗口
// 基于反编译: initWithFrame / timerFired / systemWindow flags
// 位于最高 windowLevel (10000011) 捕获所有触摸
// 通过 IOHIDEventSystemClient 识别游戏触摸

#import "TouchMainWindow.h"
#import "HUDRootViewController.h"
#import "HIDEventManager.h"

@interface TouchMainWindow ()
@property (nonatomic, strong) NSTimer *pollTimer;
@end

@implementation TouchMainWindow

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        // 每 1/60 秒轮询 HID 事件
        // 对应反编译: NSTimer scheduledTimerWithTimeInterval:1.0/60.0
        self.pollTimer = [NSTimer scheduledTimerWithTimeInterval:1.0/60.0
                                                           target:self
                                                         selector:@selector(timerFired:)
                                                         userInfo:nil
                                                          repeats:YES];
        
        // 添加透明背景视图用于触摸轨迹
        self.Background = [[UIView alloc] initWithFrame:self.bounds];
        self.Background.backgroundColor = [UIColor clearColor];
        self.Background.userInteractionEnabled = NO;
        [self addSubview:self.Background];
    }
    return self;
}

- (void)timerFired:(NSTimer *)timer {
    // 从 HID 事件系统获取最新事件
    IOHIDEventRef event = [[HIDEventManager shared] getNextEvent];
    
    if (event) {
        uint64_t senderID = IOHIDEventGetSenderID(event);
        IOHIDEventType type = IOHIDEventGetType(event);
        
        // 识别游戏触摸事件
        if (type == kIOHIDEventTypeDigitizer) {
            // 获取触摸坐标
            CGFloat x = IOHIDEventGetFloatValue(event, kIOHIDEventFieldDigitizerX);
            CGFloat y = IOHIDEventGetFloatValue(event, kIOHIDEventFieldDigitizerY);
            
            // 转发到 HUD 控制器
            [self.hudController handleSenderID:senderID];
            
            // 如果是作用于作弊菜单区域, 拦截事件
            if ([self shouldInterceptTouchAtPoint:CGPointMake(x, y)]) {
                // 阻止事件传递给游戏
                IOHIDEventSetSenderID(event, 0);
            }
        }
    }
}

- (BOOL)shouldInterceptTouchAtPoint:(CGPoint)point {
    // 检查触摸点是否在作弊菜单区域
    // 如果在菜单区域内, 拦截触摸事件
    if (self.hudController.view.window && !self.hudController.view.window.hidden) {
        // 计算菜单区域 (简化: 中间 300x400)
        CGFloat menuX = (self.bounds.size.width - 300) / 2;
        CGFloat menuY = (self.bounds.size.height - 400) / 2;
        CGRect menuRect = CGRectMake(menuX, menuY, 300, 400);
        
        return CGRectContainsPoint(menuRect, point);
    }
    return NO;
}

// === 系统级窗口标志 ===
// 所有返回 YES 是为了隐蔽窗口不被检测

+ (BOOL)_isSystemWindow {
    return YES;  // 伪装成系统窗口 (如 StatusBar)
}

- (BOOL)_isWindowServerHostingManaged {
    return YES;  // 由窗口服务器托管
}

- (BOOL)_ignoresHitTest {
    return YES;  // 忽略点击测试 (但实际通过 HID 捕获)
}

- (BOOL)_isSecure {
    return YES;  // 安全模式 (防止截图)
}

- (BOOL)_shouldCreateContextAsSecure {
    return YES;  // 安全上下文
}

- (void)dealloc {
    [self.pollTimer invalidate];
}

@end
