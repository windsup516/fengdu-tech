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

#endif /* CRYPTO_UTILS_H */
