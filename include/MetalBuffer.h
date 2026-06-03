// MetalBuffer.h — Reusable Metal buffer pool
// Matches 太阳神 MetalBuffer class for GPU buffer management

#import <Metal/Metal.h>
#import <Foundation/Foundation.h>

@interface MetalBuffer : NSObject

@property (nonatomic, strong, readonly) id<MTLBuffer> buffer;
@property (nonatomic, assign) NSTimeInterval lastReuseTime;

- (instancetype)initWithBuffer:(id<MTLBuffer>)buffer;
+ (instancetype)bufferWithMTLBuffer:(id<MTLBuffer>)buffer;

@end
