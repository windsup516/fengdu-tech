// KernelLogoView.m — Animated kernel/crosshair logo
// Matches 太阳神 multi-layer CAShapeLayer 60fps animation system
// Layers: dot, dotGlow, orbitArc, innerCore, midRing, outerRing,
//          crossLayer, bullet, innerStroke, gridLayer, glowBlobs

#import "KernelLogoView.h"
#import <QuartzCore/QuartzCore.h>

@interface KernelLogoView ()
@property (nonatomic, strong) CAShapeLayer *dotLayer;
@property (nonatomic, strong) CAShapeLayer *dotGlowLayer;
@property (nonatomic, strong) CAShapeLayer *orbitArc;
@property (nonatomic, strong) CAShapeLayer *innerCore;
@property (nonatomic, strong) CAShapeLayer *midRing;
@property (nonatomic, strong) CAShapeLayer *outerRing;
@property (nonatomic, strong) CAShapeLayer *crossLayer;
@property (nonatomic, strong) CAShapeLayer *bullet;
@property (nonatomic, strong) CAShapeLayer *innerStroke;
@property (nonatomic, strong) CAShapeLayer *gridLayer;
@property (nonatomic, strong) NSMutableArray<CAShapeLayer *> *glowBlobs;
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, assign) CFTimeInterval startTime;
@property (nonatomic, assign) CGFloat rotationAngle;
@end

@implementation KernelLogoView

- (instancetype)initWithSize:(CGFloat)size tintColor:(UIColor *)color {
    CGRect frame = CGRectMake(0, 0, size, size);
    self = [super initWithFrame:frame];
    if (self) {
        _logoSize = size;
        _tintColor = color ?: [UIColor colorWithRed:0.2 green:0.65 blue:0.98 alpha:1.0];
        _rotationAngle = 0;
        self.backgroundColor = [UIColor clearColor];
        [self setupLayers];
    }
    return self;
}

