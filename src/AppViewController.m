// AppViewController - 主菜单界面 (武器选择 + 状态 + 激活按钮)
// 基于反编译 AppViewController / startServiceBootstrap / toggleHUD
// v2.1: 完整匹配原版二进制 — hudVisible 状态机 + clock_gettime 安全检查

#import "AppViewController.h"
#import "HUDController.h"
#import "WeaponConfig.h"
#import "DeviceInfo.h"
#import "XPFKernelInterface.h"
#import "GameHooks.h"
#import "CryptoUtils.h"
#import "HIDEventManager.h"
#import <time.h>

@interface AppViewController ()
- (void)installHero;
@end

@implementation AppViewController

- (void)viewDidLoad {
    NSLog(@"[AppVC] viewDidLoad: START");
    @try {
        [super viewDidLoad];
        NSLog(@"[AppVC] super viewDidLoad OK");
    } @catch (NSException *e) {
        NSLog(@"[AppVC] super viewDidLoad CRASH: %@", e);
    }

    self.selectedFlavor = @"M4A1";
    self.hudVisible = NO;
    self.serviceReady = NO;
    self.serviceLoading = NO;
    self.didRunEntryAnimation = NO;

    @try { [self installBackground]; NSLog(@"[AppVC] installBackground OK"); }
    @catch (NSException *e) { NSLog(@"[AppVC] installBackground CRASH: %@", e); }

    @try { [self installHero]; }
    @catch (NSException *e) { NSLog(@"[AppVC] installHero CRASH: %@", e); }

    @try { [self installFlavorSelector]; NSLog(@"[AppVC] installFlavorSelector OK"); }
    @catch (NSException *e) { NSLog(@"[AppVC] installFlavorSelector CRASH: %@", e); }

    @try { [self installInfoCard]; NSLog(@"[AppVC] installInfoCard OK"); }
    @catch (NSException *e) { NSLog(@"[AppVC] installInfoCard CRASH: %@", e); }

    @try { [self installStatusCard]; NSLog(@"[AppVC] installStatusCard OK"); }
    @catch (NSException *e) { NSLog(@"[AppVC] installStatusCard CRASH: %@", e); }

    @try { [self installPrimaryButton]; NSLog(@"[AppVC] installPrimaryButton OK"); }
    @catch (NSException *e) { NSLog(@"[AppVC] installPrimaryButton CRASH: %@", e); }

    @try { [self installFooter]; NSLog(@"[AppVC] installFooter OK"); }
    @catch (NSException *e) { NSLog(@"[AppVC] installFooter CRASH: %@", e); }

    self.listening = YES;

    @try {
        [self refreshDeviceInfo];
        NSLog(@"[AppVC] refreshDeviceInfo OK");
    } @catch (NSException *e) {
        NSLog(@"[AppVC] refreshDeviceInfo CRASH: %@", e);
    }

    NSLog(@"[AppVC] viewDidLoad: DONE");
}

- (void)viewWillAppear:(BOOL)animated {
    @try {
        [super viewWillAppear:animated];
        if (!self.didRunEntryAnimation) {
            [self prepareForEntryAnimation];
        }
    } @catch (NSException *e) {
        NSLog(@"[AppVC] viewWillAppear CRASH: %@", e);
    }
}

- (void)viewDidAppear:(BOOL)animated {
    @try {
        [super viewDidAppear:animated];
        if (!self.didRunEntryAnimation) {
            [self runEntryAnimationIfNeeded];
        }
    } @catch (NSException *e) {
        NSLog(@"[AppVC] viewDidAppear CRASH: %@", e);
    }
}

#pragma mark - Entry Animation

- (void)prepareForEntryAnimation {
    // 初始状态: 按钮缩小 + 信息卡片偏移
    self.primaryButton.transform = CGAffineTransformMakeScale(0.85, 0.85);
    self.primaryButton.alpha = 0.0;
}

