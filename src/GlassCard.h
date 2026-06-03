// GlassCard.h — Frosted glass card component (matches 太阳神)
// UIView with blur effect + rounded corners + border glow

#import <UIKit/UIKit.h>

@interface GlassCard : UIView

@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, assign) CGFloat cornerRadius;
@property (nonatomic, assign) CGFloat blurIntensity;

- (instancetype)initWithCornerRadius:(CGFloat)radius;
- (void)setGlowColor:(UIColor *)color;

@end
