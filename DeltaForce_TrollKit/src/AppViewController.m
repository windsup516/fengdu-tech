// AppViewController - 主菜单界面 (武器选择 + 状态 + 激活按钮)
// 基于反编译 AppViewController / startServiceBootstrap / toggleHUD

#import "AppViewController.h"
#import "HUDController.h"
#import "WeaponConfig.h"
#import "DeviceInfo.h"
#import "XPFKernelInterface.h"
#import "GameHooks.h"
#import "CryptoUtils.h"
#import "HIDEventManager.h"

// 从反编译恢复的加密数据
static const uint8_t serv_text[] = {0x4a,0x4c,0x4e,0x43,0x4f,0x0e,0x45,0x0d,0x0e,0x46,0x4f,0x07,0x01,0x0b,0x06,0x04,0x44,0x02,0x0a,0x4f,0x09,0x0c,0x02,0x46,0x07,0x17,0x4a,0x4c,0x2e,0x4c,0x08,0x47};

@interface AppViewController ()
@property (nonatomic) BOOL listening;
@property (nonatomic) BOOL didInstallLayout;
- (void)installHero;
@end

@implementation AppViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.selectedFlavor = @"M4A1";
    
    [self installBackground];
    [self installHero];
    [self installFlavorSelector];
    [self installInfoCard];
    [self installStatusCard];
    [self installPrimaryButton];
    [self installFooter];
    
    self.listening = YES;
    [self refreshDeviceInfo];
}

#pragma mark - 武器选择

