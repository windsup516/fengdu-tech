// HIDEventManager - IOHIDEventSystemClient 管理
// 对应反编译: registerHIDEventCallback
// 用于捕获/注入触摸事件

#import "HIDEventManager.h"
#import <IOKit/hid/IOHIDEventSystemClient.h>
#import <IOKit/hid/IOHIDEvent.h>
#import <mach/mach_time.h>

// IOHIDEventSystemClient 函数签名
typedef IOHIDEventSystemClientRef (*IOHIDEventSystemClientCreate_t)(CFAllocatorRef allocator);
typedef void (*IOHIDEventSystemClientRegisterEventCallback_t)(
    IOHIDEventSystemClientRef client,
    void (*callback)(void *target, void *refcon, IOHIDServiceRef service, IOHIDEventRef event),
    void *target,
    void *refcon);
typedef void (*IOHIDEventSystemClientScheduleWithRunLoop_t)(
    IOHIDEventSystemClientRef client,
    CFRunLoopRef runLoop,
    CFStringRef mode);

// IOHIDEvent 函数签名
typedef uint64_t (*IOHIDEventGetSenderID_t)(IOHIDEventRef event);
typedef IOHIDEventType (*IOHIDEventGetType_t)(IOHIDEventRef event);
typedef void (*IOHIDEventSetSenderID_t)(IOHIDEventRef event, uint64_t senderID);
typedef CGFloat (*IOHIDEventGetFloatValue_t)(IOHIDEventRef event, IOHIDEventField field);
typedef IOHIDEventRef (*IOHIDEventCreateDigitizerEvent_t)(
    CFAllocatorRef allocator, uint64_t timestamp, uint32_t transducerType,
    uint32_t index, uint32_t identity, uint32_t eventMask,
    uint32_t buttonMask, CGFloat x, CGFloat y, CGFloat z,
    CGFloat tipPressure, CGFloat twist, CGFloat majorRadius,
    CGFloat minorRadius);
typedef void (*IOHIDEventSetIntegerValue_t)(IOHIDEventRef event, IOHIDEventField field, CFIndex value);
typedef void (*IOHIDEventSetFloatValue_t)(IOHIDEventRef event, IOHIDEventField field, CGFloat value);

@interface HIDEventManager ()
@property (nonatomic) IOHIDEventSystemClientRef hidClient;
@property (nonatomic) BOOL registered;
@property (nonatomic, strong) NSMutableArray *eventQueue;
@property (nonatomic) CFMachPortRef eventPort;

// 动态加载的函数指针
@property (nonatomic) IOHIDEventSystemClientCreate_t HIDEventSystemClientCreate;
@property (nonatomic) IOHIDEventSystemClientRegisterEventCallback_t HIDEventSystemClientRegisterEventCallback;
@property (nonatomic) IOHIDEventSystemClientScheduleWithRunLoop_t HIDEventSystemClientScheduleWithRunLoop;
@property (nonatomic) IOHIDEventGetSenderID_t HIDEventGetSenderID;
@property (nonatomic) IOHIDEventGetType_t HIDEventGetType;
@property (nonatomic) IOHIDEventSetSenderID_t HIDEventSetSenderID;
@property (nonatomic) IOHIDEventGetFloatValue_t HIDEventGetFloatValue;
@property (nonatomic) IOHIDEventCreateDigitizerEvent_t HIDEventCreateDigitizerEvent;
@property (nonatomic) IOHIDEventSetIntegerValue_t HIDEventSetIntegerValue;
@property (nonatomic) IOHIDEventSetFloatValue_t HIDEventSetFloatValue;
@end

// 全局 HID 事件回调
static void onHIDEventReceived(void *target, void *refcon, IOHIDServiceRef service, IOHIDEventRef event) {
    @autoreleasepool {
        HIDEventManager *manager = (__bridge HIDEventManager *)target;
        [manager enqueueEvent:event];
    }
}

@implementation HIDEventManager

+ (instancetype)shared {
    static HIDEventManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[HIDEventManager alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        self.eventQueue = [NSMutableArray array];
        [self loadSymbols];
    }
    return self;
}

