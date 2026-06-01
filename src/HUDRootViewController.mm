// HUDRootViewController - HUD 根视图控制器
// Metal + ImGui 覆盖层渲染 (60fps)
// 反检测设计: 使用 UITextField 作为 CAMetalLayer 容器
// 对应原版反编译: -[HUDRootViewController viewDidLoad] (0x1000079d4)

#import "HUDRootViewController.h"
#import "MetalRenderer.h"
#import "ImGuiAdapter.h"
#import "CryptoUtils.h"
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

// 防止 viewDidLoad 被多次调用（内存警告可能导致 view 被卸载重载）
static BOOL g_imGuiInitialized = NO;

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

    self.view.backgroundColor = [UIColor clearColor];

    UIScreen *screen = [UIScreen mainScreen];
    CGRect bounds = screen.bounds;
    CGFloat scale = screen.scale;

    g_screenScale = (float)scale;
    g_screenWidth = (float)bounds.size.width;
    g_screenHeight = (float)bounds.size.height;

    // ===== 步骤0: 创建 ImGui 上下文 (必须在任何 ImGui 调用之前, 且只创建一次) =====
    if (!g_imGuiInitialized) {
        if (!ImGui::GetCurrentContext()) {
            ImGui::CreateContext();
            ImGui::GetIO().IniFilename = NULL; // 禁用 ini 文件, 避免文件系统检测
            NSLog(@"[HUD] ImGui context created");
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
            NSLog(@"[HUD] FATAL: Metal not available");
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
        NSLog(@"[HUD] ImGui Metal backend initialized");
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
    NSLog(@"[HUD] Metal+ImGui ready (UITextField container, anti-detection)");
}

- (void)ChangeUI {
    if (!self.rendering) return;
    if (!gMetalLayer || !gCmdQueue) return;
    if (!ImGui::GetCurrentContext()) return;

    self.animationTime = CACurrentMediaTime();

    id<CAMetalDrawable> drawable = [gMetalLayer nextDrawable];
    if (!drawable) return;

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
}

- (void)syncCurrentOrientation {
    UIScreen *screen = [UIScreen mainScreen];
    CGRect bounds = screen.bounds;
    CGFloat scale = screen.scale;

    g_screenScale = (float)scale;
    g_screenWidth = (float)bounds.size.width;
    g_screenHeight = (float)bounds.size.height;

    gMetalLayer.frame = bounds;
    gMetalLayer.drawableSize = CGSizeMake(bounds.size.width * scale,
                                           bounds.size.height * scale);
}

- (void)handleSenderID:(uint64_t)senderID {
    if (senderID == 0xDEADBEEFCAFE) return;
}

@end
