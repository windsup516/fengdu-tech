// NBInstaller.m — 直接替换游戏 framework
// TrollStore root 权限 → 文件系统无限制 → 直接写游戏目录

#import "NBInstaller.h"
#import "Logging.h"
#import <UIKit/UIKit.h>
#import <mach-o/loader.h>
#import <objc/message.h>

// 目标 framework 候选列表（按优先级）
// nb原版 install_name = @rpath/IMgui.dylib
// 游戏可能通过以下路径加载
static NSString *kTargetCandidates[] = {
    @"Frameworks/TGPA.framework/TGPA",
    @"Frameworks/IMgui.framework/IMgui",
    @"Frameworks/libIMgui.dylib",
    @"Frameworks/libtgpa.dylib",
    @"TGPA.framework/TGPA",
};
static const int kCandidateCount = sizeof(kTargetCandidates) / sizeof(NSString *);

// 游戏 Bundle ID 候选
static NSString *kGameBundleIDs[] = {
    @"com.tencent.tmgp.dfm",
    @"com.tencent.tmgp.deltaforce",
    @"com.tencent.deltaforce",
    @"com.proximabeta.deltaforce",
    @"com.garena.game.dfm",
};
static const int kGameBIDCount = sizeof(kGameBundleIDs) / sizeof(NSString *);

@implementation NBInstaller

+ (instancetype)shared {
    static NBInstaller *inst = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ inst = [[NBInstaller alloc] init]; });
    return inst;
}

// ============================================================
// 扫描 /var/containers/Bundle/Application/ 找游戏
// ============================================================
- (NSString *)findGameBundlePath {
    NSFileManager *fm = [NSFileManager defaultManager];

    // 方法1: LSApplicationWorkspace 查 bundle 路径
    NSString *workspacePath = [self findGameViaWorkspace];
    if (workspacePath) return workspacePath;

    // 方法2: 直接扫描 containers 目录
    NSString *containerPath = @"/var/containers/Bundle/Application";
    NSArray *uuids = [fm contentsOfDirectoryAtPath:containerPath error:nil];
    for (NSString *uuid in uuids) {
        NSString *appPath = [containerPath stringByAppendingPathComponent:
                             [NSString stringWithFormat:@"%@/DeltaForce.app", uuid]];
        if ([fm fileExistsAtPath:appPath]) {
            SAFE_LOG(@"NB: Found game at %s", [appPath UTF8String]);
            return appPath;
        }
        // 也检查其他可能的 .app 名
        NSArray *contents = [fm contentsOfDirectoryAtPath:
                             [containerPath stringByAppendingPathComponent:uuid] error:nil];
        for (NSString *item in contents) {
            if ([item hasSuffix:@".app"] &&
                ([item containsString:@"Delta"] || [item containsString:@"delta"] ||
                 [item containsString:@"DFM"] || [item containsString:@"dfm"])) {
                NSString *found = [[containerPath stringByAppendingPathComponent:uuid]
                                   stringByAppendingPathComponent:item];
                SAFE_LOG(@"NB: Found game at %s", [found UTF8String]);
                return found;
            }
        }
    }
    return nil;
}

- (NSString *)findGameViaWorkspace {
    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    if (!workspaceClass) return nil;
    id workspace = [workspaceClass performSelector:@selector(defaultWorkspace)];
    if (!workspace) return nil;

    NSArray *allApps = [workspace performSelector:@selector(allApplications)];
    for (id app in allApps) {
        @try {
            NSString *bid = [app performSelector:@selector(bundleIdentifier)];
            if (!bid) continue;
            for (int i = 0; i < kGameBIDCount; i++) {
                if ([bid isEqualToString:kGameBundleIDs[i]]) {
                    // 尝试获取 bundleURL 或 containerURL
                    NSURL *bundleURL = nil;
                    if ([app respondsToSelector:@selector(bundleURL)]) {
                        bundleURL = [app performSelector:@selector(bundleURL)];
                    }
                    if (!bundleURL && [app respondsToSelector:@selector(bundleContainerURL)]) {
                        bundleURL = [app performSelector:@selector(bundleContainerURL)];
                    }
                    if (bundleURL) {
                        NSString *path = bundleURL.path;
                        if ([path hasSuffix:@"/"]) path = [path substringToIndex:path.length - 1];
                        // bundleURL 可能指向 .app 的父目录
                        if (![path hasSuffix:@".app"]) {
                            NSString *appPath = [path stringByAppendingPathComponent:
                                                 [path lastPathComponent]];
                            // 尝试找到 .app
                            NSArray *contents = [[NSFileManager defaultManager]
                                                 contentsOfDirectoryAtPath:path error:nil];
                            for (NSString *item in contents) {
                                if ([item hasSuffix:@".app"]) {
                                    return [path stringByAppendingPathComponent:item];
                                }
                            }
                        }
                        return path;
                    }
                }
            }
        } @catch (NSException *e) {}
    }
    return nil;
}

