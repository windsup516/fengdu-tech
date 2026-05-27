#ifndef APP_VIEW_CONTROLLER_H
#define APP_VIEW_CONTROLLER_H

#import <UIKit/UIKit.h>

@interface AppViewController : UIViewController

@property (nonatomic, copy) void (^onAuthorized)(void);

@property (nonatomic, strong) UIButton *primaryButton;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *statusHeader;
@property (nonatomic, strong) UILabel *statusDetail;
@property (nonatomic, strong) UIView *statusCard;
@property (nonatomic, strong) UIView *infoCard;
@property (nonatomic, strong) UILabel *infoCardHeader;
@property (nonatomic, strong) UILabel *infoCardCounter;
@property (nonatomic, strong) UILabel *flavorTitleLabel;
@property (nonatomic, strong) UIView *flavorSelector;
@property (nonatomic, strong) NSArray *flavorButtons;
@property (nonatomic, strong) NSArray *infoRows;
@property (nonatomic, strong) NSMutableArray *glowBlobs;

@property (nonatomic) BOOL serviceLoading;
@property (nonatomic) BOOL serviceReady;
@property (nonatomic, strong) NSString *selectedFlavor;
@property (nonatomic, strong) NSString *statusText;

- (void)installBackground;
- (void)installFlavorSelector;
- (void)installInfoCard;
- (void)installStatusCard;
- (void)installPrimaryButton;
- (void)installFooter;
- (void)refreshDeviceInfo;
- (void)setStatus:(NSString *)status detail:(NSString *)detail kind:(NSInteger)kind;
- (void)setServiceLoading:(BOOL)loading;

@end
#endif