- (void)setupLayers {
    CGFloat cx = self.bounds.size.width / 2;
    CGFloat cy = self.bounds.size.height / 2;
    CGFloat r = MIN(cx, cy) * 0.85;

    CGColorRef tint = self.tintColor.CGColor;

    // Outer ring — full circle with glow
    _outerRing = [CAShapeLayer layer];
    _outerRing.path = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(cx-r, cy-r, r*2, r*2)].CGPath;
    _outerRing.fillColor = nil;
    _outerRing.strokeColor = tint;
    _outerRing.lineWidth = 1.5;
    _outerRing.opacity = 0.3;
    [self.layer addSublayer:_outerRing];

    // Mid ring — dashed
    _midRing = [CAShapeLayer layer];
    _midRing.path = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(cx-r*0.75, cy-r*0.75, r*1.5, r*1.5)].CGPath;
    _midRing.fillColor = nil;
    _midRing.strokeColor = tint;
    _midRing.lineWidth = 1.0;
    _midRing.lineDashPattern = @[@4, @8];
    _midRing.opacity = 0.5;
    [self.layer addSublayer:_midRing];

    // Inner core — solid circle
    _innerCore = [CAShapeLayer layer];
    _innerCore.path = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(cx-r*0.15, cy-r*0.15, r*0.3, r*0.3)].CGPath;
    _innerCore.fillColor = tint;
    _innerCore.opacity = 0.6;
    [self.layer addSublayer:_innerCore];

    // Inner stroke — thin ring around core
    _innerStroke = [CAShapeLayer layer];
    _innerStroke.path = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(cx-r*0.2, cy-r*0.2, r*0.4, r*0.4)].CGPath;
    _innerStroke.fillColor = nil;
    _innerStroke.strokeColor = tint;
    _innerStroke.lineWidth = 0.8;
    _innerStroke.opacity = 0.8;
    [self.layer addSublayer:_innerStroke];

    // Center dot
    _dotLayer = [CAShapeLayer layer];
    _dotLayer.path = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(cx-3, cy-3, 6, 6)].CGPath;
    _dotLayer.fillColor = [UIColor whiteColor].CGColor;
    _dotLayer.opacity = 0.9;
    [self.layer addSublayer:_dotLayer];

    // Dot glow — larger blurry circle
    _dotGlowLayer = [CAShapeLayer layer];
    CGFloat glowR = 12;
    _dotGlowLayer.path = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(cx-glowR, cy-glowR, glowR*2, glowR*2)].CGPath;
    _dotGlowLayer.fillColor = tint;
    _dotGlowLayer.opacity = 0.15;
    _dotGlowLayer.shadowColor = tint;
    _dotGlowLayer.shadowRadius = 15;
    _dotGlowLayer.shadowOpacity = 0.5;
    _dotGlowLayer.shadowOffset = CGSizeZero;
    [self.layer addSublayer:_dotGlowLayer];

    // Crosshair lines
    UIBezierPath *crossPath = [UIBezierPath bezierPath];
    CGFloat cl = r * 0.5;
    [crossPath moveToPoint:CGPointMake(cx, cy-cl)];
    [crossPath addLineToPoint:CGPointMake(cx, cy-r*0.22)];
    [crossPath moveToPoint:CGPointMake(cx, cy+r*0.22)];
    [crossPath addLineToPoint:CGPointMake(cx, cy+cl)];
    [crossPath moveToPoint:CGPointMake(cx-cl, cy)];
    [crossPath addLineToPoint:CGPointMake(cx-r*0.22, cy)];
    [crossPath moveToPoint:CGPointMake(cx+r*0.22, cy)];
    [crossPath addLineToPoint:CGPointMake(cx+cl, cy)];
    _crossLayer = [CAShapeLayer layer];
    _crossLayer.path = crossPath.CGPath;
    _crossLayer.strokeColor = tint;
    _crossLayer.lineWidth = 1.2;
    _crossLayer.lineCap = kCALineCapRound;
    _crossLayer.opacity = 0.7;
    [self.layer addSublayer:_crossLayer];

    // Orbit arc — partial circle
    UIBezierPath *arcPath = [UIBezierPath bezierPathWithArcCenter:CGPointMake(cx, cy)
                                                            radius:r*0.55
                                                        startAngle:-M_PI_4
                                                          endAngle:M_PI_4
                                                         clockwise:YES];
    _orbitArc = [CAShapeLayer layer];
    _orbitArc.path = arcPath.CGPath;
    _orbitArc.fillColor = nil;
    _orbitArc.strokeColor = [UIColor colorWithRed:0.4 green:0.8 blue:1.0 alpha:1.0].CGColor;
    _orbitArc.lineWidth = 2.0;
    _orbitArc.lineCap = kCALineCapRound;
    _orbitArc.opacity = 0.8;
    [self.layer addSublayer:_orbitArc];

    // Bullet indicator — small triangle
    UIBezierPath *bulletPath = [UIBezierPath bezierPath];
    CGFloat bx = cx, by = cy - r*0.55;
    CGFloat bw = 5;
    [bulletPath moveToPoint:CGPointMake(bx, by - bw*2)];
    [bulletPath addLineToPoint:CGPointMake(bx - bw, by)];
    [bulletPath addLineToPoint:CGPointMake(bx + bw, by)];
    [bulletPath closePath];
    _bullet = [CAShapeLayer layer];
    _bullet.path = bulletPath.CGPath;
    _bullet.fillColor = [UIColor whiteColor].CGColor;
    _bullet.opacity = 0.9;
    [self.layer addSublayer:_bullet];

    // Grid lines — subtle radial grid
    UIBezierPath *gridPath = [UIBezierPath bezierPath];
    for (int i = 0; i < 8; i++) {
        CGFloat angle = i * M_PI_4;
        CGFloat gx1 = cx + cos(angle) * r*0.25;
        CGFloat gy1 = cy + sin(angle) * r*0.25;
        CGFloat gx2 = cx + cos(angle) * r*0.65;
        CGFloat gy2 = cy + sin(angle) * r*0.65;
        [gridPath moveToPoint:CGPointMake(gx1, gy1)];
        [gridPath addLineToPoint:CGPointMake(gx2, gy2)];
    }
    _gridLayer = [CAShapeLayer layer];
    _gridLayer.path = gridPath.CGPath;
    _gridLayer.strokeColor = tint;
    _gridLayer.lineWidth = 0.3;
    _gridLayer.opacity = 0.15;
    [self.layer addSublayer:_gridLayer];

    // Glow blobs — 3 floating blobs
    _glowBlobs = [NSMutableArray array];
    CGFloat blobPositions[][2] = {{-0.4, -0.3}, {0.35, 0.25}, {-0.2, 0.4}};
    for (int i = 0; i < 3; i++) {
        CAShapeLayer *blob = [CAShapeLayer layer];
        CGFloat br = r * (0.06 + i * 0.02);
        CGFloat bpx = cx + blobPositions[i][0] * r;
        CGFloat bpy = cy + blobPositions[i][1] * r;
        blob.path = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(bpx-br, bpy-br, br*2, br*2)].CGPath;
        blob.fillColor = tint;
        blob.opacity = 0.3 + i * 0.1;
        blob.shadowColor = tint;
        blob.shadowRadius = 8;
        blob.shadowOpacity = 0.4;
        blob.shadowOffset = CGSizeZero;
        [self.layer addSublayer:blob];
        [_glowBlobs addObject:blob];
    }
}

