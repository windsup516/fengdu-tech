// FBSOrientationObserver.m — FrontBoard Services orientation observer implementation
// Monitors device rotation via private FBSOrientationObserver API
// Falls back to UIDevice notifications if private API not available

#import "FBSOrientationObserver.h"

@interface FBSOrientationObserver ()
@property (nonatomic, assign, readwrite) DFOrientationState currentOrientation;
@property (nonatomic, assign, readwrite) CGSize currentScreenSize;
@property (nonatomic, assign, readwrite) BOOL isLandscape;
@property (nonatomic, strong) id fbsObserver; // Private FBSOrientationObserver instance
@end

@implementation FBSOrientationObserver

+ (instancetype)shared {
    static FBSOrientationObserver *inst = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ inst = [[FBSOrientationObserver alloc] init]; });
    return inst;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self updateScreenState];
    }
    return self;
}

- (DFOrientationState)orientationFromUIDevice:(UIDeviceOrientation)deviceOrientation {
    switch (deviceOrientation) {
        case UIDeviceOrientationPortrait:
            return DFOrientationPortrait;
        case UIDeviceOrientationLandscapeLeft:
            return DFOrientationLandscapeLeft;
        case UIDeviceOrientationLandscapeRight:
            return DFOrientationLandscapeRight;
        case UIDeviceOrientationPortraitUpsideDown:
            return DFOrientationPortraitUpsideDown;
        default:
            return DFOrientationUnknown;
    }
}

- (void)updateScreenState {
    UIScreen *screen = [UIScreen mainScreen];
    _currentScreenSize = screen.bounds.size;

    DFOrientationState orientation = [self orientationFromUIDevice:[UIDevice currentDevice].orientation];
    if (orientation == DFOrientationUnknown) {
        // Fallback: determine from screen size
        if (_currentScreenSize.width > _currentScreenSize.height) {
            orientation = DFOrientationLandscapeLeft;
        } else {
            orientation = DFOrientationPortrait;
        }
    }
    _currentOrientation = orientation;
    _isLandscape = (orientation == DFOrientationLandscapeLeft ||
                    orientation == DFOrientationLandscapeRight);
}

- (void)startObserving {
    // Method 1: Try private FBSOrientationObserver class
    Class fbsClass = NSClassFromString(@"FBSOrientationObserver");
    if (fbsClass) {
        _fbsObserver = [[fbsClass alloc] init];
        // FBSOrientationObserver posts notifications or uses delegate pattern
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(fbsOrientationChanged:)
                                                     name:@"FBSOrientationDidChangeNotification"
                                                   object:nil];
        return;
    }

    // Method 2: Fallback to UIDevice notifications
    [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(deviceOrientationChanged:)
                                                 name:UIDeviceOrientationDidChangeNotification
                                               object:nil];

    // Also observe screen size changes (external display, etc.)
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(screenSizeChanged:)
                                                 name:UIScreenDidConnectNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(screenSizeChanged:)
                                                 name:UIScreenModeDidChangeNotification
                                               object:nil];
}

- (void)stopObserving {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [[UIDevice currentDevice] endGeneratingDeviceOrientationNotifications];
    _fbsObserver = nil;
}

- (void)fbsOrientationChanged:(NSNotification *)note {
    [self updateScreenState];
    if ([self.delegate respondsToSelector:@selector(orientationDidChange:)]) {
        [self.delegate orientationDidChange:_currentOrientation];
    }
}

- (void)deviceOrientationChanged:(NSNotification *)note {
    [self updateScreenState];
    if ([self.delegate respondsToSelector:@selector(orientationDidChange:)]) {
        [self.delegate orientationDidChange:_currentOrientation];
    }
}

- (void)screenSizeChanged:(NSNotification *)note {
    [self updateScreenState];
    if ([self.delegate respondsToSelector:@selector(orientationDidChange:)]) {
        [self.delegate orientationDidChange:_currentOrientation];
    }
}

- (void)dealloc {
    [self stopObserving];
}

@end
