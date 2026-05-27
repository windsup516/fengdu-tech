#ifndef LOGIN_VIEW_CONTROLLER_H
#define LOGIN_VIEW_CONTROLLER_H

#import <UIKit/UIKit.h>

@interface LoginViewController : UIViewController

@property (nonatomic, copy) void (^onAuthorized)(void);

// UI Elements (匹配反编译)
@property (nonatomic, strong) UITextField *keyField;
@property (nonatomic, strong) UIButton *submitButton;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIView *cardView;

// Methods
- (IBAction)submitTapped;
- (IBAction)clearSavedKey:(id)sender;
- (void)setLoading:(BOOL)loading;
- (void)setStatusText:(NSString *)text color:(UIColor *)color;
- (void)installBackground;
- (void)installHero;
- (void)installCard;
- (void)installClearKeyButton;

@end
#endif
