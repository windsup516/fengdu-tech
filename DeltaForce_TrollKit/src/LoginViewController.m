// LoginViewController - 授权登录界面
// 基于反编译: LoginViewController / submitTapped / handleAuthResponse
// 字符串加密: splitmix64 + NEON XOR
// 防封网关验证: 仅允许通过 202.189.9.12 防封代理的设备使用

#import "LoginViewController.h"
#import "CryptoUtils.h"
#import <arpa/inet.h>
#import <sys/socket.h>
#import <netdb.h>
// NetworkManager.h — 服务器验证模块 (测试阶段暂不启用)

// 防封网关配置
#define ANTIBAN_HOST @"202.189.9.12"
#define ANTIBAN_PORT 443   // 用 HTTPS 端口做连通检测，不易被防火墙拦截
#define ANTIBAN_TIMEOUT 5  // 超时秒数

// NEON XOR 解密引擎使用的常量 (从反编译恢复)
static const uint8_t byte_10013838F[16] = {0x5d,0x4c,0x15,0x5a,0x1c,0x53,0x0a,0x12,0x5a,0x40,0x12,0x49,0x44,0x57,0x49,0x1c};
static const uint8_t byte_100138372[29] = {0x31,0x4f,0x12,0x09,0x52,0x06,0x09,0x0b,0x47,0x0f,0x0a,0x46,0x4f,0x07,0x01,0x0b,0x06,0x04,0x44,0x02,0x0a,0x4f,0x09,0x0c,0x02,0x46,0x07,0x17,0x41};
static const uint8_t byte_10013839F[7]  = {0x4a,0x45,0x0e,0x45,0x0d,0x0e,0x46};
static const uint8_t byte_1001383B7[29] = {0x2f,0x0b,0x04,0x0e,0x09,0x4a,0x45,0x0e,0x45,0x0d,0x0e,0x46,0x4f,0x07,0x01,0x0b,0x06,0x04,0x44,0x02,0x0a,0x4f,0x09,0x0c,0x02,0x46,0x07,0x17,0x41};
static const uint8_t byte_1001383D4[42] = {0x26,0x4a,0x40,0x0d,0x4a,0x07,0x01,0x0b,0x06,0x04,0x44,0x02,0x0a,0x4f,0x09,0x0c,0x02,0x46,0x07,0x17,0x4a,0x4c,0x2e,0x4c,0x08,0x47,0x94,0x63,0x33,0x7b,0x37,0x32,0x64,0x7b,0x38,0x3c,0x7b,0x33,0x7a,0x37,0x3b,0x68};
static const uint8_t byte_1001383A6[17] = {0x4e,0x4a,0x4e,0x47,0x0e,0x45,0x0d,0x0e,0x46,0x0f,0x0a,0x46,0x4f,0x07,0x01,0x0b,0x06};
static const uint8_t byte_100138324[26] = {0x21,0x06,0x0e,0x45,0x0d,0x0e,0x46,0x4f,0x07,0x01,0x0b,0x06,0x04,0x44,0x02,0x0a,0x04,0x45,0x0d,0x4c,0x0c,0x57,0x44,0x4a,0x44,0x5a};
static const uint8_t byte_1001383FE[25] = {0x2a,0x0e,0x0d,0x46,0x4f,0x07,0x01,0x0b,0x06,0x04,0x44,0x02,0x0a,0x4f,0x09,0x0c,0x02,0x46,0x07,0x17,0x4a,0x4c,0x2e,0x4c,0x08};

typedef struct {
    int64_t state;
    int64_t seed;
    int length;
    const uint8_t *bytes;
} EncryptedString;

@interface LoginViewController ()
@property (nonatomic) BOOL inFlight;
@property (nonatomic, strong) void (^pendingRetry)(void);
@end

@implementation LoginViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // 暗黑背景
    self.view.backgroundColor = [UIColor colorWithRed:0.031 green:0.039 blue:0.078 alpha:1.0];
    
    // 安装 UI 组件
    [self installBackground];
    [self installHero];
    [self installCard];
    [self installClearKeyButton];
    
    // 检查已保存密钥
    NSString *savedKey = [self loadSavedKey];
    if (savedKey.length == 32) {
        self.keyField.text = savedKey;
        NSString *loadedText = DecryptBytes(byte_100138324, 0x60633644713B5348LL, 26);
        self.statusLabel.text = loadedText;
    }
}

#pragma mark - Submit

