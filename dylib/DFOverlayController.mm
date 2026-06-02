// DFOverlayController — self-contained Metal+ImGui overlay in game process
// NO dependencies on Stocks src/ (no ImGuiAdapter, no GameHooks, no ESPOverlay, no Logging)
// Proves injection works by drawing debug overlay + writing status to /tmp/dfoverlay.log

#import "DFOverlayController.h"
#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#import "imgui.h"
#import "imgui_impl_metal.h"

// Cross-process log: write to /tmp/ so Stocks app can verify injection succeeded
static FILE *g_dylibLog = NULL;
static void dylib_log(const char *fmt, ...) {
    if (!g_dylibLog) g_dylibLog = fopen("/tmp/dfoverlay.log", "w");
    if (!g_dylibLog) return;
    time_t now = time(NULL);
    struct tm *t = localtime(&now);
    fprintf(g_dylibLog, "%02d:%02d:%02d [DFOverlay] ", t->tm_hour, t->tm_min, t->tm_sec);
    va_list args;
    va_start(args, fmt);
    vfprintf(g_dylibLog, fmt, args);
    fprintf(g_dylibLog, "\n");
    fflush(g_dylibLog);
    va_end(args);
}

@interface DFOverlayController ()
@property (nonatomic, strong) UIWindow *overlayWindow;
@property (nonatomic, strong) CAMetalLayer *metalLayer;
@property (nonatomic, strong) id<MTLCommandQueue> cmdQueue;
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic) float screenW, screenH;
@property (nonatomic) int frameCount;
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

    if (![NSThread isMainThread]) {
        dispatch_sync(dispatch_get_main_queue(), ^{ [self startOverlay]; });
        return;
    }

    dylib_log("startOverlay: PID=%d proc=%s", getpid(), getprogname());

    UIScreen *screen = [UIScreen mainScreen];
    CGRect bounds = screen.bounds;
    self.screenW = bounds.size.width;
    self.screenH = bounds.size.height;
    CGFloat scale = screen.scale;

    dylib_log("Screen: %.0fx%.0f@%.1fx", self.screenW, self.screenH, scale);

    // ImGui context
    if (!ImGui::GetCurrentContext()) {
        ImGui::CreateContext();
        ImGui::GetIO().IniFilename = NULL;
        ImGui::GetIO().DisplaySize = ImVec2(self.screenW, self.screenH);
    }

    // Style
    ImGui::GetStyle().WindowRounding = 8.0f;

    // CAMetalLayer
    self.metalLayer = [CAMetalLayer layer];
    self.metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    self.metalLayer.framebufferOnly = YES;
    self.metalLayer.opaque = NO;
    self.metalLayer.maximumDrawableCount = 2;
    self.metalLayer.presentsWithTransaction = NO;
    self.metalLayer.frame = bounds;
    self.metalLayer.drawableSize = CGSizeMake(self.screenW * scale, self.screenH * scale);

    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (!device) {
        dylib_log("FATAL: no Metal device");
        return;
    }
    self.metalLayer.device = device;
    self.cmdQueue = [device newCommandQueue];

    ImGui_ImplMetal_Init(device);
    ImGui_ImplMetal_CreateDeviceObjects(device);
    dylib_log("Metal device: %s", [[device name] UTF8String]);

    // Root view
    UIViewController *rootVC = [[UIViewController alloc] init];
    rootVC.view = [[UIView alloc] initWithFrame:bounds];
    rootVC.view.backgroundColor = [UIColor clearColor];
    [rootVC.view.layer addSublayer:self.metalLayer];

    // Overlay window
    self.overlayWindow = [[UIWindow alloc] initWithFrame:bounds];
    self.overlayWindow.backgroundColor = [UIColor clearColor];
    self.overlayWindow.windowLevel = UIWindowLevelStatusBar + 200;
    self.overlayWindow.rootViewController = rootVC;
    self.overlayWindow.hidden = NO;
    [self.overlayWindow makeKeyAndVisible];

    // 60fps render loop
    self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(renderFrame:)];
    if (@available(iOS 15.0, *))
        self.displayLink.preferredFrameRateRange = CAFrameRateRangeMake(60, 60, 60);
    else
        self.displayLink.preferredFramesPerSecond = 60;
    [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];

    self.initialized = YES;
    dylib_log("Overlay started — winLevel=%.0f window=%@",
              self.overlayWindow.windowLevel, self.overlayWindow);
}