- (void)runEntryAnimationIfNeeded {
    if (self.didRunEntryAnimation) return;
    self.didRunEntryAnimation = YES;

    [UIView animateWithDuration:0.45 delay:0.15 options:UIViewAnimationOptionCurveEaseOut animations:^{
        self.primaryButton.transform = CGAffineTransformIdentity;
        self.primaryButton.alpha = 1.0;
    } completion:nil];
}

#pragma mark - 武器选择

- (void)installFlavorSelector {
    self.flavorTitleLabel = [[UILabel alloc] init];
    self.flavorTitleLabel.text = @"WEAPON PROFILE";
    self.flavorTitleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    self.flavorTitleLabel.textColor = [UIColor colorWithRed:0.588 green:0.659 blue:0.784 alpha:1.0];
    self.flavorTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.flavorTitleLabel];

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

    // StatusPill — 状态指示器
    self.statusPill = [[UIView alloc] init];
    self.statusPill.backgroundColor = [UIColor colorWithRed:0.204 green:0.827 blue:0.600 alpha:1.0];
    self.statusPill.layer.cornerRadius = 4;
    self.statusPill.translatesAutoresizingMaskIntoConstraints = NO;
    [self.statusCard addSubview:self.statusPill];

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

    // 进度条 (对应反编译 progressTrack/progressFill)
    self.progressTrack = [[UIView alloc] init];
    self.progressTrack.backgroundColor = [UIColor colorWithRed:0.118 green:0.149 blue:0.235 alpha:1.0];
    self.progressTrack.layer.cornerRadius = 2;
    self.progressTrack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.statusCard addSubview:self.progressTrack];

    self.progressFill = [[UIView alloc] init];
    self.progressFill.backgroundColor = [UIColor colorWithRed:0.376 green:0.647 blue:0.980 alpha:1.0];
    self.progressFill.layer.cornerRadius = 2;
    self.progressFill.translatesAutoresizingMaskIntoConstraints = NO;
    [self.progressTrack addSubview:self.progressFill];

    [NSLayoutConstraint activateConstraints:@[
        [self.statusCard.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.statusCard.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-100],
        [self.statusCard.widthAnchor constraintEqualToConstant:180],
        [self.statusCard.heightAnchor constraintEqualToConstant:80],

        [self.statusPill.topAnchor constraintEqualToAnchor:self.statusCard.topAnchor constant:14],
        [self.statusPill.leadingAnchor constraintEqualToAnchor:self.statusCard.leadingAnchor constant:12],
        [self.statusPill.widthAnchor constraintEqualToConstant:8],
        [self.statusPill.heightAnchor constraintEqualToConstant:8],

        [self.statusHeader.topAnchor constraintEqualToAnchor:self.statusCard.topAnchor constant:10],
        [self.statusHeader.leadingAnchor constraintEqualToAnchor:self.statusPill.trailingAnchor constant:8],
        [self.statusDetail.topAnchor constraintEqualToAnchor:self.statusHeader.bottomAnchor constant:4],
        [self.statusDetail.leadingAnchor constraintEqualToAnchor:self.statusPill.trailingAnchor constant:8],

        [self.progressTrack.topAnchor constraintEqualToAnchor:self.statusDetail.bottomAnchor constant:10],
        [self.progressTrack.leadingAnchor constraintEqualToAnchor:self.statusCard.leadingAnchor constant:12],
        [self.progressTrack.trailingAnchor constraintEqualToAnchor:self.statusCard.trailingAnchor constant:-12],
        [self.progressTrack.heightAnchor constraintEqualToConstant:4],

        [self.progressFill.topAnchor constraintEqualToAnchor:self.progressTrack.topAnchor],
        [self.progressFill.leadingAnchor constraintEqualToAnchor:self.progressTrack.leadingAnchor],
        [self.progressFill.heightAnchor constraintEqualToConstant:4],
    ]];
    self.progressFillWidth = [self.progressFill.widthAnchor constraintEqualToConstant:0];
    self.progressFillWidth.active = YES;
}

