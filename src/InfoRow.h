// InfoRow.h — Information row component (matches 太阳神)
// Key-value pair display row with optional icon + copy support

#import <UIKit/UIKit.h>

@interface InfoRow : UIView

@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *value;
@property (nonatomic, assign) BOOL showSeparator;
@property (nonatomic, assign) BOOL allowCopy;

- (instancetype)initWithTitle:(NSString *)title value:(NSString *)value;

@end
