// GlowBlob.m — Animated glow blob implementation

#import "GlowBlob.h"

@interface GlowBlob ()
@property (nonatomic, strong) UIView *coreView;
@property (nonatomic, strong) UIColor *blobColor;
@property (nonatomic, assign) CGPoint originalCenter;
@end

@implementation GlowBlob

- (instancetype)initWithRadius:(CGFloat)radius color:(UIColor *)color {
    CGRect frame = CGRectMake(0, 0, radius * 2, radius * 2);
    self = [super initWithFrame:frame];
    if (self) {
        _blobRadius = radius;
        _blobColor = color;
        _glowIntensity = 0.5;
        _animationDuration = 3.0;
        self.backgroundColor = [UIColor clearColor];
        [self setupBlob];
    }
    return self;
}

- (void)setupBlob {
    // Outer glow layer
    self.layer.cornerRadius = _blobRadius;

    // Core circle
    _coreView = [[UIView alloc] initWithFrame:self.bounds];
    _coreView.backgroundColor = _blobColor;
    _coreView.layer.cornerRadius = _blobRadius;
    _coreView.alpha = 0.3;
    [self addSubview:_coreView];

    // Glow shadow
    self.layer.shadowColor = _blobColor.CGColor;
    self.layer.shadowRadius = _blobRadius * 2;
    self.layer.shadowOpacity = _glowIntensity;
    self.layer.shadowOffset = CGSizeZero;
}

- (void)startFloating {
    _originalCenter = self.center;

    // Float animation — random circular path
    CGFloat dx = (arc4random_uniform(20) - 10);
    CGFloat dy = (arc4random_uniform(20) - 10);

    CABasicAnimation *floatX = [CABasicAnimation animationWithKeyPath:@"position.x"];
    floatX.fromValue = @(self.center.x);
    floatX.toValue = @(self.center.x + dx);
    floatX.duration = _animationDuration;
    floatX.autoreverses = YES;
    floatX.repeatCount = HUGE_VALF;
    floatX.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [self.layer addAnimation:floatX forKey:@"floatX"];

    CABasicAnimation *floatY = [CABasicAnimation animationWithKeyPath:@"position.y"];
    floatY.fromValue = @(self.center.y);
    floatY.toValue = @(self.center.y + dy);
    floatY.duration = _animationDuration * 1.3;
    floatY.autoreverses = YES;
    floatY.repeatCount = HUGE_VALF;
    floatY.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [self.layer addAnimation:floatY forKey:@"floatY"];

    // Opacity pulse
    CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"opacity"];
    pulse.fromValue = @(0.15);
    pulse.toValue = @(_glowIntensity);
    pulse.duration = _animationDuration * 0.8;
    pulse.autoreverses = YES;
    pulse.repeatCount = HUGE_VALF;
    [_coreView.layer addAnimation:pulse forKey:@"pulse"];

    // Scale pulse
    CABasicAnimation *scalePulse = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
    scalePulse.fromValue = @(0.85);
    scalePulse.toValue = @(1.15);
    scalePulse.duration = _animationDuration * 1.1;
    scalePulse.autoreverses = YES;
    scalePulse.repeatCount = HUGE_VALF;
    scalePulse.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [self.layer addAnimation:scalePulse forKey:@"scalePulse"];
}

- (void)stopFloating {
    [self.layer removeAllAnimations];
    [_coreView.layer removeAllAnimations];
    self.center = _originalCenter;
}

@end
