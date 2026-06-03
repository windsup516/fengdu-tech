// FBSOrientationObserver.h — FrontBoard Services orientation observer
// Matches 太阳神 rotation tracking for overlay layout
// Uses private FBSOrientationObserver API for device rotation

#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, DFOrientationState) {
    DFOrientationUnknown = 0,
    DFOrientationPortrait,
    DFOrientationLandscapeLeft,
    DFOrientationLandscapeRight,
    DFOrientationPortraitUpsideDown,
};

@protocol DFOrientationObserverDelegate <NSObject>
- (void)orientationDidChange:(DFOrientationState)newOrientation;
@end

@interface FBSOrientationObserver : NSObject

@property (nonatomic, weak) id<DFOrientationObserverDelegate> delegate;
@property (nonatomic, assign, readonly) DFOrientationState currentOrientation;
@property (nonatomic, assign, readonly) CGSize currentScreenSize;
@property (nonatomic, assign, readonly) BOOL isLandscape;

+ (instancetype)shared;
- (void)startObserving;
- (void)stopObserving;

@end
