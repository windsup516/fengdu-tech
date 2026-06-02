// Stocks.app (伪装) - Delta Force 作弊框架
// TrollStore + 越狱兼容版本
// arm64 iOS 13.0-16.x
// 伪装为苹果股票应用 (com.apple.stocks)
// Scene-based lifecycle (matching Amazon2 architecture)

#import <UIKit/UIKit.h>
#import "AppDelegate.h"

// Entry point
int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil,
               NSStringFromClass([AppDelegate class]));
    }
}
