// TouchMainWindow - 触摸事件捕获窗口
// 基于反编译: initWithFrame(0x100009320, 608字节) / timerFired:(0x100009608, 384字节)
// 位于最高 windowLevel (10000011) 通过 IOHIDEventSystemClient 捕获所有触摸
// 标志伪装为系统窗口 (反检测)

#import "TouchMainWindow.h"
#import "HUDRootViewController.h"
#import "HIDEventManager.h"
#import <dlfcn.h>

// IOHIDEvent 函数指针 (通过 HIDEventManager 动态加载)
// 避免静态链接 IOKit 被检测
static uint64_t (*s_IOHIDEventGetSenderID)(IOHIDEventRef) = NULL;
static IOHIDEventType (*s_IOHIDEventGetType)(IOHIDEventRef) = NULL;
static void (*s_IOHIDEventSetSenderID)(IOHIDEventRef, uint64_t) = NULL;
static CGFloat (*s_IOHIDEventGetFloatValue)(IOHIDEventRef, IOHIDEventField) = NULL;

@interface TouchMainWindow ()
@property (nonatomic, strong) NSTimer *pollTimer;
@end

@implementation TouchMainWindow

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        // 动态加载 IOHIDEvent 函数指针 (一次)
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            void *handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit",
                                  RTLD_LAZY | RTLD_NOLOAD);
            if (!handle) {
                handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit",
                                RTLD_LAZY);
            }
            if (handle) {
                s_IOHIDEventGetSenderID = dlsym(handle, "IOHIDEventGetSenderID");
                s_IOHIDEventGetType     = dlsym(handle, "IOHIDEventGetType");
                s_IOHIDEventSetSenderID = dlsym(handle, "IOHIDEventSetSenderID");
                s_IOHIDEventGetFloatValue = dlsym(handle, "IOHIDEventGetFloatValue");
                dlclose(handle);
            }
        });
        
        // 每 1/60 秒轮询 HID 事件队列
        // 反编译: scheduledTimerWithTimeInterval:1.0/60.0 target:selector:timerFired:
        self.pollTimer = [NSTimer scheduledTimerWithTimeInterval:1.0/60.0
                                                           target:self
                                                         selector:@selector(timerFired:)
                                                         userInfo:nil
                                                          repeats:YES];
        
        // 透明背景视图 (对应反编译: Background view)
        self.Background = [[UIView alloc] initWithFrame:self.bounds];
        self.Background.backgroundColor = [UIColor clearColor];
        self.Background.userInteractionEnabled = NO;
        [self addSubview:self.Background];
    }
    return self;
}

// 反编译: timerFired: 函数地址 0x100009608, 大小 384 字节
// 通过 IOHIDEventSystemClient 轮询 HID 事件
- (void)timerFired:(NSTimer *)timer {
    if (!s_IOHIDEventGetSenderID) return;
    
    // 从 HIDEventManager 的事件队列获取最新 HID 事件
    IOHIDEventRef event = [[HIDEventManager shared] getNextEvent];
    if (!event) return;
    
    // 获取事件的 senderID 和类型
    uint64_t senderID = s_IOHIDEventGetSenderID(event);
    IOHIDEventType type = s_IOHIDEventGetType(event);
    
    // 只处理触摸事件
    if (type == kIOHIDEventTypeDigitizer) {
        // 获取触摸坐标
        CGFloat x = s_IOHIDEventGetFloatValue(event, kIOHIDEventFieldDigitizerX);
        CGFloat y = s_IOHIDEventGetFloatValue(event, kIOHIDEventFieldDigitizerY);
        
        // 转发到 HUD 控制器 (用于判断是否被菜单拦截)
        [self.hudController handleSenderID:senderID];
        
        // 如果触摸点在作弊菜单区域, 拦截事件不传给游戏
        if ([self shouldInterceptTouchAtPoint:CGPointMake(x, y)]) {
            // 设置 senderID = 0 阻止事件传递到游戏进程
            s_IOHIDEventSetSenderID(event, 0);
        }
    }
}

- (BOOL)shouldInterceptTouchAtPoint:(CGPoint)point {
    // 检查作弊菜单是否可见
    if (self.hudController.view.window && !self.hudController.view.window.hidden) {
        // 菜单区域: 屏幕中间 300x400
        CGFloat menuX = (self.bounds.size.width - 300) / 2;
        CGFloat menuY = (self.bounds.size.height - 400) / 2;
        CGRect menuRect = CGRectMake(menuX, menuY, 300, 400);
        return CGRectContainsPoint(menuRect, point);
    }
    return NO;
}

// === 系统级窗口伪装标志 ===
// 所有返回 YES 对应反编译中的 class method / instance method

+ (BOOL)_isSystemWindow {
    // 反编译: +[TouchMainWindow _isSystemWindow] → 0x100009554
    return YES;  // 伪装为系统窗口
}

- (BOOL)_isWindowServerHostingManaged {
    return YES;  // 窗口服务器托管管理
}

- (BOOL)_ignoresHitTest {
    // 反编译: -[TouchMainWindow _ignoresHitTest] → 0x100009564
    return YES;  // 忽略命中测试
}

- (BOOL)_isSecure {
    // 反编译: -[TouchMainWindow _isSecure] → 0x10000956C
    return YES;  // 安全模式 (防截图/录制)
}

- (BOOL)_shouldCreateContextAsSecure {
    return YES;  // 安全渲染上下文
}

- (void)dealloc {
    [self.pollTimer invalidate];
}

@end
