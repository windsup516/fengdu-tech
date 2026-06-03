// StatusPill.m — Status indicator pill implementation
// Colored dot + label in a rounded pill container

#import "StatusPill.h"

@interface StatusPill ()
@property (nonatomic, strong) UIView *dotView;
@property (nonatomic, strong) UILabel *label;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@end

@implementation StatusPill

- (instancetype)initWithText:(NSString *)text state:(StatusPillState)state {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _statusText = text;
        _state = state;
        _fontSize = 12;
        [self setupViews];
    }
    return self;
}

- (void)setupViews {
    self.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.7];
    self.layer.cornerRadius = 12;
    self.layer.borderWidth = 0.5;
    self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.1].CGColor;

    // Colored dot
    _dotView = [[UIView alloc] initWithFrame:CGRectMake(6, 0, 8, 8)];
    _dotView.layer.cornerRadius = 4;
    _dotView.backgroundColor = [self colorForState:_state];
    [self addSubview:_dotView];

    // Label
    _label = [[UILabel alloc] initWithFrame:CGRectZero];
    _label.font = [UIFont monospacedSystemFontOfSize:_fontSize weight:UIFontWeightMedium];
    _label.text = _statusText;
    _label.textColor = [UIColor colorWithWhite:0.9 alpha:1.0];
    _label.textAlignment = NSTextAlignmentCenter;
    [self addSubview:_label];

    // Spinner (hidden by default)
    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    _spinner.transform = CGAffineTransformMakeScale(0.6, 0.6);
    _spinner.hidesWhenStopped = YES;
    [self addSubview:_spinner];

    [self updateStateDisplay];
}

- (UIColor *)colorForState:(StatusPillState)state {
    switch (state) {
        case StatusPillStateInactive: return [UIColor grayColor];
        case StatusPillStateLoading:  return [UIColor colorWithRed:1.0 green:0.75 blue:0.1 alpha:1.0];
        case StatusPillStateSuccess:  return [UIColor colorWithRed:0.2 green:0.8 blue:0.4 alpha:1.0];
        case StatusPillStateError:    return [UIColor colorWithRed:0.95 green:0.2 blue:0.2 alpha:1.0];
        case StatusPillStateWarning:  return [UIColor colorWithRed:1.0 green:0.5 blue:0.1 alpha:1.0];
    }
}

- (void)setState:(StatusPillState)state {
    [self setState:state animated:NO];
}

- (void)setState:(StatusPillState)state animated:(BOOL)animated {
    _state = state;
    if (animated) {
        [UIView animateWithDuration:0.3 animations:^{
            self->_dotView.backgroundColor = [self colorForState:state];
        }];
    } else {
        _dotView.backgroundColor = [self colorForState:state];
    }
    [self updateStateDisplay];
}

- (void)updateStateDisplay {
    if (_state == StatusPillStateLoading) {
        _dotView.hidden = YES;
        [_spinner startAnimating];
    } else {
        _dotView.hidden = NO;
        [_spinner stopAnimating];
    }
}

- (void)setStatusText:(NSString *)statusText {
    _statusText = statusText;
    _label.text = statusText;
}

- (CGSize)sizeThatFits:(CGSize)size {
    CGSize labelSize = [_label sizeThatFits:size];
    return CGSizeMake(labelSize.width + 28, 24);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat h = self.bounds.size.height;
    _dotView.center = CGPointMake(10, h / 2);
    _spinner.center = CGPointMake(10, h / 2);
    _label.frame = CGRectMake(18, 0, self.bounds.size.width - 24, h);
}

@end
