// KernelLogoView.h — Animated kernel/crosshair logo matching 太阳神
// Multi-layer CAShapeLayer animation at 60fps

#import <UIKit/UIKit.h>

@interface KernelLogoView : UIView

@property (nonatomic, assign) CGFloat logoSize;
@property (nonatomic, assign) BOOL animating;
@property (nonatomic, strong) UIColor *tintColor;

- (instancetype)initWithSize:(CGFloat)size tintColor:(UIColor *)color;
- (void)startAnimation;
- (void)stopAnimation;
- (void)setProgress:(CGFloat)progress animated:(BOOL)animated;

@end