- (void)installFlavorSelector {
    self.flavorTitleLabel = [[UILabel alloc] init];
    self.flavorTitleLabel.text = @"WEAPON PROFILE";
    self.flavorTitleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    self.flavorTitleLabel.textColor = [UIColor colorWithRed:0.588 green:0.659 blue:0.784 alpha:1.0];
    self.flavorTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.flavorTitleLabel];
    
    // 武器预设列表
    NSArray *weapons = @[@"AKM", @"QBZ95-1", @"QBZ-17", @"AKS-74U", @"ASH-12", 
                          @"M16A4", @"M4A1", @"K416", @"AUG", @"M7", @"SC17", @"97M"];
    
    NSMutableArray *buttons = [NSMutableArray array];
    CGFloat btnWidth = 72;
    CGFloat btnHeight = 34;
    CGFloat spacing = 8;
    CGFloat totalWidth = weapons.count * btnWidth + (weapons.count - 1) * spacing;
    
    UIScrollView *scrollView = [[UIScrollView alloc] init];
    scrollView.showsHorizontalScrollIndicator = NO;
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:scrollView];
    
    UIView *container = [[UIView alloc] init];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    [scrollView addSubview:container];
    
    [weapons enumerateObjectsUsingBlock:^(NSString *name, NSUInteger idx, BOOL *stop) {
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
        [btn setTitle:name forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
        btn.tintColor = [UIColor whiteColor];
        btn.backgroundColor = [UIColor colorWithRed:0.118 green:0.149 blue:0.235 alpha:1.0];
        btn.layer.cornerRadius = 8;
        btn.layer.borderWidth = 1;
        btn.layer.borderColor = [UIColor colorWithRed:0.196 green:0.235 blue:0.329 alpha:1.0].CGColor;
        btn.tag = idx;
        [btn addTarget:self action:@selector(flavorButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        btn.translatesAutoresizingMaskIntoConstraints = NO;
        [container addSubview:btn];
        [buttons addObject:btn];
    }];
    self.flavorButtons = buttons;
    
    [NSLayoutConstraint activateConstraints:@[
        [scrollView.topAnchor constraintEqualToAnchor:self.flavorTitleLabel.bottomAnchor constant:8],
        [scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [scrollView.heightAnchor constraintEqualToConstant:44],
        
        [container.topAnchor constraintEqualToAnchor:scrollView.topAnchor],
        [container.bottomAnchor constraintEqualToAnchor:scrollView.bottomAnchor],
        [container.leadingAnchor constraintEqualToAnchor:scrollView.leadingAnchor],
        [container.trailingAnchor constraintEqualToAnchor:scrollView.trailingAnchor],
        [container.heightAnchor constraintEqualToAnchor:scrollView.heightAnchor],
        [container.widthAnchor constraintEqualToConstant:totalWidth],
    ]];
    
    // 布局按钮
    [buttons enumerateObjectsUsingBlock:^(UIButton *btn, NSUInteger idx, BOOL *stop) {
        CGFloat x = idx * (btnWidth + spacing);
        [NSLayoutConstraint activateConstraints:@[
            [btn.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:x],
            [btn.centerYAnchor constraintEqualToAnchor:container.centerYAnchor],
            [btn.widthAnchor constraintEqualToConstant:btnWidth],
            [btn.heightAnchor constraintEqualToConstant:btnHeight],
        ]];
    }];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.flavorTitleLabel.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:240],
        [self.flavorTitleLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
    ]];
}

- (void)flavorButtonTapped:(UIButton *)sender {
    NSArray *weapons = @[@"AKM", @"QBZ95-1", @"QBZ-17", @"AKS-74U", @"ASH-12", 
                          @"M16A4", @"M4A1", @"K416", @"AUG", @"M7", @"SC17", @"97M"];
    self.selectedFlavor = weapons[sender.tag % weapons.count];
    
    for (UIButton *btn in self.flavorButtons) {
        btn.backgroundColor = [UIColor colorWithRed:0.118 green:0.149 blue:0.235 alpha:1.0];
        btn.layer.borderColor = [UIColor colorWithRed:0.196 green:0.235 blue:0.329 alpha:1.0].CGColor;
    }
    
    sender.backgroundColor = [UIColor colorWithRed:0.235 green:0.341 blue:0.557 alpha:0.6];
    sender.layer.borderColor = [UIColor colorWithRed:0.376 green:0.647 blue:0.980 alpha:1.0].CGColor;
    
    // 应用武器配置
    [[WeaponConfigManager shared] applyConfigForWeapon:self.selectedFlavor];
}

#pragma mark - Info Card

- (void)installInfoCard {
    self.infoCard = [[UIView alloc] init];
    self.infoCard.backgroundColor = [UIColor colorWithRed:0.078 green:0.094 blue:0.157 alpha:0.6];
    self.infoCard.layer.cornerRadius = 16;
    self.infoCard.layer.borderWidth = 1;
    self.infoCard.layer.borderColor = [UIColor colorWithRed:0.157 green:0.188 blue:0.282 alpha:1.0].CGColor;
    self.infoCard.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.infoCard];
    
    self.infoCardHeader = [[UILabel alloc] init];
    self.infoCardHeader.text = @"DEVICE INFO";
    self.infoCardHeader.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    self.infoCardHeader.textColor = [UIColor colorWithRed:0.588 green:0.659 blue:0.784 alpha:1.0];
    self.infoCardHeader.translatesAutoresizingMaskIntoConstraints = NO;
    [self.infoCard addSubview:self.infoCardHeader];
    
    self.infoCardCounter = [[UILabel alloc] init];
    self.infoCardCounter.text = @"--";
    self.infoCardCounter.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    self.infoCardCounter.textColor = [UIColor colorWithRed:0.376 green:0.647 blue:0.980 alpha:1.0];
    self.infoCardCounter.translatesAutoresizingMaskIntoConstraints = NO;
    [self.infoCard addSubview:self.infoCardCounter];
    
    // Info rows
    NSArray *labels = @[@"FPS", @"Ping", @"Players", @"Weapon", @"State"];
    NSMutableArray *rows = [NSMutableArray array];
    
    [labels enumerateObjectsUsingBlock:^(NSString *label, NSUInteger idx, BOOL *stop) {
        UILabel *lbl = [[UILabel alloc] init];
        lbl.text = [NSString stringWithFormat:@"%@: --", label];
        lbl.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
        lbl.textColor = [UIColor colorWithRed:0.588 green:0.659 blue:0.784 alpha:1.0];
        lbl.translatesAutoresizingMaskIntoConstraints = NO;
        [self.infoCard addSubview:lbl];
        [rows addObject:lbl];
    }];
    self.infoRows = rows;
    
    [NSLayoutConstraint activateConstraints:@[
        [self.infoCard.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [self.infoCard.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:80],
        [self.infoCard.widthAnchor constraintEqualToConstant:160],
        
        [self.infoCardHeader.topAnchor constraintEqualToAnchor:self.infoCard.topAnchor constant:12],
        [self.infoCardHeader.leadingAnchor constraintEqualToAnchor:self.infoCard.leadingAnchor constant:12],
        [self.infoCardCounter.trailingAnchor constraintEqualToAnchor:self.infoCard.trailingAnchor constant:-12],
        [self.infoCardCounter.centerYAnchor constraintEqualToAnchor:self.infoCardHeader.centerYAnchor],
    ]];
    
    [rows enumerateObjectsUsingBlock:^(UILabel *lbl, NSUInteger idx, BOOL *stop) {
        [NSLayoutConstraint activateConstraints:@[
            [lbl.leadingAnchor constraintEqualToAnchor:self.infoCard.leadingAnchor constant:12],
            [lbl.trailingAnchor constraintEqualToAnchor:self.infoCard.trailingAnchor constant:-12],
            [lbl.topAnchor constraintEqualToAnchor:self.infoCardHeader.bottomAnchor constant:12 + idx*18],
        ]];
    }];
}

#pragma mark - Status Card

- (void)installStatusCard {
    self.statusCard = [[UIView alloc] init];
    self.statusCard.backgroundColor = [UIColor colorWithRed:0.078 green:0.094 blue:0.157 alpha:0.6];
    self.statusCard.layer.cornerRadius = 16;
    self.statusCard.layer.borderWidth = 1;
    self.statusCard.layer.borderColor = [UIColor colorWithRed:0.157 green:0.188 blue:0.282 alpha:1.0].CGColor;
    self.statusCard.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.statusCard];
    
    self.statusHeader = [[UILabel alloc] init];
    self.statusHeader.text = @"Status";
    self.statusHeader.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    self.statusHeader.textColor = [UIColor colorWithRed:0.588 green:0.659 blue:0.784 alpha:1.0];
    self.statusHeader.translatesAutoresizingMaskIntoConstraints = NO;
    [self.statusCard addSubview:self.statusHeader];
    
    self.statusDetail = [[UILabel alloc] init];
    self.statusDetail.text = @"Ready";
    self.statusDetail.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    self.statusDetail.textColor = [UIColor colorWithRed:0.204 green:0.827 blue:0.600 alpha:1.0];
    self.statusDetail.translatesAutoresizingMaskIntoConstraints = NO;
    [self.statusCard addSubview:self.statusDetail];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.statusCard.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.statusCard.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-100],
        [self.statusCard.widthAnchor constraintEqualToConstant:160],
        [self.statusCard.heightAnchor constraintEqualToConstant:60],
        
        [self.statusHeader.topAnchor constraintEqualToAnchor:self.statusCard.topAnchor constant:10],
        [self.statusHeader.leadingAnchor constraintEqualToAnchor:self.statusCard.leadingAnchor constant:12],
        [self.statusDetail.topAnchor constraintEqualToAnchor:self.statusHeader.bottomAnchor constant:4],
        [self.statusDetail.leadingAnchor constraintEqualToAnchor:self.statusCard.leadingAnchor constant:12],
    ]];
}

