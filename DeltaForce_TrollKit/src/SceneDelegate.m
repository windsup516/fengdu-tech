// SceneDelegate - 场景代理 (匹配原版 Info.plist 声明)
// 空实现 - 窗口由 AppDelegate 全权处理
// 仅用于满足 iOS 13+ 场景生命周期, 防止 Info.plist 报错

#import <UIKit/UIKit.h>

@interface SceneDelegate : UIResponder <UIWindowSceneDelegate>
@end

@implementation SceneDelegate
// 窗口创建 + 生命周期全部由 AppDelegate 处理
// SceneDelegate 仅做占位, 避免 UIKit 报 "无法实例化 SceneDelegate" 的错
@end
