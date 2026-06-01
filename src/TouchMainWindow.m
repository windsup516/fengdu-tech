// TouchMainWindow - 触摸事件捕获窗口
// 基于反编译: initWithFrame(0x100009320, 608字节) / timerFired:(0x100009608, 384字节)
// timerFired 实际用途: 屏幕旋转/尺寸变化时调整 Background 视图
// 100Hz 轮询 (0.01s) — 匹配原版
// HID 事件处理由 HIDEventManager + sub_100007154 回调完成

#import "TouchMainWindow.h"
#import "HUDRootViewController.h"
#import "HIDEventManager.h"

// 外部全局变量 (来自 HUDRootViewController)
extern float g_screenScale;
extern float g_screenWidth;
extern float g_screenHeight;

// 外部触摸状态全局变量 (来自 HIDEventManager 回调)
extern uint8_t g_touchActive;   // byte_10139CB60
extern float g_touchX;          // dword_10139CB68
extern float g_touchY;          // dword_10139CB70

// 原版全局标志: byte_10139DD44 — 是否使用旋转后的尺寸
static BOOL g_useRotatedSize = NO;

@interface TouchMainWindow ()
@property (nonatomic, strong) NSTimer *pollTimer;
@end

@implementation TouchMainWindow

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];

        // 原版: 创建 Background 视图 (colorWithWhite:0.001 alpha)
        // 不是 clearColor — 极浅白色, 视觉上透明但能拦截触摸
        self.Background = [[UIView alloc] initWithFrame:self.bounds];
        self.Background.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.001];
        [self addSubview:self.Background];

        // 原版: 100Hz 定时器 (0.01s), 不是 60Hz
        self.pollTimer = [NSTimer scheduledTimerWithTimeInterval:0.01
                                                           target:self
                                                         selector:@selector(timerFired:)
                                                         userInfo:nil
                                                          repeats:YES];
    }
    return self;
}

// 原版 timerFired: (0x100009608)
// 实际功能: 根据屏幕状态调整 Background 视图的 frame 和 center
// 不是处理 HID 事件 (HID 处理在 sub_100007154 回调中)
- (void)timerFired:(NSTimer *)timer {
    float scale = g_screenScale;
    if (scale <= 0.0f) scale = 2.0f;

    if (g_useRotatedSize) {
        // 横屏模式: Background view 占据整个像素空间
        float w = g_screenHeight;
        float h = g_screenWidth;
        [self.Background setFrame:CGRectMake(0, 0, w / scale, h / scale)];
    } else {
        // 竖屏模式: Background view 占据全屏
        float w = g_screenWidth;
        float h = g_screenHeight;
        [self.Background setFrame:CGRectMake(0, 0, w / scale, h / scale)];
        [self.Background setCenter:CGPointMake(w / (2.0f * scale), h / (2.0f * scale))];
    }
}

- (BOOL)shouldInterceptTouchAtPoint:(CGPoint)point {
    if (self.hudController.view.window && !self.hudController.view.window.hidden) {
        CGFloat menuX = (self.bounds.size.width - 300) / 2;
        CGFloat menuY = (self.bounds.size.height - 400) / 2;
        CGRect menuRect = CGRectMake(menuX, menuY, 300, 400);
        return CGRectContainsPoint(menuRect, point);
    }
    return NO;
}

// === 系统级窗口伪装标志 ===

+ (BOOL)_isSystemWindow {
    return YES;
}

- (BOOL)_isWindowServerHostingManaged {
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

- (void)dealloc {
    [self.pollTimer invalidate];
}

@end
