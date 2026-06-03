// MetalContext.h — Metal device + command queue management
// Matches 太阳神 MetalContext: singleton GPU context with font texture

#import <Metal/Metal.h>
#import <Foundation/Foundation.h>
#import "MetalBuffer.h"

@interface MetalContext : NSObject

@property (nonatomic, strong, readonly) id<MTLDevice> device;
@property (nonatomic, strong, readonly) id<MTLCommandQueue> commandQueue;
@property (nonatomic, strong, readonly) id<MTLTexture> fontTexture;

+ (instancetype)shared;

- (void)makeDeviceObjects;
- (void)makeFontTexture;
- (MetalBuffer *)dequeueReusableBufferOfLength:(NSUInteger)length;

@end
