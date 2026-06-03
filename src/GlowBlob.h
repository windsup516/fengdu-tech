// GlowBlob.h — Animated glow blob element (matches 太阳神)
// Floating blob with pulse and float animations

#import <UIKit/UIKit.h>

@interface GlowBlob : UIView

@property (nonatomic, assign) CGFloat blobRadius;
@property (nonatomic, assign) CGFloat glowIntensity;
@property (nonatomic, assign) NSTimeInterval animationDuration;

- (instancetype)initWithRadius:(CGFloat)radius color:(UIColor *)color;
- (void)startFloating;
- (void)stopFloating;

@end