#pragma mark - Primary Button

- (void)installPrimaryButton {
    self.primaryButton = [UIButton buttonWithType:UIButtonTypeCustom];
    
    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.colors = @[
        (id)[UIColor colorWithRed:0.376 green:0.647 blue:0.980 alpha:1.0].CGColor,
        (id)[UIColor colorWithRed:0.235 green:0.439 blue:0.820 alpha:1.0].CGColor,
    ];
    gradient.frame = CGRectMake(0, 0, 200, 50);
    gradient.cornerRadius = 25;
    [self.primaryButton.layer insertSublayer:gradient atIndex:0];
    
    [self.primaryButton setTitle:@"ACTIVATE CHEAT" forState:UIControlStateNormal];
    self.primaryButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightBold];
    [self.primaryButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.primaryButton.layer.cornerRadius = 25;
    self.primaryButton.clipsToBounds = YES;
    
    [self.primaryButton addTarget:self action:@selector(primaryButtonDown) forControlEvents:UIControlEventTouchDown];
    [self.primaryButton addTarget:self action:@selector(primaryButtonUp) forControlEvents:UIControlEventTouchUpInside];
    [self.primaryButton addTarget:self action:@selector(primaryButtonTapped) forControlEvents:UIControlEventTouchUpOutside];
    
    self.primaryButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.primaryButton];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.primaryButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.primaryButton.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-160],
        [self.primaryButton.widthAnchor constraintEqualToConstant:200],
        [self.primaryButton.heightAnchor constraintEqualToConstant:50],
    ]];
}

- (void)primaryButtonDown {
    // 通过 IOHIDEventSystemClient 模拟鼠标按下
    [[HIDEventManager shared] sendMouseButtonDown];
}

- (void)primaryButtonUp {
    [[HIDEventManager shared] sendMouseButtonUp];
}

- (void)primaryButtonTapped {
    [self toggleHUD];
}

