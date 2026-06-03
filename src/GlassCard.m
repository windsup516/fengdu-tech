// GlassCard.m — Frosted glass card implementation
// Uses UIVisualEffectView + gradient border + shadow for glassmorphism effect

#import "GlassCard.h"

@interface GlassCard ()
@property (nonatomic, strong) UIVisualEffectView *blurView;
@property (nonatomic, strong) CAGradientLayer *borderGradient;
@property (nonatomic, strong) UIColor *glowColor;
@end

@implementation GlassCard

- (instancetype)initWithCornerRadius:(CGFloat)radius {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _cornerRadius = radius;
        _blurIntensity = 1.0;
        _glowColor = [UIColor colorWithRed:0.3 green:0.6 blue:0.9 alpha:0.3];
        [self setupViews];
    }
    return self;
}

- (void)setupViews {
    self.backgroundColor = [UIColor clearColor];
    self.layer.cornerRadius = _cornerRadius;
    self.layer.masksToBounds = YES;
    self.layer.borderWidth = 0.5;
    self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.15].CGColor;

    // Blur background
    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    _blurView = [[UIVisualEffectView alloc] initWithEffect:blur];
    _blurView.frame = self.bounds;
    _blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _blurView.layer.cornerRadius = _cornerRadius;
    _blurView.clipsToBounds = YES;
    _blurView.alpha = 0.85;
    [self insertSubview:_blurView atIndex:0];

    // Content view inside blur
    _contentView = [[UIView alloc] initWithFrame:self.bounds];
    _contentView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _contentView.backgroundColor = [UIColor colorWithWhite:0.05 alpha:0.3];
    [self addSubview:_contentView];

    // Top highlight gradient
    _borderGradient = [CAGradientLayer layer];
    _borderGradient.frame = self.bounds;
    _borderGradient.colors = @[
        (id)[UIColor colorWithWhite:1.0 alpha:0.12].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:0.02].CGColor,
    ];
    _borderGradient.locations = @[@0.0, @1.0];
    _borderGradient.cornerRadius = _cornerRadius;
    [self.layer addSublayer:_borderGradient];

    // Shadow (on the view itself, not layer — for glow effect)
    self.layer.shadowColor = _glowColor.CGColor;
    self.layer.shadowOpacity = 0.4;
    self.layer.shadowRadius = 12;
    self.layer.shadowOffset = CGSizeMake(0, 2);

    // Inner content inset
    _contentView.layoutMargins = UIEdgeInsetsMake(12, 16, 12, 16);
}

- (void)setGlowColor:(UIColor *)color {
    _glowColor = color;
    self.layer.shadowColor = color.CGColor;
    [self setNeedsDisplay];
}

- (void)setCornerRadius:(CGFloat)cornerRadius {
    _cornerRadius = cornerRadius;
    self.layer.cornerRadius = cornerRadius;
    _blurView.layer.cornerRadius = cornerRadius;
    _borderGradient.cornerRadius = cornerRadius;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _borderGradient.frame = self.bounds;
    // Update shadow path
    self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.bounds
                                                       cornerRadius:_cornerRadius].CGPath;
}

@end
