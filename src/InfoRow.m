// InfoRow.m — Information row implementation

#import "InfoRow.h"

@interface InfoRow ()
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *valueLabel;
@property (nonatomic, strong) UIView *separator;
@end

@implementation InfoRow

- (instancetype)initWithTitle:(NSString *)title value:(NSString *)value {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _title = title;
        _value = value;
        _showSeparator = YES;
        _allowCopy = NO;
        [self setupViews];
    }
    return self;
}

- (void)setupViews {
    _titleLabel = [[UILabel alloc] init];
    _titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    _titleLabel.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
    _titleLabel.text = _title;
    [self addSubview:_titleLabel];

    _valueLabel = [[UILabel alloc] init];
    _valueLabel.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    _valueLabel.textColor = [UIColor colorWithWhite:0.9 alpha:1.0];
    _valueLabel.text = _value;
    _valueLabel.textAlignment = NSTextAlignmentRight;
    _valueLabel.adjustsFontSizeToFitWidth = YES;
    [self addSubview:_valueLabel];

    _separator = [[UIView alloc] init];
    _separator.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.06];
    [self addSubview:_separator];

    if (_allowCopy) {
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                              action:@selector(handleTap)];
        [self addGestureRecognizer:tap];
    }
}

- (void)handleTap {
    if (_value.length > 0) {
        [[UIPasteboard generalPasteboard] setString:_value];
        // Brief visual feedback
        _valueLabel.textColor = [UIColor colorWithRed:0.3 green:0.7 blue:1.0 alpha:1.0];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            self->_valueLabel.textColor = [UIColor colorWithWhite:0.9 alpha:1.0];
        });
    }
}

- (void)setTitle:(NSString *)title {
    _title = title;
    _titleLabel.text = title;
}

- (void)setValue:(NSString *)value {
    _value = value;
    _valueLabel.text = value;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;

    [_titleLabel sizeToFit];
    _titleLabel.frame = CGRectMake(0, 0, w * 0.4, h);

    [_valueLabel sizeToFit];
    CGFloat vw = w * 0.55;
    _valueLabel.frame = CGRectMake(w - vw, 0, vw, h);

    if (_showSeparator) {
        _separator.frame = CGRectMake(0, h - 1, w, 0.5);
    } else {
        _separator.frame = CGRectZero;
    }
}

- (CGSize)sizeThatFits:(CGSize)size {
    return CGSizeMake(size.width, 28);
}

@end
