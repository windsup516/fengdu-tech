#ifndef APP_VIEW_CONTROLLER_H
#define APP_VIEW_CONTROLLER_H

#import <UIKit/UIKit.h>
#import "LoginViewController.h"

@interface AppViewController : LoginViewController

// UI 核心元素
@property (nonatomic, strong) UIButton *primaryButton;
@property (nonatomic, strong) UILabel *statusHeader;
@property (nonatomic, strong) UILabel *statusDetail;
@property (nonatomic, strong) UIView *statusCard;
@property (nonatomic, strong) UIView *statusPill;
@property (nonatomic, strong) UIView *progressTrack;
@property (nonatomic, strong) UIView *progressFill;
@property (nonatomic, strong) NSLayoutConstraint *progressFillWidth;
@property (nonatomic, strong) CAGradientLayer *primaryButtonGradient;
@property (nonatomic, strong) UIView *infoCard;
@property (nonatomic, strong) UILabel *infoCardHeader;
@property (nonatomic, strong) UILabel *infoCardCounter;
@property (nonatomic, strong) UILabel *flavorTitleLabel;
@property (nonatomic, strong) UIView *flavorSelector;
@property (nonatomic, strong) NSArray *flavorButtons;
@property (nonatomic, strong) NSArray *infoRows;
@property (nonatomic, strong) NSMutableArray *glowBlobs;
@property (nonatomic, strong) UILabel *footerLabel;
@property (nonatomic, strong) CAGradientLayer *backgroundGradient;
@property (nonatomic, strong) UILabel *brandLabel;
@property (nonatomic, strong) UILabel *brandSubLabel;
@property (nonatomic, strong) UIView *heroContainer;
@property (nonatomic, strong) CAShapeLayer *gridLayer;

// 状态标志
@property (nonatomic) BOOL hudVisible;
@property (nonatomic) BOOL didRunEntryAnimation;
@property (nonatomic) BOOL serviceLoading;
@property (nonatomic) BOOL serviceReady;
@property (nonatomic) BOOL listening;
@property (nonatomic) BOOL didInstallLayout;

// 数据
@property (nonatomic, strong) NSString *selectedFlavor;
@property (nonatomic, strong) NSString *statusText;

// 方法
- (void)installBackground;
- (void)installHero;
- (void)installFlavorSelector;
- (void)installInfoCard;
- (void)installStatusCard;
- (void)installPrimaryButton;
- (void)installFooter;
- (void)refreshDeviceInfo;
- (void)setStatus:(NSString *)status detail:(NSString *)detail kind:(NSInteger)kind;
- (void)setServiceLoading:(BOOL)loading;
- (void)toggleHUD;
- (void)updatePrimaryButtonAppearance;
- (void)startServiceBootstrap;
- (void)prepareForEntryAnimation;
- (void)runEntryAnimationIfNeeded;
- (UIView *)addGlowBlobAtAnchor:(CGPoint)anchor tint:(UIColor *)tint size:(CGFloat)size;

@end
#endif