#pragma mark - Primary Button

- (void)installPrimaryButton {
    self.primaryButton = [UIButton buttonWithType:UIButtonTypeCustom];

    // 渐变背景 — 浮球样式
    self.primaryButtonGradient = [CAGradientLayer layer];
    self.primaryButtonGradient.colors = @[
        (id)[UIColor colorWithRed:0.376 green:0.647 blue:0.980 alpha:1.0].CGColor,
        (id)[UIColor colorWithRed:0.235 green:0.439 blue:0.820 alpha:1.0].CGColor,
    ];
    CGFloat ballSize = 80;
    self.primaryButtonGradient.frame = CGRectMake(0, 0, ballSize, ballSize);
    self.primaryButtonGradient.cornerRadius = ballSize / 2;
    [self.primaryButton.layer insertSublayer:self.primaryButtonGradient atIndex:0];

    // 外圈光晕
    self.primaryButton.layer.shadowColor = [UIColor colorWithRed:0.376 green:0.647 blue:0.980 alpha:0.6].CGColor;
    self.primaryButton.layer.shadowOffset = CGSizeMake(0, 0);
    self.primaryButton.layer.shadowRadius = 12;
    self.primaryButton.layer.shadowOpacity = 1.0;

    [self.primaryButton setTitle:@"风度" forState:UIControlStateNormal];
    self.primaryButton.titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
    [self.primaryButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.primaryButton.layer.cornerRadius = ballSize / 2;
    self.primaryButton.clipsToBounds = NO;
    self.primaryButton.layer.masksToBounds = YES;

    [self.primaryButton addTarget:self action:@selector(primaryButtonDown) forControlEvents:UIControlEventTouchDown];
    [self.primaryButton addTarget:self action:@selector(primaryButtonUp) forControlEvents:UIControlEventTouchUpInside];
    [self.primaryButton addTarget:self action:@selector(primaryButtonTapped) forControlEvents:UIControlEventTouchUpOutside];

    self.primaryButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.primaryButton];

    [NSLayoutConstraint activateConstraints:@[
        [self.primaryButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.primaryButton.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-80],
        [self.primaryButton.widthAnchor constraintEqualToConstant:ballSize],
        [self.primaryButton.heightAnchor constraintEqualToConstant:ballSize],
    ]];
}

- (void)primaryButtonDown {
    [[HIDEventManager shared] sendMouseButtonDown];
}

- (void)primaryButtonUp {
    [[HIDEventManager shared] sendMouseButtonUp];
}

- (void)primaryButtonTapped {
    [self toggleHUD];
}

#pragma mark - toggleHUD (原版 0x1000f9a38 — 完整状态机)

- (void)toggleHUD {
    // 安全检查: clock_gettime(CLOCK_MONOTONIC) 获取运行时间
    // 原版 sub_10000B1C8: 返回自系统启动以来的毫秒数
    // qword_10139E208 ^ qword_10139E200 — 混淆的计时器检查
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    uint64_t nowMs = ts.tv_nsec / 1000000 + 1000 * ts.tv_sec;

    // 简单的防快速点击: 500ms 冷却
    static uint64_t lastToggleMs = 0;
    if (nowMs - lastToggleMs < 500) return;
    lastToggleMs = nowMs;

    HUDController *hud = [HUDController shared];

    if (hud.showing) {
        // 当前显示中 → 隐藏
        [hud hide];
        self.hudVisible = NO;
    } else {
        // 当前隐藏 → 显示
        self.hudVisible = YES;
        [self startServiceBootstrap];
    }

    // 更新按钮文字和颜色
    [self updatePrimaryButtonAppearance];
}

