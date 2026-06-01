// HIDEventManager - IOHIDEventSystemClient 管理
// 完全匹配原版反编译流程:
// 1. registerEventCallback → dispatch_once
// 2. sub_10000A7E8: dlopen("IOKit.framework/IOKit") → dlsym("IOHIDEventSystemClientRegisterEventCallback")
// 3. 注册 sub_100007154 作为 HID 事件回调
// 4. sub_100007154: 将 HID 事件转换为 UIGestureRepresentation 对象
//    存储触摸状态到全局变量 (g_touchActive / g_touchX / g_touchY)

#import "HIDEventManager.h"
#import <IOKit/hid/IOHIDEventSystemClient.h>
#import <IOKit/hid/IOHIDEvent.h>
#import <mach/mach_time.h>
#import <dlfcn.h>
#import <objc/runtime.h>

// === 全局触摸状态 (对应原版反编译全局变量) ===
// byte_10139CB60 — 触摸激活标志 (0=触摸中, 1=未触摸)
uint8_t g_touchActive = 1;
// dword_10139CB68 — 触摸 X 坐标
float g_touchX = 0.0f;
// dword_10139CB70 — 触摸 Y 坐标
float g_touchY = 0.0f;

// dispatch_once 令牌 (qword_10139CBB8)
static dispatch_once_t g_hidOnceToken;

// IOHIDEventSystemClient 函数签名
typedef IOHIDEventSystemClientRef (*IOHIDEventSystemClientCreate_t)(CFAllocatorRef allocator);
typedef void (*IOHIDEventSystemClientRegisterEventCallback_t)(
    IOHIDEventSystemClientRef client,
    void (*callback)(void *target, void *refcon, void *service, IOHIDEventRef event),
    void *target,
    void *refcon);
typedef void (*IOHIDEventSystemClientScheduleWithRunLoop_t)(
    IOHIDEventSystemClientRef client,
    CFRunLoopRef runLoop,
    CFStringRef mode);

@interface HIDEventManager ()
@property (nonatomic) IOHIDEventSystemClientRef hidClient;
@property (nonatomic) BOOL registered;
@end

@implementation HIDEventManager

+ (instancetype)shared {
    static HIDEventManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[HIDEventManager alloc] init];
    });
    return shared;
}

// ====== 原版 sub_100007154 — HID 事件回调处理 ======
// 将 HID 事件转换为 UIGestureRepresentation 对象
// 提取触摸坐标并存入全局变量
static void onHIDEvent(void *target, void *refcon, void *service, IOHIDEventRef event) {
    @autoreleasepool {
        // dispatch_once 初始化 UIGestureRepresentation 对象 (原版: qword_10139CB78)
        static id gRepresentation = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            // UIGestureRepresentation 是私有类, 用于将 HID 事件转为手势表示
            Class repClass = NSClassFromString(@"UIGestureRepresentation");
            if (!repClass) {
                // iOS 16+ 可能是 UIHIDEventRepresentation
                repClass = NSClassFromString(@"UIHIDEventRepresentation");
            }
            if (repClass) {
                gRepresentation = [[repClass alloc] init];
            }
        });

        if (!gRepresentation) return;

        // representationWithHIDEvent:hidStreamIdentifier:
        SEL repSel = NSSelectorFromString(@"representationWithHIDEvent:hidStreamIdentifier:");
        id rep = nil;
        if ([gRepresentation respondsToSelector:repSel]) {
            IMP imp = [gRepresentation methodForSelector:repSel];
            id (*func)(id, SEL, IOHIDEventRef, uint64_t) = (void *)imp;
            rep = func(gRepresentation, repSel, event, 0);
        }

        if (!rep) return;

        // 获取触摸位置
        CGPoint location = CGPointZero;
        if ([rep respondsToSelector:@selector(location)]) {
            location = [rep location];
        }

        // 检测触摸阶段 (isLift / isInRange / isInRangeLift / isCancel)
        BOOL isLift = NO;
        if ([rep respondsToSelector:@selector(isLift)]) {
            isLift = [rep isLift];
        }
        BOOL isInRange = NO;
        if ([rep respondsToSelector:@selector(isInRange)]) {
            isInRange = [rep isInRange];
        }
        BOOL isInRangeLift = NO;
        if ([rep respondsToSelector:@selector(isInRangeLift)]) {
            isInRangeLift = [rep isInRangeLift];
        }
        BOOL isCancel = NO;
        if ([rep respondsToSelector:@selector(isCancel)]) {
            isCancel = [rep isCancel];
        }

        // 触摸激活判断: lift/inRange/inRangeLift/cancel 均为 NO 时表示触摸中
        uint8_t active = (isLift || isInRange || isInRangeLift) ? 1 : (!isCancel ? 0 : 1);

        // 只在有实际位置时更新状态
        if (location.x != 0.0f || location.y != 0.0f) {
            g_touchActive = active;
            g_touchX = (float)location.x;
            g_touchY = (float)location.y;
        }
    }
}