- (IBAction)submitTapped {
    if (self.inFlight) return;
    
    NSString *rawKey = self.keyField.text;
    NSString *trimmedKey = [rawKey stringByTrimmingCharactersInSet:
                            [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
    if (trimmedKey.length == 32) {
        [self.keyField resignFirstResponder];
        [self setLoading:YES];
        
        // 解密 "Checking..."
        NSString *statusText = DecryptBytes(byte_10013838F, 0x72C59874A2D55574LL, 16);
        UIColor *blueColor = [UIColor colorWithRed:0.376 green:0.647 blue:0.980 alpha:1.0];
        [self setStatusText:statusText color:blueColor];
        
        self.inFlight = YES;
        
        // 🚫 测试模式：绕过服务器验证，直接授权
        // 待稳定后取消注释以下代码以启用服务器验证
        // [[NetworkManager shared] authorizeWithKey:trimmedKey
        //                                completion:^(BOOL success, NSData *responseData, NSError *error) {
        //     dispatch_async(dispatch_get_main_queue(), ^{
        //         self.inFlight = NO;
        //         [self setLoading:NO];
        //         [self handleAuthResponse:responseData error:error];
        //     });
        // }];
        
        // 步骤1: 先检测防封网关连通性
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            BOOL gatewayOK = [self checkAntibanGateway];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                self.inFlight = NO;
                [self setLoading:NO];
                
                if (gatewayOK) {
                    [self bypassAuthorize];
                } else {
                    NSString *errText = @"✗ 未检测到防封网关\n请连接 202.189.9.12 后重试";
                    UIColor *redColor = [UIColor colorWithRed:0.973 green:0.443 blue:0.443 alpha:1.0];
                    [self setStatusText:errText color:redColor];
                }
            });
        });
        
    } else {
        NSString *errorText = DecryptBytes(byte_100138372, 0xF448C8D1A18070CLL, 29);
        UIColor *redColor = [UIColor colorWithRed:0.973 green:0.443 blue:0.443 alpha:1.0];
        [self setStatusText:errorText color:redColor];
    }
}

#pragma mark - 防封网关检测

- (BOOL)checkAntibanGateway {
    // 尝试 TCP 连接到 202.189.9.12:443
    // 能连上 → 用户挂了防封代理 → 允许使用
    // 连不上 → 用户裸连 → 拒绝使用（否则会被封）
    
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(ANTIBAN_PORT);
    
    struct hostent *host = gethostbyname([ANTIBAN_HOST UTF8String]);
    if (!host) {
        // DNS 解析失败，直接试 IP
        addr.sin_addr.s_addr = inet_addr([ANTIBAN_HOST UTF8String]);
    } else {
        memcpy(&addr.sin_addr, host->h_addr_list[0], host->h_length);
    }
    
    int sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock < 0) return NO;
    
    // 设置非阻塞 + 超时
    struct timeval tv;
    tv.tv_sec = ANTIBAN_TIMEOUT;
    tv.tv_usec = 0;
    setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
    
    int result = connect(sock, (struct sockaddr *)&addr, sizeof(addr));
    close(sock);
    
    if (result == 0) {
        NSLog(@"[Gateway] 防封网关 %@:%d 连通 ✓", ANTIBAN_HOST, ANTIBAN_PORT);
        return YES;
    } else {
        NSLog(@"[Gateway] 防封网关 %@:%d 不通 ✗ (errno=%d)", ANTIBAN_HOST, ANTIBAN_PORT, errno);
        return NO;
    }
}

// 测试模式：直接授权，跳过服务器
- (void)bypassAuthorize {
    NSString *successText = @"✓ 测试模式 — 授权成功 (离线)";
    UIColor *tealColor = [UIColor colorWithRed:0.204 green:0.827 blue:0.600 alpha:1.0];
    [self setStatusText:successText color:tealColor];
    
    [self saveAuthorizedKey:self.keyField.text];
    
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.6 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        if (weakSelf.onAuthorized) {
            weakSelf.onAuthorized();
        }
    });
}

