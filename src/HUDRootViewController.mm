// HUDRootViewController - HUD 根视图控制器
// Metal + ImGui 覆盖层渲染 (60fps)
// 反检测设计: 使用 UITextField 作为 CAMetalLayer 容器
// 对应原版反编译: -[HUDRootViewController viewDidLoad] (0x1000079d4)

#import "HUDRootViewController.h"
#import "HUDController.h"
#import "MetalRenderer.h"
#import "ImGuiAdapter.h"
#import "CryptoUtils.h"
#import "Logging.h"
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#import "imgui.h"
#import "imgui_impl_metal.h"

// 全局变量 (对应原版反编译)
// qword_10139CB50 = UITextField 容器
static UITextField *gMetalContainer = nil;
// qword_10139CB58 = CAMetalLayer
static CAMetalLayer *gMetalLayer = nil;
// 屏幕缩放比 (dword_10139DD2C) — TouchMainWindow timerFired 使用
float g_screenScale = 2.0f;
// 屏幕尺寸 (qword_10139DD38 = width, dword_10139DD40 = height) — TouchMainWindow 使用
float g_screenWidth = 0.0f;
float g_screenHeight = 0.0f;

static id<MTLCommandQueue> gCmdQueue = nil;

// 防止 viewDidLoad 被多次调用
static BOOL g_imGuiInitialized = NO;

// contextId 访问器 (定义在 HUDController.m, C linkage)
extern "C" {
unsigned int hudWindowContextId(void);
unsigned int touchWindowContextId(void);
void hudTriggerSBSRecovery(void);
}

// 前向声明
@interface HUDRootViewController ()
- (void)recreateMetalLayer;
@end

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

    HUD_LOG(@"viewDidLoad: starting Metal+ImGui init...");
    self.view.backgroundColor = [UIColor clearColor];

    UIScreen *screen = [UIScreen mainScreen];
    CGRect bounds = screen.bounds;
    CGFloat scale = screen.scale;

    g_screenScale = (float)scale;
    g_screenWidth = (float)bounds.size.width;
    g_screenHeight = (float)bounds.size.height;
    HUD_LOG(@"Screen: %.0fx%.0f scale=%.1f", g_screenWidth, g_screenHeight, g_screenScale);

    // ===== 步骤0: 创建 ImGui 上下文 (必须在任何 ImGui 调用之前, 且只创建一次) =====
    if (!g_imGuiInitialized) {
        if (!ImGui::GetCurrentContext()) {
            ImGui::CreateContext();
            ImGui::GetIO().IniFilename = NULL; // 禁用 ini 文件, 避免文件系统检测
            HUD_LOG(@"ImGui context created");
        }
    }

    // ===== 创建 UITextField 作为 CAMetalLayer 容器 (反检测关键) =====
    gMetalContainer = [[UITextField alloc] initWithFrame:bounds];
    gMetalContainer.backgroundColor = [UIColor clearColor];
    gMetalContainer.secureTextEntry = YES;
    gMetalContainer.userInteractionEnabled = NO;

    UIView *fieldEditor = gMetalContainer.subviews.firstObject;
    if (fieldEditor) {
        fieldEditor.userInteractionEnabled = NO;
    }

    // ===== 创建 CAMetalLayer =====
    gMetalLayer = [CAMetalLayer layer];
    gMetalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    gMetalLayer.framebufferOnly = YES;
    gMetalLayer.opaque = NO;
    gMetalLayer.maximumDrawableCount = 2;
    gMetalLayer.presentsWithTransaction = NO;
    gMetalLayer.frame = bounds;

    if (fieldEditor) {
        [fieldEditor.layer addSublayer:gMetalLayer];
    } else {
        [gMetalContainer.layer addSublayer:gMetalLayer];
    }

    // ===== 创建 Metal 设备 (仅首次) =====
    if (!g_imGuiInitialized) {
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (!device) {
            HUD_LOG(@"FATAL: Metal not available on this device");
            return;
        }
        gMetalLayer.device = device;
        gMetalLayer.drawableSize = CGSizeMake(bounds.size.width * scale,
                                               bounds.size.height * scale);

        // ===== 创建命令队列 =====
        gCmdQueue = [device newCommandQueue];

        // ===== 初始化 Metal 渲染器 =====
        self.renderer = [[MetalRenderer alloc] initWithDevice:device
                                                        layer:gMetalLayer
                                                 commandQueue:gCmdQueue];

        // ===== 初始化 ImGui 配置 (context 已创建, GetIO 安全) =====
        self.imgui = [[ImGuiAdapter alloc] init];
        [self.imgui loadFonts];
        [self.imgui setupStyle];

        // ===== 初始化 ImGui Metal 后端 + 显式创建字体纹理 =====
        ImGui_ImplMetal_Init(device);
        ImGui_ImplMetal_CreateDeviceObjects(device);
        HUD_LOG(@"ImGui Metal backend initialized (device=%s)", [[device name] UTF8String]);
    }

    // ===== 启动 DisplayLink 60fps 渲染循环 =====
    if (!self.displayLink) {
        self.displayLink = [CADisplayLink displayLinkWithTarget:self
                                                       selector:@selector(ChangeUI)];

        if (@available(iOS 15.0, *)) {
            self.displayLink.preferredFrameRateRange = CAFrameRateRangeMake(60, 60, 60);
        } else {
            self.displayLink.preferredFramesPerSecond = 60;
        }

        [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop]
                               forMode:NSRunLoopCommonModes];
    }

    self.rendering = YES;
    g_imGuiInitialized = YES;
    HUD_LOG(@"Metal+ImGui ready, rendering=%d displayLink=%@", self.rendering, self.displayLink ? @"YES" : @"NIL");
}

