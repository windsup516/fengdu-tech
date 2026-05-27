// HUDRootViewController - HUD 根视图控制器
// 基于反编译 0x1000079D4 viewDidLoad 恢复
// 真实结构: UITextField → UIFieldEditor → CAMetalLayer ← 非 self.view.layer
// DisplayLink selector: "ChangeUI" (非 "renderFrame:")
// 使用 Metal + ImGui 渲染 60fps 作弊菜单覆盖层

#import "HUDRootViewController.h"
#import "MetalRenderer.h"
#import "ImGuiAdapter.h"
#import "CryptoUtils.h"
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>

// 全局 Metal 资源 (对应反编译中的 qword)
static UITextField *gTextField = nil;     // qword_10139CB50
static CAMetalLayer *gMetalLayer = nil;    // qword_10139CB58
static id<MTLCommandQueue> gCmdQueue = nil; // qword_10139CB48
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
    
    // === 透明背景 (覆盖层不可见) ===
    self.view.backgroundColor = [UIColor clearColor];
    
    // === 获取屏幕信息 ===
    UIScreen *screen = [UIScreen mainScreen];
    CGRect bounds = screen.bounds;
    CGFloat scale = screen.scale;
    gScreenScale = scale;
    
    // ====== 步骤1: 创建隐藏的 UITextField ======
    // 原版反编译: 用 UITextField 持有 CAMetalLayer
    // 利用 UITextField → UIFieldEditor 的 layer 树结构隐藏 Metal 层
    gTextField = [[UITextField alloc] initWithFrame:bounds];
    gTextField.backgroundColor = [UIColor clearColor];
    gTextField.secureTextEntry = YES;      // 安全输入模式 → 防止系统截图
    gTextField.userInteractionEnabled = NO; // 穿透所有触摸事件
    
    // 获取 UITextField 的 subview (UIFieldEditor.layer)
    UIView *fieldEditor = gTextField.subviews.firstObject;
    fieldEditor.userInteractionEnabled = NO;
    
    // 添加到视图层级
    [self.view addSubview:gTextField];
    
    // ====== 步骤2: 创建 CAMetalLayer (GPU 渲染层) ======
    gMetalLayer = [CAMetalLayer layer];
    gMetalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    gMetalLayer.framebufferOnly = YES;
    gMetalLayer.opaque = NO;
    gMetalLayer.maximumDrawableCount = 2;
    gMetalLayer.presentsWithTransaction = NO;
    gMetalLayer.frame = gTextField.bounds;
    
    // ⚠️ 关键: CAMetalLayer 加到 fieldEditor.layer 上, 非 self.view.layer
    // 反编译原文: [fieldEditor.layer addSublayer:cametalLayer]
    [fieldEditor.layer addSublayer:gMetalLayer];
    
    // ====== 步骤3: 创建 Metal 设备 ======
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    gMetalLayer.device = device;
    
    // 设置 drawable size (按屏幕比例缩放)
    gMetalLayer.drawableSize = CGSizeMake(bounds.size.width * scale,
                                           bounds.size.height * scale);
    
    // ====== 步骤4: 创建命令队列 ======
    gCmdQueue = [device newCommandQueue];
    
    // ====== 步骤5: 初始化 Metal 渲染器 ======
    self.renderer = [[MetalRenderer alloc] initWithDevice:device
                                                    layer:gMetalLayer
                                               commandQueue:gCmdQueue];
    
    // ====== 步骤6: 初始化 ImGui 适配层 ======
    self.imgui = [[ImGuiAdapter alloc] init];
    [self.imgui loadFonts];
    [self.imgui setupStyle];
    
    // ====== 步骤7: 启动 DisplayLink 60fps 帧循环 ======
    // 反编译原文: CADisplayLink displayLinkWithTarget:self selector:@selector(ChangeUI)
    // 注意: selector 名是 "ChangeUI" 而非 "renderFrame:" (反检测考量)
    self.displayLink = [CADisplayLink displayLinkWithTarget:self
                                                   selector:@selector(ChangeUI)];
    
    // 锁定帧率为 60fps
    // 反编译原文: CAFrameRateRangeMake(60.0, 60.0, 60.0)
    if (@available(iOS 15.0, *)) {
        self.displayLink.preferredFrameRateRange = CAFrameRateRangeMake(60, 60, 60);
    } else {
        self.displayLink.preferredFramesPerSecond = 60;
    }
    
    [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop]
                           forMode:NSRunLoopCommonModes];
    
    self.rendering = YES;
    
    NSLog(@"[HUD] Metal+ImGui ready (UITextField+MetalLayer on fieldEditor)");
}

// ⚠️ 方法名 "ChangeUI" — 对应反编译中的真实 selector
// 反编译: "displayLinkWithTarget:selector:" → "ChangeUI"
- (void)ChangeUI {
    if (!self.rendering) return;
    
    self.animationTime = CACurrentMediaTime();
    
    // 获取下一个 Metal drawable
    id<CAMetalDrawable> drawable = [gMetalLayer nextDrawable];
    if (!drawable) return;
    
    // 创建命令缓冲区
    id<MTLCommandBuffer> cmdBuffer = [gCmdQueue commandBuffer];
    
    // 1. ImGui 帧开始
    [self.imgui beginFrame:drawable.size timestamp:self.animationTime];
    
    // 2. 渲染作弊菜单
    [self.imgui renderCheatMenu:self];
    
    // 3. ImGui 帧结束 + 绘制到 Metal
    [self.imgui endFrame:cmdBuffer drawable:drawable];
    
    // 4. 提交 GPU 命令
    [cmdBuffer commit];
    
    // 5. 等待调度完成
    [cmdBuffer waitUntilScheduled];
}

- (void)loadImGui {
    [self.imgui loadFonts];
    [self.imgui setupStyle];
}

- (void)prepareForEntryAnimation {
    // 入场动画 - 渐入 (反编译: alpha 0→1 动画)
    self.view.alpha = 0.0;
    [UIView animateWithDuration:0.25 animations:^{
        self.view.alpha = 1.0;
    }];
}

- (void)syncCurrentOrientation {
    // 同步屏幕方向 (反编译: syncCurrentOrientation selector)
    UIScreen *screen = [UIScreen mainScreen];
    CGRect bounds = screen.bounds;
    gMetalLayer.frame = bounds;
    gMetalLayer.drawableSize = CGSizeMake(bounds.size.width * gScreenScale, 
                                           bounds.size.height * gScreenScale);
}

// === 处理 senderID (来自 TouchMainWindow timerFired 回调) ===
- (void)handleSenderID:(uint64_t)senderID {
    // senderID 用于区分游戏触摸和作弊触摸
    // 0xDEADBEEFCAFE = 我们注入的触摸
    if (senderID == 0xDEADBEEFCAFE) {
        // 是我们注入的事件, 忽略
        return;
    }
    // 否则是游戏本身的触摸, 可能需要转发到 ImGui
}

@end