// 服务器验证模式（暂未启用）
- (void)handleAuthResponse:(NSData *)responseData error:(NSError *)error {
    if (error) {
        // 验证失败
        NSString *format = DecryptBytes(byte_1001383B7, 0xE42A8B4664234E39LL, 29);
        NSString *failText = [NSString stringWithFormat:format, error.localizedDescription];
        UIColor *redColor = [UIColor colorWithRed:0.973 green:0.443 blue:0.443 alpha:1.0];
        [self setStatusText:failText color:redColor];
        
        // 10秒后重试
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC),
                       dispatch_get_main_queue(), ^{
            [weakSelf submitTapped];
        });
        return;
    }
    
    if (responseData.length > 0) {
        // 成功
        NSString *format = DecryptBytes(byte_10013839F, 0x6BE1CDD3F12BEC81LL, 7);
        NSString *successText = [NSString stringWithFormat:format, 
                                 [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding]];
        UIColor *tealColor = [UIColor colorWithRed:0.204 green:0.827 blue:0.600 alpha:1.0];
        [self setStatusText:successText color:tealColor];
        
        // 保存授权状态
        [self saveAuthorizedKey:self.keyField.text];
        
        // 0.6秒后触发授权完成
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.6 * NSEC_PER_SEC),
                       dispatch_get_main_queue(), ^{
            if (weakSelf.onAuthorized) {
                weakSelf.onAuthorized();
            }
        });
    } else {
        // 空响应
        NSString *errorText = DecryptBytes(byte_1001383D4, 0xFD3F1767EEDA12B8LL, 42);
        UIColor *redColor = [UIColor colorWithRed:0.973 green:0.443 blue:0.443 alpha:1.0];
        [self setStatusText:errorText color:redColor];
    }
}

#pragma mark - Clear Key

- (IBAction)clearSavedKey:(id)sender {
    if (self.inFlight) return;
    
    [self clearSavedKeyFromKeychain];
    self.keyField.text = @"";
    
    NSString *clearedText = DecryptBytes(byte_1001383FE, 0x12E2F663B533D52ELL, 25);
    UIColor *grayColor = [UIColor colorWithRed:0.588 green:0.659 blue:0.784 alpha:1.0];
    [self setStatusText:clearedText color:grayColor];
}

#pragma mark - Keychain Storage

- (NSString *)loadSavedKey {
    // 从钥匙串加载
    NSDictionary *query = @{
        (id)kSecClass: (id)kSecClassGenericPassword,
        (id)kSecAttrService: @"com.star.auth",
        (id)kSecAttrAccount: @"license_key",
        (id)kSecReturnData: @YES,
    };
    
    CFDataRef data = NULL;
    OSStatus status = SecItemCopyMatching((CFDictionaryRef)query, (CFTypeRef *)&data);
    
    if (status == errSecSuccess && data) {
        NSString *key = [[NSString alloc] initWithData:(__bridge NSData *)data 
                                              encoding:NSUTF8StringEncoding];
        CFRelease(data);
        return key;
    }
    return nil;
}

- (void)saveAuthorizedKey:(NSString *)key {
    NSData *keyData = [key dataUsingEncoding:NSUTF8StringEncoding];
    
    // 先删除旧的
    NSDictionary *deleteQuery = @{
        (id)kSecClass: (id)kSecClassGenericPassword,
        (id)kSecAttrService: @"com.star.auth",
        (id)kSecAttrAccount: @"license_key",
    };
    SecItemDelete((CFDictionaryRef)deleteQuery);
    
    // 保存新的
    NSDictionary *addQuery = @{
        (id)kSecClass: (id)kSecClassGenericPassword,
        (id)kSecAttrService: @"com.star.auth",
        (id)kSecAttrAccount: @"license_key",
        (id)kSecValueData: keyData,
        (id)kSecAttrAccessible: (id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
    };
    SecItemAdd((CFDictionaryRef)addQuery, NULL);
}

- (void)clearSavedKeyFromKeychain {
    NSDictionary *deleteQuery = @{
        (id)kSecClass: (id)kSecClassGenericPassword,
        (id)kSecAttrService: @"com.star.auth",
        (id)kSecAttrAccount: @"license_key",
    };
    SecItemDelete((CFDictionaryRef)deleteQuery);
}

#pragma mark - UI Helpers

- (void)setStatusText:(NSString *)text color:(UIColor *)color {
    self.statusLabel.text = text;
    self.statusLabel.textColor = color;
}

- (void)setLoading:(BOOL)loading {
    if (loading) {
        [self.spinner startAnimating];
        self.submitButton.enabled = NO;
        self.submitButton.alpha = 0.78;
    } else {
        [self.spinner stopAnimating];
        self.submitButton.enabled = YES;
        self.submitButton.alpha = 1.0;
    }
}

- (void)installBackground {
    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.frame = self.view.bounds;
    gradient.colors = @[
        (id)[UIColor colorWithRed:0.031 green:0.039 blue:0.078 alpha:1.0].CGColor,
        (id)[UIColor colorWithRed:0.063 green:0.071 blue:0.118 alpha:1.0].CGColor,
        (id)[UIColor colorWithRed:0.027 green:0.035 blue:0.075 alpha:1.0].CGColor,
    ];
    gradient.locations = @[@0.0, @0.5, @1.0];
    [self.view.layer addSublayer:gradient];
}

- (void)installHero {
    // Logo + Title (简化)
    UILabel *title = [[UILabel alloc] init];
    title.text = @"DeltaForce";
    title.font = [UIFont systemFontOfSize:32 weight:UIFontWeightBold];
    title.textColor = [UIColor whiteColor];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:title];
    
    UILabel *subtitle = [[UILabel alloc] init];
    subtitle.text = @"TrollKit v2.1";
    subtitle.font = [UIFont systemFontOfSize:14 weight:UIFontWeightLight];
    subtitle.textColor = [UIColor colorWithRed:0.376 green:0.647 blue:0.980 alpha:1.0];
    subtitle.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:subtitle];
    
    [NSLayoutConstraint activateConstraints:@[
        [title.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [title.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:120],
        [subtitle.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:8],
    ]];
}