- (void)renderFrame:(CADisplayLink *)link {
    if (!self.initialized || !self.metalLayer) return;

    self.frameCount++;

    id<CAMetalDrawable> drawable = [self.metalLayer nextDrawable];
    if (!drawable) {
        if (self.frameCount <= 5) dylib_log("frame#%d: nextDrawable=nil", self.frameCount);
        return;
    }

    id<MTLCommandBuffer> cmdBuf = [self.cmdQueue commandBuffer];
    if (!cmdBuf) return;

    MTLRenderPassDescriptor *rpd = [MTLRenderPassDescriptor renderPassDescriptor];
    rpd.colorAttachments[0].texture = drawable.texture;
    rpd.colorAttachments[0].loadAction = MTLLoadActionClear;
    rpd.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0);
    rpd.colorAttachments[0].storeAction = MTLStoreActionStore;

    ImGui_ImplMetal_NewFrame(rpd);
    ImGui::NewFrame();

    // === DEBUG OVERLAY ===
    {
        ImDrawList *dl = ImGui::GetBackgroundDrawList();

        // Full-screen red border (4px)
        dl->AddRect(ImVec2(2, 2), ImVec2(self.screenW - 2, self.screenH - 2),
                    IM_COL32(255, 0, 0, 255), 0.0f, 0, 4.0f);

        // Center crosshair
        float cx = self.screenW / 2, cy = self.screenH / 2;
        dl->AddLine(ImVec2(cx - 60, cy), ImVec2(cx + 60, cy), IM_COL32(255, 50, 50, 255), 3.0f);
        dl->AddLine(ImVec2(cx, cy - 60), ImVec2(cx, cy + 60), IM_COL32(255, 50, 50, 255), 3.0f);

        // Status text
        char buf[256];
        snprintf(buf, sizeof(buf), "DFOverlay ACTIVE | frame#%d | PID=%d | %.0fx%.0f",
                 self.frameCount, getpid(), self.screenW, self.screenH);
        dl->AddText(ImVec2(cx - 200, cy + 40), IM_COL32(0, 255, 0, 255), buf);

        // Top-left watermark
        dl->AddText(ImVec2(10, 10), IM_COL32(255, 255, 255, 180), "DFOverlay v1.0");
    }

    // Menu window (small info window)
    ImGui::SetNextWindowPos(ImVec2(10, 30), ImGuiCond_Once);
    ImGui::SetNextWindowSize(ImVec2(280, 100), ImGuiCond_Once);
    ImGui::Begin("DFOverlay", NULL,
                 ImGuiWindowFlags_NoResize | ImGuiWindowFlags_NoCollapse);
    ImGui::TextColored(ImVec4(0, 1, 0, 1), "INJECTED OK");
    ImGui::Text("PID: %d", getpid());
    ImGui::Text("Frame: %d", self.frameCount);
    ImGui::Text("Resolution: %.0fx%.0f", self.screenW, self.screenH);
    ImGui::End();

    ImGui::Render();
    id<MTLRenderCommandEncoder> enc = [cmdBuf renderCommandEncoderWithDescriptor:rpd];
    [enc pushDebugGroup:@"DFOverlay"];
    ImGui_ImplMetal_RenderDrawData(ImGui::GetDrawData(), cmdBuf, enc);
    [enc popDebugGroup];
    [enc endEncoding];
    [cmdBuf presentDrawable:drawable];
    [cmdBuf commit];

    // Heartbeat: log every 300 frames (5s)
    if (self.frameCount == 1 || self.frameCount % 300 == 0) {
        dylib_log("heartbeat frame#%d screen=%.0fx%.0f", self.frameCount, self.screenW, self.screenH);
    }
}

- (void)stopOverlay {
    [self.displayLink invalidate];
    self.displayLink = nil;
    self.overlayWindow.hidden = YES;
    self.overlayWindow = nil;
    self.initialized = NO;
    dylib_log("Overlay stopped");
}

@end

// ====== Dylib Constructor — auto-start on injection ======
__attribute__((constructor))
static void DFOverlayInit(void) {
    dylib_log("=== dylib constructor: PID=%d ===", getpid());
    // Must run on main thread for UIKit
    if ([NSThread isMainThread]) {
        [[DFOverlayController shared] startOverlay];
    } else {
        dispatch_sync(dispatch_get_main_queue(), ^{
            [[DFOverlayController shared] startOverlay];
        });
    }
}

__attribute__((destructor))
static void DFOverlayCleanup(void) {
    [[DFOverlayController shared] stopOverlay];
    dylib_log("=== dylib destructor ===");
    if (g_dylibLog) { fclose(g_dylibLog); g_dylibLog = NULL; }
}