- (void)loadSymbols {
    // 动态加载 IOKit 符号 (避免静态链接被检测)
    void *handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOLOAD);
    if (!handle) {
        handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY);
    }
    
    if (handle) {
        self.HIDEventSystemClientCreate = dlsym(handle, "IOHIDEventSystemClientCreate");
        self.HIDEventSystemClientRegisterEventCallback = dlsym(handle, "IOHIDEventSystemClientRegisterEventCallback");
        self.HIDEventSystemClientScheduleWithRunLoop = dlsym(handle, "IOHIDEventSystemClientScheduleWithRunLoop");
        self.HIDEventGetSenderID = dlsym(handle, "IOHIDEventGetSenderID");
        self.HIDEventGetType = dlsym(handle, "IOHIDEventGetType");
        self.HIDEventSetSenderID = dlsym(handle, "IOHIDEventSetSenderID");
        self.HIDEventGetFloatValue = dlsym(handle, "IOHIDEventGetFloatValue");
        self.HIDEventCreateDigitizerEvent = dlsym(handle, "IOHIDEventCreateDigitizerEvent");
        self.HIDEventSetIntegerValue = dlsym(handle, "IOHIDEventSetIntegerValue");
        self.HIDEventSetFloatValue = dlsym(handle, "IOHIDEventSetFloatValue");
        
        dlclose(handle);
    }
}

- (void)registerEventCallback {
    if (self.registered || !self.HIDEventSystemClientCreate) return;
    
    // 创建 HID 事件系统客户端
    self.hidClient = self.HIDEventSystemClientCreate(kCFAllocatorDefault);
    if (!self.hidClient) {
        NSLog(@"[HID] Failed to create client");
        return;
    }
    
    // 注册事件回调
    self.HIDEventSystemClientRegisterEventCallback(
        self.hidClient,
        onHIDEventReceived,
        (__bridge void *)self,
        NULL
    );
    
    // 将客户端安排到当前运行循环
    self.HIDEventSystemClientScheduleWithRunLoop(
        self.hidClient,
        CFRunLoopGetCurrent(),
        kCFRunLoopDefaultMode
    );
    
    self.registered = YES;
    NSLog(@"[HID] Event callback registered");
}

- (void)enqueueEvent:(IOHIDEventRef)event {
    @synchronized(self) {
        if (self.eventQueue.count < 100) { // 防止无限增长
            // 保留事件的引用
            CFRetain(event);
            [self.eventQueue addObject:(__bridge id)event];
        }
    }
}

- (IOHIDEventRef)getNextEvent {
    @synchronized(self) {
        if (self.eventQueue.count == 0) return NULL;
        
        id eventObj = self.eventQueue.firstObject;
        [self.eventQueue removeObjectAtIndex:0];
        
        IOHIDEventRef event = (__bridge IOHIDEventRef)eventObj;
        CFRelease((__bridge CFTypeRef)eventObj);
        
        return event;
    }
}

#pragma mark - 触摸事件注入

- (void)sendTouchAtPoint:(CGPoint)point phase:(int)phase {
    if (!self.HIDEventCreateDigitizerEvent) return;
    
    uint64_t timestamp = mach_absolute_time();
    
    IOHIDEventRef event = self.HIDEventCreateDigitizerEvent(
        kCFAllocatorDefault,
        timestamp,
        0,    // transducerType: 0=touch
        0,    // index
        0,    // identity
        phase,// eventMask: 1=down, 2=up, 3=move
        0,    // buttonMask
        point.x, point.y, 0,  // x, y, z
        0, 0, 0, 0  // tipPressure, twist, majorRadius, minorRadius
    );
    
    if (event) {
        // 设置自定义 senderID 用于识别
        self.HIDEventSetSenderID(event, 0xDEADBEEFCAFE);
        
        // 通过 IOHIDEventSystemClient 发送
        // ...
        
        CFRelease(event);
    }
}

- (void)sendMouseButtonDown {
    // 通过 HID 注入鼠标按下
    // 使用 Digitizer 事件模拟
}

- (void)sendMouseButtonUp {
    // 鼠标释放
}

@end
