// DFMetalBuffer.m — Reusable Metal buffer with lastReuseTime tracking
// Matches 太阳神 DFMetalBuffer for buffer pool management

#import <QuartzCore/QuartzCore.h>
#import "MetalBuffer.h"

@implementation DFMetalBuffer

- (instancetype)initWithBuffer:(id<MTLBuffer>)buffer {
    self = [super init];
    if (self) {
        _buffer = buffer;
        _lastReuseTime = CACurrentMediaTime();
    }
    return self;
}

+ (instancetype)bufferWithMTLBuffer:(id<MTLBuffer>)buffer {
    return [[DFMetalBuffer alloc] initWithBuffer:buffer];
}

- (void)setLastReuseTime:(NSTimeInterval)time {
    _lastReuseTime = time;
}

- (void)dealloc {
    _buffer = nil;
}

@end
