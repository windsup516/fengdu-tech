// StatusPill.h — Status indicator pill component (matches 太阳神)
// Small rounded pill showing status text with colored dot

#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, StatusPillState) {
    StatusPillStateInactive = 0,
    StatusPillStateLoading,
    StatusPillStateSuccess,
    StatusPillStateError,
    StatusPillStateWarning,
};

@interface StatusPill : UIView

@property (nonatomic, assign) StatusPillState state;
@property (nonatomic, copy) NSString *statusText;
@property (nonatomic, assign) CGFloat fontSize;

- (instancetype)initWithText:(NSString *)text state:(StatusPillState)state;
- (void)setState:(StatusPillState)state animated:(BOOL)animated;

@end