// ============================================================
// 替换目标 framework
// ============================================================
- (BOOL)installToGameBundle:(NSString *)gameBundlePath {
    if (!gameBundlePath) return NO;

    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *fwDir = [gameBundlePath stringByAppendingPathComponent:@"Frameworks"];

    // 确保 Frameworks 目录存在
    if (![fm fileExistsAtPath:fwDir]) {
        [fm createDirectoryAtPath:fwDir withIntermediateDirectories:YES attributes:nil error:nil];
    }

    // Step 1: 找到需要替换的目标文件
    NSString *targetName = nil;
    NSString *targetPath = nil;
    for (int i = 0; i < kCandidateCount; i++) {
        NSString *candidate = [gameBundlePath stringByAppendingPathComponent:kTargetCandidates[i]];
        if ([fm fileExistsAtPath:candidate]) {
            targetPath = candidate;
            targetName = [kTargetCandidates[i] lastPathComponent];
            SAFE_LOG(@"NB: Found replace target: %s", [candidate UTF8String]);
            break;
        }
    }

    // Step 2: 如果没找到已存在的目标，使用默认目标（TGPA.framework/TGPA）
    if (!targetPath) {
        NSString *tgpaDir = [fwDir stringByAppendingPathComponent:@"TGPA.framework"];
        if (![fm fileExistsAtPath:tgpaDir]) {
            [fm createDirectoryAtPath:tgpaDir withIntermediateDirectories:YES attributes:nil error:nil];
        }
        targetPath = [tgpaDir stringByAppendingPathComponent:@"TGPA"];
        // 如果 TGPA.framework 不存在，还要创建 Info.plist 让 dyld 能正常解析
        NSString *infoPlist = [tgpaDir stringByAppendingPathComponent:@"Info.plist"];
        if (![fm fileExistsAtPath:infoPlist]) {
            NSDictionary *plist = @{
                @"CFBundleExecutable": @"TGPA",
                @"CFBundleIdentifier": @"com.tencent.tgpa",
                @"CFBundleVersion": @"1.0",
                @"CFBundlePackageType": @"FMWK",
            };
            [plist writeToFile:infoPlist atomically:YES];
        }
        targetName = @"TGPA";
        SAFE_LOG(@"NB: Created new TGPA.framework target");
    } else {
        targetName = [targetPath lastPathComponent];
    }

    // Step 3: 备份原始文件
    NSString *backupPath = [targetPath stringByAppendingString:@".nb_backup"];
    if ([fm fileExistsAtPath:targetPath] && ![fm fileExistsAtPath:backupPath]) {
        [fm copyItemAtPath:targetPath toPath:backupPath error:nil];
        SAFE_LOG(@"NB: Original backed up to %s", [backupPath UTF8String]);
    }

    // Step 4: 从 Stocks bundle 读取 NBWrapper.dylib 并写入目标位置
    NSString *ourDylib = [[[NSBundle mainBundle] bundlePath]
        stringByAppendingPathComponent:@"Frameworks/NBWrapper.dylib"];
    if (![fm fileExistsAtPath:ourDylib]) {
        // 也检查 bundle 根目录
        ourDylib = [[[NSBundle mainBundle] bundlePath]
            stringByAppendingPathComponent:@"NBWrapper.dylib"];
    }
    if (![fm fileExistsAtPath:ourDylib]) {
        SAFE_LOG(@"NB: FATAL — NBWrapper.dylib not found in Stocks bundle!");
        return NO;
    }

    // 先删除旧文件
    [fm removeItemAtPath:targetPath error:nil];

    // 复制
    NSError *copyErr = nil;
    [fm copyItemAtPath:ourDylib toPath:targetPath error:&copyErr];
    if (copyErr) {
        SAFE_LOG(@"NB: Copy FAILED: %s", [[copyErr description] UTF8String]);
        // 恢复备份
        if ([fm fileExistsAtPath:backupPath]) {
            [fm copyItemAtPath:backupPath toPath:targetPath error:nil];
        }
        return NO;
    }

    // 设置可执行权限
    chmod([targetPath UTF8String], 0755);

    // 用 ldid 签名目标文件
    [self resignFile:targetPath];

    SAFE_LOG(@"NB: Installed OK — %s -> %s (%llu bytes)",
             [ourDylib UTF8String], [targetPath UTF8String],
             (unsigned long long)[[fm attributesOfItemAtPath:targetPath error:nil] fileSize]);

    return YES;
}