- (void)ChangeUI {
    if (!self.rendering) return;
    if (!gMetalLayer || !gCmdQueue) return;
    if (!ImGui::GetCurrentContext()) return;

    static int frameCount = 0;
    if (++frameCount <= 10 || frameCount % 300 == 0) {
        HUD_LOG(@"ChangeUI rendering frame #%d", frameCount);
    }

    // 诊断: 前 60 帧 (1秒) 输出每个细节
    // 之后每 180 帧 (3秒) 输出一次摘要
    static int diagCount = 0;
    diagCount++;
    if (diagCount <= 60 || diagCount % 180 == 0) {
        HUD_LOG(@"[DIAG f#%d] screen=%.0fx%.0f scale=%.1f", diagCount,
                g_screenWidth, g_screenHeight, g_screenScale);
        HUD_LOG(@"[DIAG f#%d] viewBounds=%@ viewFrame=%@ alpha=%.2f", diagCount,
                NSStringFromCGRect(self.view.bounds),
                NSStringFromCGRect(self.view.frame),
                self.view.alpha);
        HUD_LOG(@"[DIAG f#%d] metalLayer frame=%@ opaque=%d drawableSize=%@", diagCount,
                NSStringFromCGRect(gMetalLayer.frame),
                gMetalLayer.opaque,
                NSStringFromCGSize(gMetalLayer.drawableSize));
        HUD_LOG(@"[DIAG f#%d] hudCtx=%u touchCtx=%u", diagCount,
                hudWindowContextId(), touchWindowContextId());
    }

    // contextId 恢复: 每帧检查, 连续 N 帧 ctx=0 则触发窗口重建
    {
        static int deadFrames = 0;
        unsigned int hudCtx = hudWindowContextId();
        if (hudCtx == 0) {
            deadFrames++;
            if (deadFrames == 30) {
                HUD_LOG(@"CONTEXT DEAD for %d frames — triggering recovery", deadFrames);
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self recreateMetalLayer];
                    hudTriggerSBSRecovery();
                });
            }
        } else {
            if (deadFrames >= 30) {
                HUD_LOG(@"CONTEXT RECOVERED after %d dead frames", deadFrames);
            }
            deadFrames = 0;
        }
    }

    self.animationTime = CACurrentMediaTime();

    id<CAMetalDrawable> drawable = [gMetalLayer nextDrawable];
    if (!drawable) {
        if (diagCount <= 10) HUD_LOG(@"[DIAG f#%d] nextDrawable returned nil!", diagCount);
        return;
    }

    id<MTLCommandBuffer> cmdBuffer = [gCmdQueue commandBuffer];
    if (!cmdBuffer) return;

    MTLRenderPassDescriptor *renderPassDesc = [MTLRenderPassDescriptor renderPassDescriptor];
    renderPassDesc.colorAttachments[0].texture = drawable.texture;
    renderPassDesc.colorAttachments[0].loadAction = MTLLoadActionClear;
    renderPassDesc.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0);
    renderPassDesc.colorAttachments[0].storeAction = MTLStoreActionStore;

    ImGui_ImplMetal_NewFrame(renderPassDesc);

    CGSize drawableSize = CGSizeMake((CGFloat)drawable.texture.width,
                                     (CGFloat)drawable.texture.height);
    [self.imgui beginFrame:drawableSize timestamp:self.animationTime];

    [self.imgui renderCheatMenu:self];

    [self.imgui endFrame:cmdBuffer drawable:drawable renderPassDesc:renderPassDesc];

    [cmdBuffer commit];
}