- (void)updatePrimaryButtonAppearance {
    if (self.hudVisible) {
        [self.primaryButton setTitle:@"隐藏" forState:UIControlStateNormal];
        // 绿色渐变
        self.primaryButtonGradient.colors = @[
            (id)[UIColor colorWithRed:0.133 green:0.773 blue:0.369 alpha:1.0].CGColor,
            (id)[UIColor colorWithRed:0.063 green:0.725 blue:0.506 alpha:1.0].CGColor,
        ];
        [self setStatus:@"已激活" detail:@"风度悬浮窗运行中" kind:2];
    } else {
        [self.primaryButton setTitle:@"风度" forState:UIControlStateNormal];
        // 蓝色渐变
        self.primaryButtonGradient.colors = @[
            (id)[UIColor colorWithRed:0.376 green:0.647 blue:0.980 alpha:1.0].CGColor,
            (id)[UIColor colorWithRed:0.235 green:0.439 blue:0.820 alpha:1.0].CGColor,
        ];
        [self setStatus:@"就绪" detail:@"点击风度按钮激活" kind:1];
    }
}

#pragma mark - startServiceBootstrap (原版 0x1000fa054)

- (void)startServiceBootstrap {
    if (self.serviceLoading) return;

    [self setServiceLoading:YES];
    self.primaryButton.enabled = NO;
    self.primaryButton.alpha = 0.78;
    [self.spinner startAnimating];

    [self setStatus:@"启动中" detail:@"正在初始化辅助服务..." kind:1];

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        HUDController *hud = [HUDController shared];

        // 获取当前 window scene (延迟到激活时获取，避免登录流程中崩溃)
        __block id scene = nil;
        dispatch_sync(dispatch_get_main_queue(), ^{
            scene = [UIApplication sharedApplication].delegate.window.windowScene;
            if (!scene) {
                scene = [UIApplication sharedApplication].connectedScenes.anyObject;
            }
        });

        @try {
            [hud createWindowsOnScene:scene];
        } @catch (NSException *e) {
            NSLog(@"[App] createWindowsOnScene exception: %@", e);
        }

        if (hud.windowsCreated) {
            [hud show];
        }

        int attachResult = hooks_attach_to_game();
        if (attachResult == 0) {
            hooks_scan_offsets();
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;

            [strongSelf setServiceLoading:NO];
            strongSelf.primaryButton.enabled = YES;
            strongSelf.primaryButton.alpha = 1.0;
            strongSelf.serviceReady = YES;

            if (attachResult == 0) {
                [strongSelf setStatus:@"已连接" detail:@"游戏内存已附加" kind:2];
                strongSelf.progressFillWidth.constant = strongSelf.progressTrack.bounds.size.width;
            } else {
                [strongSelf setStatus:@"仅覆盖层" detail:@"游戏附加失败，仅ESP可用" kind:3];
                strongSelf.progressFillWidth.constant = strongSelf.progressTrack.bounds.size.width * 0.5;
            }
            [UIView animateWithDuration:0.3 animations:^{
                [strongSelf.progressTrack layoutIfNeeded];
            }];
        });
    });
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
    self.footerLabel = [[UILabel alloc] init];
    self.footerLabel.text = @"风度全功能";
    self.footerLabel.font = [UIFont systemFontOfSize:10];
    self.footerLabel.textColor = [UIColor colorWithRed:0.4 green:0.4 blue:0.5 alpha:0.5];
    self.footerLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.footerLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.footerLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.footerLabel.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-30],
    ]];
}

#pragma mark - Background

- (void)installBackground {
    // 暗黑渐变
    self.backgroundGradient = [CAGradientLayer layer];
    self.backgroundGradient.frame = self.view.bounds;
    self.backgroundGradient.colors = @[
        (id)[UIColor colorWithRed:0.031 green:0.039 blue:0.078 alpha:1.0].CGColor,
        (id)[UIColor colorWithRed:0.063 green:0.071 blue:0.118 alpha:1.0].CGColor,
    ];
    [self.view.layer insertSublayer:self.backgroundGradient atIndex:0];

    // 装饰性光晕 (addGlowBlobAtAnchor)
    NSMutableArray *blobs = [NSMutableArray array];
    for (int i = 0; i < 3; i++) {
        UIView *blob = [self addGlowBlobAtAnchor:CGPointMake(arc4random_uniform(300) / 300.0,
                                                               arc4random_uniform(400) / 400.0)
                                            tint:[UIColor colorWithRed:0.2 green:0.3 blue:0.6 alpha:0.15]
                                            size:120 + arc4random_uniform(80)];
        [blobs addObject:blob];
    }
    self.glowBlobs = blobs;
}

