// DFOverlayController — Metal+ImGui overlay in game process
// Renders cheat menu HUD at 60fps via CADisplayLink
// Anti-detection: UITextField container + IOKit HID input

#import "DFOverlayController.h"
#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#import "imgui.h"
#import "imgui_impl_metal.h"
#import "MetalRenderer.h"
#import "ImGuiAdapter.h"

@interface DFOverlayController ()
@property (nonatomic, strong) UIWindow *overlayWindow;
@property (nonatomic, strong) CAMetalLayer *metalLayer;
@property (nonatomic, strong) MetalRenderer *renderer;
@property (nonatomic, strong) ImGuiAdapter *imgui;
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic) BOOL initialized;
@end

@implementation DFOverlayController

+ (instancetype)shared {
    static DFOverlayController *inst = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ inst = [[DFOverlayController alloc] init]; });
    return inst;
}

- (void)startOverlay {
    if (self.initialized) return;
    self.initialized = YES;

    // Ensure we're on main thread
    if (![NSThread isMainThread]) {
        dispatch_sync(dispatch_get_main_queue(), ^{ [self startOverlay]; });
        return;
    }

    UIScreen *screen = [UIScreen mainScreen];
    CGRect bounds = screen.bounds;
    CGFloat scale = screen.scale;

    // ImGui context
    if (!ImGui::GetCurrentContext()) {
        ImGui::CreateContext();
        ImGui::GetIO().IniFilename = NULL;
    }

    // Anti-detection: UITextField as CAMetalLayer container
    UITextField *container = [[UITextField alloc] initWithFrame:bounds];
    container.backgroundColor = [UIColor clearColor];
    container.secureTextEntry = YES;
    container.userInteractionEnabled = NO;

    UIView *fieldEditor = container.subviews.firstObject;
    if (fieldEditor) fieldEditor.userInteractionEnabled = NO;

    // CAMetalLayer
    self.metalLayer = [CAMetalLayer layer];
    self.metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    self.metalLayer.framebufferOnly = YES;
    self.metalLayer.opaque = NO;
    self.metalLayer.maximumDrawableCount = 2;
    self.metalLayer.presentsWithTransaction = NO;
    self.metalLayer.frame = bounds;

    UIView *targetView = fieldEditor ?: container;
    [targetView.layer addSublayer:self.metalLayer];

    // Metal device
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (!device) {
        NSLog(@"[DFOverlay] FATAL: no Metal device in game process");
        return;
    }
    self.metalLayer.device = device;
    self.metalLayer.drawableSize = CGSizeMake(bounds.size.width * scale,
                                               bounds.size.height * scale);

    id<MTLCommandQueue> cmdQueue = [device newCommandQueue];

    // Renderer
    self.renderer = [[MetalRenderer alloc] initWithDevice:device
                                                     layer:self.metalLayer
                                              commandQueue:cmdQueue];

    // ImGui
    self.imgui = [[ImGuiAdapter alloc] init];
    [self.imgui loadFonts];
    [self.imgui setupStyle];

    ImGui_ImplMetal_Init(device);
    ImGui_ImplMetal_CreateDeviceObjects(device);

    // Overlay window (above game windows)
    self.overlayWindow = [[UIWindow alloc] initWithFrame:bounds];
    self.overlayWindow.backgroundColor = [UIColor clearColor];
    self.overlayWindow.windowLevel = UIWindowLevelStatusBar + 200;
    UIViewController *rootVC = [[UIViewController alloc] init];
    rootVC.view = container;
    self.overlayWindow.rootViewController = rootVC;
    self.overlayWindow.hidden = NO;
    [self.overlayWindow makeKeyAndVisible];

    // 60fps render loop
    self.displayLink = [CADisplayLink displayLinkWithTarget:self
                                                    selector:@selector(renderFrame:)];
    if (@available(iOS 15.0, *)) {
        self.displayLink.preferredFrameRateRange = CAFrameRateRangeMake(60, 60, 60);
    } else {
        self.displayLink.preferredFramesPerSecond = 60;
    }
    [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];

    NSLog(@"[DFOverlay] Overlay started in game process (winLevel=%.0f)", self.overlayWindow.windowLevel);
}

- (void)renderFrame:(CADisplayLink *)link {
    if (!self.metalLayer) return;
    if (!ImGui::GetCurrentContext()) return;

    id<CAMetalDrawable> drawable = [self.metalLayer nextDrawable];
    if (!drawable) return;

    static id<MTLCommandQueue> cmdQueue = nil;
    if (!cmdQueue) {
        cmdQueue = [self.metalLayer.device newCommandQueue];
    }

    id<MTLCommandBuffer> cmdBuffer = [cmdQueue commandBuffer];
    if (!cmdBuffer) return;

    MTLRenderPassDescriptor *rpd = [MTLRenderPassDescriptor renderPassDescriptor];
    rpd.colorAttachments[0].texture = drawable.texture;
    rpd.colorAttachments[0].loadAction = MTLLoadActionClear;
    rpd.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0);
    rpd.colorAttachments[0].storeAction = MTLStoreActionStore;

    ImGui_ImplMetal_NewFrame(rpd);

    CGSize ds = CGSizeMake(drawable.texture.width, drawable.texture.height);
    double ts = CACurrentMediaTime();
    [self.imgui beginFrame:ds timestamp:ts];
    [self.imgui renderCheatMenu:nil];
    [self.imgui endFrame:cmdBuffer drawable:drawable renderPassDesc:rpd];

    [cmdBuffer commit];
}

- (void)stopOverlay {
    [self.displayLink invalidate];
    self.displayLink = nil;
    self.overlayWindow.hidden = YES;
    self.overlayWindow = nil;
    self.initialized = NO;
}

@end

// ====== Dylib Constructor — auto-start on injection ======
__attribute__((constructor))
static void DFOverlayInit(void) {
    NSLog(@"[DFOverlay] dylib loaded — starting overlay...");
    dispatch_async(dispatch_get_main_queue(), ^{
        [[DFOverlayController shared] startOverlay];
    });
}

// Dylib destructor
__attribute__((destructor))
static void DFOverlayCleanup(void) {
    [[DFOverlayController shared] stopOverlay];
    NSLog(@"[DFOverlay] dylib unloaded");
}
