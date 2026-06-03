// DFMetalContext.m — Singleton Metal device + buffer pool + font texture
// Matches 太阳神 DFMetalContext for GPU resource management

#import "DFMetalContext.h"
#import <MetalKit/MetalKit.h>
#import <mach/mach_time.h>

// Buffer pool constants
#define BUFFER_POOL_MAX_SIZE 16
#define BUFFER_POOL_MAX_AGE   5.0  // seconds before recycling

@interface DFMetalContext ()
@property (nonatomic, strong, readwrite) id<MTLDevice> device;
@property (nonatomic, strong, readwrite) id<MTLCommandQueue> commandQueue;
@property (nonatomic, strong, readwrite) id<MTLTexture> fontTexture;
@property (nonatomic, strong) NSMutableArray<DFMetalBuffer *> *bufferPool;
@property (nonatomic, strong) dispatch_queue_t poolQueue;
@end

@implementation DFMetalContext

+ (instancetype)shared {
    static DFMetalContext *inst = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        inst = [[DFMetalContext alloc] init];
    });
    return inst;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _bufferPool = [NSMutableArray arrayWithCapacity:BUFFER_POOL_MAX_SIZE];
        _poolQueue = dispatch_queue_create("com.df.metal.pool", DISPATCH_QUEUE_SERIAL);
        [self makeDeviceObjects];
    }
    return self;
}

- (void)makeDeviceObjects {
    _device = MTLCreateSystemDefaultDevice();
    if (!_device) {
        NSLog(@"[DFMetalContext] FATAL: No Metal device available");
        return;
    }
    _commandQueue = [_device newCommandQueue];
    [self makeFontTexture];
}

- (void)makeFontTexture {
    if (!_device) return;

    // Create a small 512x64 texture for font atlas
    MTLTextureDescriptor *desc = [MTLTextureDescriptor
        texture2DDescriptorWithPixelFormat:MTLPixelFormatR8Unorm
                                     width:512
                                    height:64
                                 mipmapped:NO];
    desc.usage = MTLTextureUsageShaderRead | MTLTextureUsageRenderTarget;
    desc.storageMode = MTLStorageModeShared;

    _fontTexture = [_device newTextureWithDescriptor:desc];
    if (!_fontTexture) {
        // Fallback: smaller texture
        desc.width = 256;
        desc.height = 32;
        _fontTexture = [_device newTextureWithDescriptor:desc];
    }
}

- (DFMetalBuffer *)dequeueReusableBufferOfLength:(NSUInteger)length {
    if (length == 0) return nil;

    __block DFMetalBuffer *found = nil;

    dispatch_sync(_poolQueue, ^{
        NSTimeInterval now = CACurrentMediaTime();

        // Try to find a recyclable buffer of suitable size
        for (DFMetalBuffer *mb in self->_bufferPool) {
            if (mb.buffer.length >= length && (now - mb.lastReuseTime) > 0.5) {
                found = mb;
                break;
            }
        }

        if (found) {
            [self->_bufferPool removeObject:found];
        }
    });

    if (found) {
        found.lastReuseTime = CACurrentMediaTime();
        return found;
    }

    // Create new buffer
    id<MTLBuffer> buf = [_device newBufferWithLength:length
                                             options:MTLResourceStorageModeShared];
    if (!buf) return nil;

    return [DFMetalBuffer bufferWithMTLBuffer:buf];
}

- (void)recycleBuffer:(DFMetalBuffer *)metalBuffer {
    if (!metalBuffer) return;

    dispatch_async(_poolQueue, ^{
        // Trim pool if too large
        while (self->_bufferPool.count >= BUFFER_POOL_MAX_SIZE) {
            [self->_bufferPool removeObjectAtIndex:0];
        }
        metalBuffer.lastReuseTime = CACurrentMediaTime();
        [self->_bufferPool addObject:metalBuffer];
    });
}

@end