- (UIView *)addGlowBlobAtAnchor:(CGPoint)anchor tint:(UIColor *)tint size:(CGFloat)size {
    UIView *blob = [[UIView alloc] init];
    blob.frame = CGRectMake(anchor.x * self.view.bounds.size.width - size/2,
                             anchor.y * self.view.bounds.size.height - size/2,
                             size, size);
    blob.backgroundColor = tint;
    blob.layer.cornerRadius = size / 2;
    [self.view insertSubview:blob atIndex:0];
    return blob;
}

#pragma mark - Set Status

- (void)setStatus:(NSString *)status detail:(NSString *)detail kind:(NSInteger)kind {
    self.statusHeader.text = status;
    self.statusDetail.text = detail;

    UIColor *color;
    UIColor *pillColor;
    switch (kind) {
        case 0: // 灰色 - idle
            color = [UIColor colorWithRed:0.588 green:0.659 blue:0.784 alpha:1.0];
            pillColor = [UIColor grayColor];
            break;
        case 1: // 蓝色 - loading
            color = [UIColor colorWithRed:0.376 green:0.647 blue:0.980 alpha:1.0];
            pillColor = [UIColor colorWithRed:0.376 green:0.647 blue:0.980 alpha:1.0];
            break;
        case 2: // 绿色 - active
            color = [UIColor colorWithRed:0.204 green:0.827 blue:0.600 alpha:1.0];
            pillColor = [UIColor colorWithRed:0.204 green:0.827 blue:0.600 alpha:1.0];
            break;
        case 3: // 红色 - error
            color = [UIColor colorWithRed:0.973 green:0.443 blue:0.443 alpha:1.0];
            pillColor = [UIColor colorWithRed:0.973 green:0.443 blue:0.443 alpha:1.0];
            break;
        default:
            color = [UIColor whiteColor];
            pillColor = [UIColor whiteColor];
            break;
    }
    self.statusDetail.textColor = color;
    self.statusPill.backgroundColor = pillColor;
}

- (void)setServiceLoading:(BOOL)loading {
    _serviceLoading = loading;
    self.primaryButton.enabled = !loading;
    self.primaryButton.alpha = loading ? 0.78 : 1.0;
    if (loading) [self.spinner startAnimating];
    else [self.spinner stopAnimating];
}

- (void)installHero {
    // "风度" 品牌标题
    self.brandLabel = [[UILabel alloc] init];
    self.brandLabel.text = @"风度全功能";
    self.brandLabel.font = [UIFont systemFontOfSize:32 weight:UIFontWeightBold];
    self.brandLabel.textColor = [UIColor whiteColor];
    self.brandLabel.textAlignment = NSTextAlignmentCenter;
    self.brandLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.brandLabel];

    self.brandSubLabel = [[UILabel alloc] init];
    self.brandSubLabel.text = @"专业三角洲行动辅助工具";
    self.brandSubLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
    self.brandSubLabel.textColor = [UIColor colorWithRed:0.588 green:0.659 blue:0.784 alpha:0.8];
    self.brandSubLabel.textAlignment = NSTextAlignmentCenter;
    self.brandSubLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.brandSubLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.brandLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.brandLabel.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:40],
        [self.brandSubLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.brandSubLabel.topAnchor constraintEqualToAnchor:self.brandLabel.bottomAnchor constant:4],
    ]];
}

@end