- (void)toggleHUD {
    HUDController *hud = [HUDController shared];
    if (hud.showing) {
        [hud hide];
    } else {
        [hud show];
    }
}

#pragma mark - Refresh Device Info

- (void)refreshDeviceInfo {
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        while (weakSelf.listening) {
            DeviceInfoData infoData = [DeviceInfo shared].currentInfo;
            NSString *weaponName = [NSString stringWithUTF8String:infoData.currentWeapon];
            NSString *stateText = infoData.cheatActive ? @"ACTIVE" : @"IDLE";

            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(self) strongSelf = weakSelf;
                if (!strongSelf) return;
                if (strongSelf.infoRows.count >= 5) {
                    ((UILabel *)strongSelf.infoRows[0]).text = [NSString stringWithFormat:@"FPS: %.0f", infoData.fps];
                    ((UILabel *)strongSelf.infoRows[1]).text = [NSString stringWithFormat:@"Ping: %.0fms", infoData.ping];
                    ((UILabel *)strongSelf.infoRows[2]).text = [NSString stringWithFormat:@"Players: %d", infoData.playerCount];
                    ((UILabel *)strongSelf.infoRows[3]).text = [NSString stringWithFormat:@"Weapon: %@", weaponName];
                    ((UILabel *)strongSelf.infoRows[4]).text = [NSString stringWithFormat:@"State: %@", stateText];
                    strongSelf.infoCardCounter.text = [NSString stringWithFormat:@"%d", infoData.playerCount];
                }
            });
            
            [NSThread sleepForTimeInterval:0.5];
        }
    });
}

#pragma mark - Footer

- (void)installFooter {
    UILabel *footer = [[UILabel alloc] init];
    footer.text = @"DeltaForce TrollKit v2.1 | Kernel Level";
    footer.font = [UIFont systemFontOfSize:10];
    footer.textColor = [UIColor colorWithRed:0.4 green:0.4 blue:0.5 alpha:0.5];
    footer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:footer];
    
    [NSLayoutConstraint activateConstraints:@[
        [footer.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [footer.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-30],
    ]];
}

#pragma mark - Background

- (void)installBackground {
    // 同 LoginViewController 的暗黑渐变
    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.frame = self.view.bounds;
    gradient.colors = @[
        (id)[UIColor colorWithRed:0.031 green:0.039 blue:0.078 alpha:1.0].CGColor,
        (id)[UIColor colorWithRed:0.063 green:0.071 blue:0.118 alpha:1.0].CGColor,
    ];
    [self.view.layer insertSublayer:gradient atIndex:0];
    
    // 装饰性光晕
    NSMutableArray *blobs = [NSMutableArray array];
    for (int i = 0; i < 3; i++) {
        UIView *blob = [[UIView alloc] init];
        CGFloat size = 120 + arc4random_uniform(80);
        blob.frame = CGRectMake(arc4random_uniform(200) - 50, 
                                 arc4random_uniform(400) + 100, 
                                 size, size);
        blob.backgroundColor = [UIColor colorWithRed:0.2 green:0.3 blue:0.6 alpha:0.15];
        blob.layer.cornerRadius = size / 2;
        [self.view insertSubview:blob atIndex:0];
        [blobs addObject:blob];
    }
    self.glowBlobs = blobs;
}

#pragma mark - Set Status

- (void)setStatus:(NSString *)status detail:(NSString *)detail kind:(NSInteger)kind {
    self.statusHeader.text = status;
    self.statusDetail.text = detail;
    
    UIColor *color;
    switch (kind) {
        case 0: color = [UIColor colorWithRed:0.588 green:0.659 blue:0.784 alpha:1.0]; break; // 灰色
        case 1: color = [UIColor colorWithRed:0.376 green:0.647 blue:0.980 alpha:1.0]; break; // 蓝色
        case 2: color = [UIColor colorWithRed:0.204 green:0.827 blue:0.600 alpha:1.0]; break; // 绿色
        case 3: color = [UIColor colorWithRed:0.973 green:0.443 blue:0.443 alpha:1.0]; break; // 红色
        default: color = [UIColor whiteColor]; break;
    }
    self.statusDetail.textColor = color;
}

- (void)setServiceLoading:(BOOL)loading {
    _serviceLoading = loading;
    self.primaryButton.enabled = !loading;
    self.primaryButton.alpha = loading ? 0.78 : 1.0;
    if (loading) [self.spinner startAnimating];
    else [self.spinner stopAnimating];
}

- (void)installHero {
    // AppViewController 顶部 UI (暂无内容, 预留)
}

@end
