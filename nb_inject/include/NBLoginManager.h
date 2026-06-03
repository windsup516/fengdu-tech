// NBLoginManager — 16位卡密验证
// 当前版本：任意16位字符即可激活
#ifndef NB_LOGIN_MANAGER_H
#define NB_LOGIN_MANAGER_H

#import <Foundation/Foundation.h>

@interface NBLoginManager : NSObject

+ (instancetype)shared;

/// 验证卡密（16位，任意字符）
- (BOOL)verifyKey:(NSString *)key;

/// 是否已激活
@property (nonatomic, readonly) BOOL isActivated;

/// 当前卡密（激活后保存）
@property (nonatomic, copy, readonly) NSString *currentKey;

/// 持久化：保存/读取激活状态
- (void)loadSavedState;
- (void)saveActivatedState:(NSString *)key;

@end

#endif
