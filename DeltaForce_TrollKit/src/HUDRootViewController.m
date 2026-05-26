// HUDRootViewController - HUD 根视图控制器
// 管理 Metal 渲染层 + ImGui 界面 + 帧循环
// 基于反编译 viewDidLoad 中的 Metal / CAMetalLayer / CADisplayLink 设置

#import "HUDRootViewController.h"
#import "MetalRenderer.h"
#import "ImGuiAdapter.h"
#import "ESPOverlay.h"
#import "HIDEventManager.h"
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>

// 全局 Metal 资源 (从反编译: qword_10139CB50, qword_10139CB58, qword_10139CB48)
static UITextField *gTextField = nil;     // 隐藏的文本字段 (qword_10139CB50)
static CAMetalLayer *gMetalLayer = nil;    // Metal 渲染层 (qword_10139CB58)
static id<MTLCommandQueue> gCmdQueue = nil; // Metal 命令队列 (qword_10139CB48)
static float gScreenScale = 2.0;            // dword_10139DD2C

@interface HUDRootViewController ()
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, strong) MetalRenderer *renderer;
@property (nonatomic, strong) ImGuiAdapter *imgui;
@property (nonatomic) double animationTime;
@property (nonatomic) BOOL rendering;
@end

@implementation HUDRootViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // 透明背景 (作弊覆盖层不可见)
    self.view.backgroundColor = [UIColor clearColor];
    
    // 获取屏幕尺寸
    UIScreen *screen = [UIScreen mainScreen];
    CGRect bounds = screen.bounds;
    CGFloat scale = screen.scale;
    gScreenScale = scale;
    
    // 步骤1: 创建隐藏的 UITextField
    // 用于持有 CAMetalLayer (从反编译恢复的技巧)
    gTextField = [[UITextField alloc] initWithFrame:bounds];
    gTextField.backgroundColor = [UIColor clearColor];
    gTextField.secureTextEntry = YES;      // 防止截图捕获
    gTextField.userInteractionEnabled = NO; // 穿透触摸
    
    // 获取 UITextField 的 subview (UIFieldEditor)
    UIView *fieldEditor = gTextField.subviews.firstObject;
    fieldEditor.userInteractionEnabled = NO;
    
    [self.view addSubview:gTextField];
    
    // 步骤2: 创建 CAMetalLayer
    gMetalLayer = [CAMetalLayer layer];
    gMetalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    gMetalLayer.framebufferOnly = YES;
    gMetalLayer.opaque = NO;
    gMetalLayer.maximumDrawableCount = 2;
    gMetalLayer.presentsWithTransaction = NO;
    gMetalLayer.frame = gTextField.bounds;
    
    // 将 Metal 层添加到 fieldEditor 的 layer
    [fieldEditor.layer addSublayer:gMetalLayer];
    
    // 步骤3: 创建 Metal 设备
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    gMetalLayer.device = device;
    
    // 设置 drawable size (按屏幕比例)
    gMetalLayer.drawableSize = CGSizeMake(bounds.size.width * scale, 
                                           bounds.size.height * scale);
    
    // 步骤4: 创建命令队列
    gCmdQueue = [device newCommandQueue];
    
    // 步骤5: 初始化 Metal 渲染器
    self.renderer = [[MetalRenderer alloc] initWithDevice:device
                                                    layer:gMetalLayer
                                               commandQueue:gCmdQueue];
    
    // 步骤6: 初始化 ImGui 适配层
    self.imgui = [[ImGuiAdapter alloc] init];
    
    // 步骤7: 启动 DisplayLink 帧循环 (60fps)
    // 对应反编译: CADisplayLink displayLinkWithTarget:selector:ChangeUI
    self.displayLink = [CADisplayLink displayLinkWithTarget:self
                                                   selector:@selector(renderFrame:)];
    
    // 锁定帧率为 60fps (对应反编译: CAFrameRateRangeMake(60,60,60))
    if (@available(iOS 15.0, *)) {
        self.displayLink.preferredFrameRateRange = CAFrameRateRangeMake(60, 60, 60);
    } else {
        self.displayLink.preferredFramesPerSecond = 60;
    }
    
    [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop]
                           forMode:NSRunLoopCommonModes];
    
    self.rendering = YES;
    
    NSLog(@"[HUD] Metal+ImGui renderer ready");
}

- (void)renderFrame:(CADisplayLink *)displayLink {
    if (!self.rendering) return;
    
    self.animationTime = CACurrentMediaTime();
    
    // 获取下一个 drawable
    id<CAMetalDrawable> drawable = [gMetalLayer nextDrawable];
    if (!drawable) return;
    
    // 创建命令缓冲区
    id<MTLCommandBuffer> cmdBuffer = [gCmdQueue commandBuffer];
    
    // 1. ImGui 帧开始
    [self.imgui beginFrame:drawable.size timestamp:self.animationTime];
    
    // 2. 渲染作弊菜单
    [self.imgui renderCheatMenu:self];
    
    // 3. ImGui 帧结束 + 绘制
    [self.imgui endFrame:cmdBuffer drawable:drawable];
    
    // 4. 提交命令
    [cmdBuffer commit];
    
    // 5. 等待渲染完成
    [cmdBuffer waitUntilScheduled];
}

- (void)loadImGui {
    // 加载 ImGui 资源 (字体, 样式等)
    [self.imgui loadFonts];
    [self.imgui setupStyle];
}

- (void)prepareForEntryAnimation {
    // 入场动画 - 渐入效果
    self.view.alpha = 0.0;
    [UIView animateWithDuration:0.25 animations:^{
        self.view.alpha = 1.0;
    }];
}

- (void)syncCurrentOrientation {
    // 同步屏幕方向
    UIScreen *screen = [UIScreen mainScreen];
    CGRect bounds = screen.bounds;
    gMetalLayer.frame = bounds;
    gMetalLayer.drawableSize = CGSizeMake(bounds.size.width * gScreenScale, 
                                           bounds.size.height * gScreenScale);
}

// === 处理 senderID (对应 TouchMainWindow timerFired 回调) ===
- (void)handleSenderID:(uint64_t)senderID {
    // 识别触摸来源
    // senderID 可用于区分游戏触摸和作弊触摸
    if (senderID == 0xDEADBEEFCAFE) { // 模拟的触摸
        // 转发到 ImGui
    }
}

@end