- (void)installCard {
    // 输入框 + 按钮
    UIView *card = [[UIView alloc] init];
    card.backgroundColor = [UIColor colorWithRed:0.078 green:0.094 blue:0.157 alpha:0.8];
    card.layer.cornerRadius = 20;
    card.layer.borderWidth = 1;
    card.layer.borderColor = [UIColor colorWithRed:0.157 green:0.188 blue:0.282 alpha:1.0].CGColor;
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:card];
    
    self.keyField = [[UITextField alloc] init];
    self.keyField.placeholder = @"Enter 32-char license key";
    self.keyField.textAlignment = NSTextAlignmentCenter;
    self.keyField.textColor = [UIColor whiteColor];
    self.keyField.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightMedium];
    self.keyField.backgroundColor = [UIColor colorWithRed:0.043 green:0.055 blue:0.118 alpha:1.0];
    self.keyField.layer.cornerRadius = 12;
    self.keyField.layer.borderWidth = 1;
    self.keyField.layer.borderColor = [UIColor colorWithRed:0.157 green:0.188 blue:0.282 alpha:1.0].CGColor;
    self.keyField.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:self.keyField];
    
    self.submitButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.submitButton setTitle:@"Authorize" forState:UIControlStateNormal];
    self.submitButton.backgroundColor = [UIColor colorWithRed:0.376 green:0.647 blue:0.980 alpha:1.0];
    self.submitButton.tintColor = [UIColor whiteColor];
    self.submitButton.layer.cornerRadius = 12;
    [self.submitButton addTarget:self action:@selector(submitTapped) forControlEvents:UIControlEventTouchUpInside];
    self.submitButton.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:self.submitButton];
    
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner.color = [UIColor whiteColor];
    self.spinner.hidesWhenStopped = YES;
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:self.spinner];
    
    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    self.statusLabel.textColor = [UIColor colorWithRed:0.588 green:0.659 blue:0.784 alpha:1.0];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:self.statusLabel];
    
    [NSLayoutConstraint activateConstraints:@[
        [card.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [card.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [card.widthAnchor constraintEqualToConstant:320],
        [card.heightAnchor constraintEqualToConstant:220],
        
        [self.keyField.topAnchor constraintEqualToAnchor:card.topAnchor constant:20],
        [self.keyField.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:20],
        [self.keyField.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-20],
        [self.keyField.heightAnchor constraintEqualToConstant:44],
        
        [self.submitButton.topAnchor constraintEqualToAnchor:self.keyField.bottomAnchor constant:12],
        [self.submitButton.centerXAnchor constraintEqualToAnchor:card.centerXAnchor],
        [self.submitButton.widthAnchor constraintEqualToConstant:200],
        [self.submitButton.heightAnchor constraintEqualToConstant:44],
        
        [self.spinner.centerYAnchor constraintEqualToAnchor:self.submitButton.centerYAnchor],
        [self.spinner.trailingAnchor constraintEqualToAnchor:self.submitButton.leadingAnchor constant:-8],
        
        [self.statusLabel.topAnchor constraintEqualToAnchor:self.submitButton.bottomAnchor constant:12],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:12],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-12],
    ]];
}

- (void)installClearKeyButton {
    UIButton *clearBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [clearBtn setTitle:@"Clear Saved Key" forState:UIControlStateNormal];
    clearBtn.tintColor = [UIColor colorWithRed:0.588 green:0.659 blue:0.784 alpha:1.0];
    clearBtn.titleLabel.font = [UIFont systemFontOfSize:12];
    [clearBtn addTarget:self action:@selector(clearSavedKey:) forControlEvents:UIControlEventTouchUpInside];
    clearBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:clearBtn];
    
    [NSLayoutConstraint activateConstraints:@[
        [clearBtn.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [clearBtn.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:60],
    ]];
}

@end
