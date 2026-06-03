// FramebufferDescriptor.h — Framebuffer pass configuration
// Matches 太阳神 framebuffer setup for Metal rendering

#import <Metal/Metal.h>
#import <Foundation/Foundation.h>

@interface DFFramebufferDescriptor : NSObject

@property (nonatomic, assign) MTLPixelFormat colorPixelFormat;
@property (nonatomic, assign) MTLPixelFormat depthPixelFormat;
@property (nonatomic, assign) MTLPixelFormat stencilPixelFormat;
@property (nonatomic, assign) NSUInteger sampleCount;
@property (nonatomic, assign) MTLClearColor clearColor;
@property (nonatomic, assign) BOOL clearOnLoad;
@property (nonatomic, assign) BOOL storeResults;

+ (instancetype)defaultDescriptor;
- (MTLRenderPassDescriptor *)toMTLRenderPassDescriptor:(id<MTLTexture>)colorTexture
                                         depthTexture:(id<MTLTexture>)depthTexture;

@end