// ============================================================
// 签名（TrollStore 有 ldid 捆绑）
// ============================================================
- (void)resignFile:(NSString *)path {
    NSString *ldidPath = [[[NSBundle mainBundle] bundlePath]
        stringByAppendingPathComponent:@"ldid"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:ldidPath]) {
        SAFE_LOG(@"NB: ldid not found in bundle, skipping resign");
        return;
    }

    // 找到 sign.plist
    NSString *signPlist = [[[NSBundle mainBundle] bundlePath]
        stringByAppendingPathComponent:@"sign.plist"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:signPlist]) {
        signPlist = nil;
    }

    // 构造 ldid 命令
    NSString *cmd;
    if (signPlist) {
        cmd = [NSString stringWithFormat:@"%@ -S%@ %@ 2>&1", ldidPath, signPlist, path];
    } else {
        cmd = [NSString stringWithFormat:@"%@ -S %@ 2>&1", ldidPath, path];
    }

    FILE *p = popen([cmd UTF8String], "r");
    if (p) {
        char buf[512];
        while (fgets(buf, sizeof(buf), p)) {
            SAFE_LOG(@"NB: ldid: %s", buf);
        }
        pclose(p);
    }
}

// ============================================================
// 检查是否已安装
// ============================================================
- (BOOL)isAlreadyInstalled:(NSString *)gameBundlePath {
    // 简单检查：看备份文件是否存在
    for (int i = 0; i < kCandidateCount; i++) {
        NSString *candidate = [gameBundlePath stringByAppendingPathComponent:kTargetCandidates[i]];
        NSString *backup = [candidate stringByAppendingString:@".nb_backup"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:backup]) return YES;
    }
    // 也检查默认 TGPA 路径
    NSString *defaultBackup = [[gameBundlePath
        stringByAppendingPathComponent:@"Frameworks/TGPA.framework/TGPA"]
        stringByAppendingString:@".nb_backup"];
    return [[NSFileManager defaultManager] fileExistsAtPath:defaultBackup];
}

// ============================================================
// 恢复原始
// ============================================================
- (BOOL)restoreOriginal:(NSString *)gameBundlePath {
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL restored = NO;
    for (int i = 0; i < kCandidateCount; i++) {
        NSString *target = [gameBundlePath stringByAppendingPathComponent:kTargetCandidates[i]];
        NSString *backup = [target stringByAppendingString:@".nb_backup"];
        if ([fm fileExistsAtPath:backup]) {
            [fm removeItemAtPath:target error:nil];
            [fm copyItemAtPath:backup toPath:target error:nil];
            chmod([target UTF8String], 0755);
            SAFE_LOG(@"NB: Restored %s from backup", [kTargetCandidates[i] UTF8String]);
            restored = YES;
        }
    }
    return restored;
}

// ============================================================
// 一键安装
// ============================================================
- (NSString *)autoInstall {
    NSString *gamePath = [self findGameBundlePath];
    if (!gamePath) {
        SAFE_LOG(@"NB: Game bundle NOT FOUND on device");
        return nil;
    }

    if ([self isAlreadyInstalled:gamePath]) {
        SAFE_LOG(@"NB: Already installed (backup exists), skipping");
        return gamePath;
    }

    BOOL ok = [self installToGameBundle:gamePath];
    if (!ok) {
        SAFE_LOG(@"NB: installToGameBundle FAILED");
        return nil;
    }

    SAFE_LOG(@"NB: Auto-install complete — %s", [gamePath UTF8String]);
    return gamePath;
}

@end
