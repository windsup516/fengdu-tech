// CryptoUtils - splitmix64 + NEON XOR 字符串解密引擎
// 从反编译恢复的完整解密实现
// 用于所有授权界面文本的运行时解密

#import "CryptoUtils.h"
#import <string.h>
#import <arm_neon.h>

// splitmix64 伪随机数生成器
static uint64_t splitmix64_next(uint64_t *state) {
    uint64_t z = *state;
    z = 0xBF58476D1CE4E5B9ULL * (z ^ (z >> 30));
    z = 0x94D049BB133111EBULL * (z ^ (z >> 27));
    *state -= 0x61C8864680B583EBULL; // 黄金比例步进
    return z ^ (z >> 31);
}

NSString* DecryptBytes(const uint8_t *encryptedBytes, uint64_t seed, NSInteger length) {
    if (!encryptedBytes || length <= 0 || length > 256) return nil;
    
    uint8_t buffer[256] = {0};
    uint64_t state = seed;
    
    // 使用 splitmix64 生成 XOR 密钥流
    for (NSInteger i = 0; i < length; i++) {
        uint64_t rand = splitmix64_next(&state);
        buffer[i] = encryptedBytes[i] ^ (uint8_t)((rand >> 31) ^ rand);
    }
    
    NSString *result = [NSString stringWithUTF8String:(const char *)buffer];
    
    // 安全擦除 - 防止内存扫描
    memset(buffer, 0, sizeof(buffer));
    
    return result;
}

// NEON 加速版本 - 一次解密 16 字节
NSString* DecryptBytesNEON(const uint8_t *encryptedBytes, 
                           int8x16_t xor_key1, int8x16_t xor_key2, 
                           NSInteger length) {
    if (!encryptedBytes || length <= 0) return nil;
    
    uint8_t buffer[256] = {0};
    NSInteger remaining = length;
    NSInteger offset = 0;
    
    while (remaining >= 16) {
        int8x16_t encrypted = vld1q_s8((int8_t *)(encryptedBytes + offset));
        int8x16_t decrypted1 = veorq_s8(encrypted, xor_key1);
        int8x16_t decrypted2 = veorq_s8(decrypted1, xor_key2);
        vst1q_s8((int8_t *)(buffer + offset), decrypted2);
        remaining -= 16;
        offset += 16;
    }
    
    // 处理剩余字节
    if (remaining > 0) {
        for (NSInteger i = 0; i < remaining; i++) {
            buffer[offset + i] = encryptedBytes[offset + i] ^ 0xFF;
        }
    }
    
    NSString *result = [NSString stringWithUTF8String:(const char *)buffer];
    memset(buffer, 0, sizeof(buffer));
    
    return result;
}

// 使用 128-bit XOR key 解密 (对应 veorq_s8 指令)
NSString* DecryptXMMString(int8x16_t encrypted, int8x16_t xor_key) {
    int8x16_t decrypted = veorq_s8(encrypted, xor_key);
    char buffer[17] = {0};
    vst1q_s8((int8_t *)buffer, decrypted);
    return [NSString stringWithUTF8String:buffer];
}

// 使用 64-bit XOR key 解密 (对应 veor_s8 指令)
NSString* DecryptQWordString(int8x8_t encrypted, int8x8_t xor_key) {
    int8x8_t decrypted = veor_s8(encrypted, xor_key);
    char buffer[9] = {0};
    vst1_s8((int8_t *)buffer, decrypted);
    return [NSString stringWithUTF8String:buffer];
}

// 三段 NEON XOR 解密 (40字节, 对应 SBSAccessibilityWindowHostingController 类名解密)
// 原版反编译结构:
//   xmmword_10134CF10 ^ xmmword_100122900  → 16字节 (veorq_s8)
//   xmmword_10134CF20 ^ xmmword_100122910  → 16字节 (veorq_s8)
//   qword_10134CF30  ^ 0x3BD3649011612E66  → 8字节 (veor_s8)
NSString* DecryptSBSClassName(const int8_t part1[16], const int8_t key1[16],
                               const int8_t part2[16], const int8_t key2[16],
                               const int8_t part3[8],  int64_t key3) {
    char buffer[41] = {0};
    
    // 第1段: 128-bit NEON XOR
    int8x16_t enc1 = vld1q_s8(part1);
    int8x16_t k1   = vld1q_s8(key1);
    int8x16_t dec1 = veorq_s8(enc1, k1);
    vst1q_s8((int8_t *)(buffer + 0), dec1);
    
    // 第2段: 128-bit NEON XOR
    int8x16_t enc2 = vld1q_s8(part2);
    int8x16_t k2   = vld1q_s8(key2);
    int8x16_t dec2 = veorq_s8(enc2, k2);
    vst1q_s8((int8_t *)(buffer + 16), dec2);
    
    // 第3段: 64-bit NEON XOR
    int8x8_t enc3 = vld1_s8(part3);
    int8x8_t k3   = vreinterpret_s8_s64(vdup_n_s64(key3));
    int8x8_t dec3 = veor_s8(enc3, k3);
    vst1_s8((int8_t *)(buffer + 32), dec3);
    
    NSString *result = [NSString stringWithUTF8String:buffer];
    
    // 安全擦除
    memset(buffer, 0, sizeof(buffer));
    
    return result;
}