// 导出全局变量访问器 (供 TouchMainWindow timerFired 使用)
+ (float)screenScale { return g_screenScale; }
+ (float)screenWidth { return g_screenWidth; }
+ (float)screenHeight { return g_screenHeight; }

- (void)loadImGui {
    [self.imgui loadFonts];
    [self.imgui setupStyle];
}

- (void)renderFrame:(CADisplayLink *)displayLink {
    (void)displayLink;
}

- (void)prepareForEntryAnimation {
    self.view.alpha = 0.0;
    [UIView animateWithDuration:0.25 animations:^{
        self.view.alpha = 1.0;
    }];
    // Safety: if animation fails (window context not ready), force visible after delay
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (self.view.alpha < 0.5) {
            HUD_LOG(@"Entry animation may not have completed (alpha=%.2f), forcing alpha=1.0", self.view.alpha);
            self.view.alpha = 1.0;
        }
    });
}

- (void)syncCurrentOrientation {
    UIScreen *screen = [UIScreen mainScreen];
    CGRect bounds = screen.bounds;
    CGFloat scale = screen.scale;

    // Stocks app 是竖屏, 但游戏是横屏 — 通过设备方向判断是否需要交换宽高
    UIDeviceOrientation devOrientation = [[UIDevice currentDevice] orientation];
    BOOL isLandscape = (devOrientation == UIDeviceOrientationLandscapeLeft ||
                        devOrientation == UIDeviceOrientationLandscapeRight);

    float w = (float)bounds.size.width;
    float h = (float)bounds.size.height;
    if (isLandscape && w < h) {
        // 设备横屏但 UIScreen 返回竖屏尺寸 — 交换
        float tmp = w; w = h; h = tmp;
        HUD_LOG(@"Orientation: landscape — swapping screen to %.0fx%.0f", w, h);
    }

    g_screenScale = (float)scale;
    g_screenWidth = w;
    g_screenHeight = h;

    CGRect layerFrame = CGRectMake(0, 0, w, h);
    gMetalLayer.frame = layerFrame;
    gMetalLayer.drawableSize = CGSizeMake(w * scale, h * scale);
    HUD_LOG(@"syncCurrentOrientation: screen=%.0fx%.0f scale=%.1f landscape=%d",
            g_screenWidth, g_screenHeight, g_screenScale, isLandscape);
}

- (void)handleSenderID:(uint64_t)senderID {
    if (senderID == 0xDEADBEEFCAFE) return;
}

// contextId 恢复: 强制 UIWindow 重建 CAContext
// CAMetalLayer 更换不会改变 contextId (contextId 属于 UIWindow 的 CAContext)
// 必须通过 makeKeyAndVisible 让 window server 分配新的 CAContext
- (void)recreateMetalLayer {
    HUD_LOG(@"recreateMetalLayer: forcing window CAContext refresh...");

    // 获取 HUDController 的 hudWindow
    HUDController *hc = [HUDController shared];
    UIWindow *hudWin = hc.hudWindow;
    if (!hudWin) {
        HUD_LOG(@"recreateMetalLayer: no hudWindow, aborting");
        return;
    }

    // 重新创建 CAMetalLayer (确保 layer 本身也是新的)
    id<MTLDevice> device = gMetalLayer.device;
    if (device) {
        [gMetalLayer removeFromSuperlayer];

        CAMetalLayer *newLayer = [CAMetalLayer layer];
        newLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
        newLayer.framebufferOnly = YES;
        newLayer.opaque = NO;
        newLayer.maximumDrawableCount = 2;
        newLayer.presentsWithTransaction = NO;
        newLayer.device = device;
        newLayer.frame = CGRectMake(0, 0, g_screenWidth, g_screenHeight);
        newLayer.drawableSize = CGSizeMake(g_screenWidth * g_screenScale,
                                            g_screenHeight * g_screenScale);

        UIView *container = gMetalContainer.subviews.firstObject ?: gMetalContainer;
        [container.layer addSublayer:newLayer];
        gMetalLayer = newLayer;

        if (self.renderer) {
            [self.renderer updateLayer:newLayer];
        }
        HUD_LOG(@"recreateMetalLayer: CAMetalLayer replaced");
    }

    // 强制 UIWindow 重新连接 render server 获取新 contextId
    hudWin.hidden = NO;
    [hudWin makeKeyAndVisible];
    hudWin.windowLevel = 10000010.0;
    HUD_LOG(@"recreateMetalLayer: makeKeyAndVisible called, new ctx=%u",
            hudWindowContextId());
}

@end
