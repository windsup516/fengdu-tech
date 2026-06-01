#ifndef CRYPTO_UTILS_H
#define CRYPTO_UTILS_H

#import <Foundation/Foundation.h>
#import <arm_neon.h>

// splitmix64 字符串解密
NSString* DecryptBytes(const uint8_t *encryptedBytes, uint64_t seed, NSInteger length);

// NEON 加速解密 (对应反编译中的 veorq_s8 / veor_s8)
NSString* DecryptBytesNEON(const uint8_t *encryptedBytes, 
                            int8x16_t xor_key1, int8x16_t xor_key2, 
                            NSInteger length);
NSString* DecryptXMMString(int8x16_t encrypted, int8x16_t xor_key);
NSString* DecryptQWordString(int8x8_t encrypted, int8x8_t xor_key);

// 三段 NEON XOR 解密 (对应原版 40 字节 SBS 类名解密)
// 结构: 16字节 veorq_s8 + 16字节 veorq_s8 + 8字节 veor_s8
// 返回解密后的 NSString (自动安全擦除)
NSString* DecryptSBSClassName(const int8_t part1[16], const int8_t key1[16],
                               const int8_t part2[16], const int8_t key2[16],
                               const int8_t part3[8],  int64_t key3);

#endif /* CRYPTO_UTILS_H */
