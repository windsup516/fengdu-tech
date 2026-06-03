// DFFramebufferDescriptor.m — Framebuffer pass configuration implementation

#import "DFFramebufferDescriptor.h"

@implementation DFFramebufferDescriptor

+ (instancetype)defaultDescriptor {
    DFFramebufferDescriptor *desc = [[DFFramebufferDescriptor alloc] init];
    desc.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
    desc.depthPixelFormat = MTLPixelFormatDepth32Float;
    desc.stencilPixelFormat = MTLPixelFormatInvalid;
    desc.sampleCount = 1;
    desc.clearColor = MTLClearColorMake(0, 0, 0, 0);
    desc.clearOnLoad = YES;
    desc.storeResults = YES;
    return desc;
}

- (MTLRenderPassDescriptor *)toMTLRenderPassDescriptor:(id<MTLTexture>)colorTexture
                                         depthTexture:(id<MTLTexture>)depthTexture {
    MTLRenderPassDescriptor *rpd = [MTLRenderPassDescriptor renderPassDescriptor];

    if (colorTexture) {
        rpd.colorAttachments[0].texture = colorTexture;
        rpd.colorAttachments[0].loadAction = _clearOnLoad ? MTLLoadActionClear : MTLLoadActionLoad;
        rpd.colorAttachments[0].clearColor = _clearColor;
        rpd.colorAttachments[0].storeAction = _storeResults ? MTLStoreActionStore
                                                             : MTLStoreActionDontCare;
    }

    if (depthTexture) {
        rpd.depthAttachment.texture = depthTexture;
        rpd.depthAttachment.loadAction = MTLLoadActionClear;
        rpd.depthAttachment.clearDepth = 1.0;
        rpd.depthAttachment.storeAction = MTLStoreActionDontCare;
    }

    return rpd;
}

@end