- (void)startAnimation {
    if (self.animating) return;
    self.animating = YES;
    self.startTime = CACurrentMediaTime();

    // Rotation animation on outer ring
    CABasicAnimation *outerRotate = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
    outerRotate.fromValue = @(0);
    outerRotate.toValue = @(M_PI * 2);
    outerRotate.duration = 8.0;
    outerRotate.repeatCount = HUGE_VALF;
    [_outerRing addAnimation:outerRotate forKey:@"outerRotate"];

    // Reverse rotation on mid ring
    CABasicAnimation *midRotate = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
    midRotate.fromValue = @(0);
    midRotate.toValue = @(-M_PI * 2);
    midRotate.duration = 6.0;
    midRotate.repeatCount = HUGE_VALF;
    [_midRing addAnimation:midRotate forKey:@"midRotate"];

    // Orbit arc rotation (faster)
    CABasicAnimation *orbitRotate = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
    orbitRotate.fromValue = @(0);
    orbitRotate.toValue = @(M_PI * 2);
    orbitRotate.duration = 3.0;
    orbitRotate.repeatCount = HUGE_VALF;
    [_orbitArc addAnimation:orbitRotate forKey:@"orbitRotate"];

    // Bullet orbits with arc
    CABasicAnimation *bulletRotate = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
    bulletRotate.fromValue = @(0);
    bulletRotate.toValue = @(M_PI * 2);
    bulletRotate.duration = 3.0;
    bulletRotate.repeatCount = HUGE_VALF;
    [_bullet addAnimation:bulletRotate forKey:@"bulletRotate"];

    // Dot glow pulse
    CAKeyframeAnimation *glowPulse = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
    glowPulse.values = @[@0.1, @0.3, @0.1];
    glowPulse.keyTimes = @[@0, @0.5, @1.0];
    glowPulse.duration = 2.0;
    glowPulse.repeatCount = HUGE_VALF;
    [_dotGlowLayer addAnimation:glowPulse forKey:@"glowPulse"];

    // Crosshair fade
    CAKeyframeAnimation *crossFade = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
    crossFade.values = @[@0.5, @0.9, @0.5];
    crossFade.keyTimes = @[@0, @0.5, @1.0];
    crossFade.duration = 1.5;
    crossFade.repeatCount = HUGE_VALF;
    [_crossLayer addAnimation:crossFade forKey:@"crossFade"];

    // Blob float animation
    for (int i = 0; i < _glowBlobs.count; i++) {
        CAShapeLayer *blob = _glowBlobs[i];
        CAKeyframeAnimation *blobFloat = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation"];
        CGFloat phase = i * 2.0;
        blobFloat.values = @[
            [NSValue valueWithCGPoint:CGPointMake(0, 0)],
            [NSValue valueWithCGPoint:CGPointMake(5, -5)],
            [NSValue valueWithCGPoint:CGPointMake(-3, -2)],
            [NSValue valueWithCGPoint:CGPointMake(0, 0)],
        ];
        blobFloat.keyTimes = @[@0, @0.33, @0.66, @1.0];
        blobFloat.duration = 3.0 + phase;
        blobFloat.repeatCount = HUGE_VALF;
        [blob addAnimation:blobFloat forKey:@"blobFloat"];

        CAKeyframeAnimation *blobOpacity = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
        blobOpacity.values = @[@0.2, @0.5, @0.2];
        blobOpacity.keyTimes = @[@0, @0.5, @1.0];
        blobOpacity.duration = 2.5 + phase;
        blobOpacity.repeatCount = HUGE_VALF;
        [blob addAnimation:blobOpacity forKey:@"blobOpacity"];
    }

    // DisplayLink for fine-grained updates
    self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(displayLinkTick:)];
    [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)displayLinkTick:(CADisplayLink *)link {
    CFTimeInterval elapsed = link.timestamp - self.startTime;
    // Subtle core pulse
    CGFloat pulse = 1.0 + 0.1 * sin(elapsed * 3.0);
    _innerCore.transform = CATransform3DMakeScale(pulse, pulse, 1.0);
    _dotLayer.opacity = 0.7 + 0.2 * sin(elapsed * 4.0);
}

- (void)stopAnimation {
    self.animating = NO;
    [_outerRing removeAllAnimations];
    [_midRing removeAllAnimations];
    [_orbitArc removeAllAnimations];
    [_bullet removeAllAnimations];
    [_dotGlowLayer removeAllAnimations];
    [_crossLayer removeAllAnimations];
    for (CAShapeLayer *blob in _glowBlobs) {
        [blob removeAllAnimations];
    }
    [self.displayLink invalidate];
    self.displayLink = nil;
}

- (void)setProgress:(CGFloat)progress animated:(BOOL)animated {
    CGFloat clamped = MIN(1.0, MAX(0.0, progress));
    if (animated) {
        [CATransaction begin];
        [CATransaction setAnimationDuration:0.3];
    }
    _orbitArc.strokeEnd = 0.1 + clamped * 0.9;
    _outerRing.opacity = 0.15 + clamped * 0.25;
    _innerCore.opacity = 0.2 + clamped * 0.6;
    if (animated) {
        [CATransaction commit];
    }
}

- (void)dealloc {
    [self stopAnimation];
}

@end
