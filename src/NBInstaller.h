// NBInstaller — 直接替换游戏 framework（TrollStore root 权限）
// 运行原理: TrollStore 安装的 Stocks 有 root 权限，可以直接写游戏 bundle 目录
// 不需要重新打包 IPA，每次启动游戏前自动替换目标 dylib

#import <Foundation/Foundation.h>

@interface NBInstaller : NSObject

+ (instancetype)shared;

/// 扫描并返回游戏安装路径 (DeltaForce.app)
- (NSString *)findGameBundlePath;

/// 将内嵌的 NBWrapper.dylib 替换到游戏 Frameworks/ 目录
/// @param gameBundlePath 游戏 .app 完整路径
/// @return YES 如果替换成功
- (BOOL)installToGameBundle:(NSString *)gameBundlePath;

/// 一键操作：找游戏 → 替换 → 返回游戏路径
- (NSString *)autoInstall;

/// 查看目标 framework 是否已被替换
- (BOOL)isAlreadyInstalled:(NSString *)gameBundlePath;

/// 恢复原始 framework（从备份）
- (BOOL)restoreOriginal:(NSString *)gameBundlePath;

@end