// ====== 原版 sub_10000A7E8 — 动态加载 IOKit 并注册 HID 回调 ======
// 通过 dlopen + dlsym 动态加载, 避免静态链接被符号扫描检测
static void registerHIDCallbackInternal(void) {
    // 原版: 解密 IOKit 框架路径字符串 (xmmword_10134D0D0)
    // 简化为直接使用已知路径
    void *handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY);
    if (!handle) {
        NSLog(@"[HID] dlopen IOKit failed");
        return;
    }

    // 原版: 解密 "IOHIDEventSystemClientRegisterEventCallback" (xmmword_10134D050)
    IOHIDEventSystemClientRegisterEventCallback_t registerCallback =
        (IOHIDEventSystemClientRegisterEventCallback_t)dlsym(
            handle, "IOHIDEventSystemClientRegisterEventCallback");

    if (!registerCallback) {
        NSLog(@"[HID] dlsym IOHIDEventSystemClientRegisterEventCallback failed");
        dlclose(handle);
        return;
    }

    // 创建 HID 客户端
    IOHIDEventSystemClientRef client = NULL;
    IOHIDEventSystemClientCreate_t createClient =
        (IOHIDEventSystemClientCreate_t)dlsym(handle, "IOHIDEventSystemClientCreate");
    if (createClient) {
        client = createClient(kCFAllocatorDefault);
    }

    if (client) {
        // 注册回调 (onHIDEvent = 原版 sub_100007154)
        registerCallback(client, onHIDEvent, NULL, NULL);

        // 调度到当前 run loop
        IOHIDEventSystemClientScheduleWithRunLoop_t scheduleClient =
            (IOHIDEventSystemClientScheduleWithRunLoop_t)dlsym(
                handle, "IOHIDEventSystemClientScheduleWithRunLoop");
        if (scheduleClient) {
            scheduleClient(client, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
        }

        // 保存客户端引用
        [HIDEventManager shared].hidClient = client;
        [HIDEventManager shared].registered = YES;

        NSLog(@"[HID] Callback registered via dlopen+dlsym (anti-static-analysis)");
    }

    dlclose(handle);
}

- (void)registerEventCallback {
    // 原版: dispatch_once(&qword_10139CBB8, &stru_10016CC30)
    // stru_10016CC30 的 invoke 函数 = sub_10000A7E8
    dispatch_once(&g_hidOnceToken, ^{
        registerHIDCallbackInternal();
    });
}

- (void)enqueueEvent:(IOHIDEventRef)event {
    // 原版不使用事件队列 — 回调直接更新全局变量
    // 保留此方法用于兼容
}

- (IOHIDEventRef)getNextEvent {
    // 原版不使用事件队列 — TouchMainWindow 直接从全局变量读取
    return NULL;
}

#pragma mark - 触摸事件注入

- (void)sendTouchAtPoint:(CGPoint)point phase:(int)phase {
    // 保留触摸注入功能
}

- (void)sendMouseButtonDown {
    // 保留
}

- (void)sendMouseButtonUp {
    // 保留
}

@end
