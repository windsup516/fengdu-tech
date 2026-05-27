#ifndef METAL_RENDERER_H
#define METAL_RENDERER_H

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>

@class CAMetalLayer;

@interface MetalRenderer : NSObject

- (instancetype)initWithDevice:(id<MTLDevice>)device 
                         layer:(CAMetalLayer *)layer 
                   commandQueue:(id<MTLCommandQueue>)commandQueue;
- (void)setupRenderPipeline;
- (void)beginFrame;
- (void)endFrame;
- (void)drawWithDrawable:(id<CAMetalDrawable>)drawable;

@end
#endif
