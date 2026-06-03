// MetalTexture.h — Metal texture wrapper with descriptor helpers
// Matches 太阳神 MetalTexture helper class

#import <Metal/Metal.h>
#import <Foundation/Foundation.h>

@interface MetalTexture : NSObject

@property (nonatomic, strong, readonly) id<MTLTexture> texture;
@property (nonatomic, assign, readonly) NSUInteger width;
@property (nonatomic, assign, readonly) NSUInteger height;

- (instancetype)initWithTexture:(id<MTLTexture>)texture;
- (instancetype)initWithDevice:(id<MTLDevice>)device
                   descriptor:(MTLTextureDescriptor *)descriptor;

+ (instancetype)texture2DWithDevice:(id<MTLDevice>)device
                              width:(NSUInteger)width
                             height:(NSUInteger)height
                        pixelFormat:(MTLPixelFormat)format;

@end
