// MetalTexture.m — Metal texture wrapper implementation

#import "MetalTexture.h"

@implementation MetalTexture

- (instancetype)initWithTexture:(id<MTLTexture>)texture {
    self = [super init];
    if (self) {
        _texture = texture;
        _width = texture.width;
        _height = texture.height;
    }
    return self;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device
                   descriptor:(MTLTextureDescriptor *)descriptor {
    id<MTLTexture> tex = [device newTextureWithDescriptor:descriptor];
    if (!tex) return nil;
    return [self initWithTexture:tex];
}

+ (instancetype)texture2DWithDevice:(id<MTLDevice>)device
                              width:(NSUInteger)width
                             height:(NSUInteger)height
                        pixelFormat:(MTLPixelFormat)format {
    MTLTextureDescriptor *desc = [MTLTextureDescriptor
        texture2DDescriptorWithPixelFormat:format
                                     width:width
                                    height:height
                                 mipmapped:NO];
    desc.usage = MTLTextureUsageShaderRead | MTLTextureUsageRenderTarget;
    desc.storageMode = MTLStorageModeShared;

    id<MTLTexture> tex = [device newTextureWithDescriptor:desc];
    if (!tex) return nil;

    return [[MetalTexture alloc] initWithTexture:tex];
}

@end
