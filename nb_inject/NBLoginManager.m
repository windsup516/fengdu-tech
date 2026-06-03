// NBLoginManager.m — 16位卡密验证实现
#import "NBLoginManager.h"

static NSString *const kNBDefaultsKey = @"nb_card_key_v2";
static NSString *const kNBDefaultsActive = @"nb_activated_v2";

@implementation NBLoginManager {
    BOOL _isActivated;
    NSString *_currentKey;
}

+ (instancetype)shared {
    static NBLoginManager *inst = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ inst = [[NBLoginManager alloc] init]; });
    return inst;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _isActivated = NO;
        [self loadSavedState];
    }
    return self;
}

- (BOOL)verifyKey:(NSString *)key {
    if (!key || key.length != 16) return NO;
    // 当前版本：任意16位字符即可
    _isActivated = YES;
    _currentKey = [key copy];
    [self saveActivatedState:key];
    return YES;
}

- (void)loadSavedState {
    NSString *saved = [[NSUserDefaults standardUserDefaults] stringForKey:kNBDefaultsActive];
    NSString *key = [[NSUserDefaults standardUserDefaults] stringForKey:kNBDefaultsKey];
    if ([saved isEqualToString:@"YES"] && key.length == 16) {
        _isActivated = YES;
        _currentKey = key;
    }
}

- (void)saveActivatedState:(NSString *)key {
    [[NSUserDefaults standardUserDefaults] setObject:@"YES" forKey:kNBDefaultsActive];
    [[NSUserDefaults standardUserDefaults] setObject:key forKey:kNBDefaultsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (BOOL)isActivated { return _isActivated; }
- (NSString *)currentKey { return _currentKey; }

@end
