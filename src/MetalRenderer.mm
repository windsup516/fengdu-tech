// MetalRenderer - Metal 渲染封装
// 配合 ImGui 绘制作弊菜单覆盖层

#import "MetalRenderer.h"
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>

@interface MetalRenderer ()
@property (nonatomic, strong) id<MTLDevice> device;
@property (nonatomic, strong) CAMetalLayer *layer;
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;
@end

@implementation MetalRenderer

- (instancetype)initWithDevice:(id<MTLDevice>)device 
                         layer:(CAMetalLayer *)layer 
                   commandQueue:(id<MTLCommandQueue>)commandQueue {
    self = [super init];
    if (self) {
        _device = device;
        _layer = layer;
        _commandQueue = commandQueue;
    }
    return self;
}

- (void)setupRenderPipeline {
    // 创建 Metal 渲染管线用于 ImGui
    // 使用 ImGui 的 Metal 后端
}

- (void)beginFrame {
    // 帧开始
}

- (void)endFrame {
    // 帧结束 - 提交命令
}

- (void)drawWithDrawable:(id<CAMetalDrawable>)drawable {
    id<MTLCommandBuffer> cmdBuffer = [self.commandQueue commandBuffer];
    cmdBuffer.label = @"ImGui Command Buffer";
    
    // 创建渲染描述符
    MTLRenderPassDescriptor *desc = [MTLRenderPassDescriptor renderPassDescriptor];
    desc.colorAttachments[0].texture = drawable.texture;
    desc.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0); // 透明
    desc.colorAttachments[0].loadAction = MTLLoadActionClear;
    desc.colorAttachments[0].storeAction = MTLStoreActionStore;
    
    // 提交渲染命令
    id<MTLRenderCommandEncoder> encoder = [cmdBuffer renderCommandEncoderWithDescriptor:desc];
    encoder.label = @"ImGui Render Encoder";
    
    // ImGui 绘制...
    
    [encoder endEncoding];
    
    [cmdBuffer presentDrawable:drawable];
    [cmdBuffer commit];
}

@end
