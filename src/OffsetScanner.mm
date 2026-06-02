// OffsetScanner.mm — UE4 GWorld/GName 签名扫描 + 指针解密
// 基于红狼 translate 二进制 IDA Pro 逆向 + Amazon/太阳神参考
//
// 红狼核心发现 (IDA):
//   - GWorld 指针: NO XOR on pointer itself, plain mach_vm_read_overwrite
//   - GName XOR:   xorString @ 0x1000DF968, 9-variant switch dispatch
//   - GName table:  base + 0x143977C0 (红狼) / 需运行时定位
//   - 偏移全硬编码, 无 AOB 扫描
//   - 进程发现: sysctl(KERN_PROC_ALL) → task_for_pid_workaround
//
// 本实现改进:
//   1. ADRP+LDR 指令解码器 → 自动扫描 GWorld 引用
//   2. GName xorString 完整实现 (9 case)
//   3. UWorld→PersistentLevel→Actors TArray 遍历
//   4. 运行时验证 (检查读出的值是否在合理范围)

#import "OffsetScanner.h"
#import "Logging.h"
#import <mach/mach.h>
#import <mach/vm_map.h>
#import <mach-o/loader.h>
#import <mach-o/fat.h>
#import <string.h>

ScannedOffsets g_scanned_offsets = {0};

#pragma mark - ARM64 指令解码

uint64_t arm64_decode_adrp(uint32_t instr, uint64_t pc) {
    // ADRP: [31]=1, [30:29]=immlo, [28:24]=10000, [23:5]=immhi, [4:0]=Rd
    if ((instr & 0x9F000000) != 0x90000000) return 0;

    int64_t immhi = ((int64_t)(instr >> 5) & 0x7FFFF) << 2;   // bits [23:5]
    int64_t immlo = ((int64_t)(instr >> 29) & 0x3);             // bits [30:29]
    int64_t imm = (immhi | immlo) << 12;                        // 33-bit signed, shift left 12
    // Sign extend from 33 bits
    if (imm & (1LL << 32)) imm |= ~((1LL << 33) - 1);

    uint64_t pageBase = (pc & ~0xFFFULL) + (int64_t)imm;
    return pageBase;
}

uint64_t arm64_decode_ldr_offset(uint32_t instr) {
    // LDR (unsigned offset) 64-bit: 11 111 0 01 01 imm12 Rn Rt
    // size=11 (64-bit), V=0, opc=01 (load)
    if ((instr & 0xFFC00000) != 0xF9400000) return 0;

    uint64_t imm12 = (instr >> 10) & 0xFFF;  // scaled by 8 for 64-bit
    return imm12 * 8;  // Return byte offset
}

uint64_t arm64_decode_add_imm(uint32_t instr) {
    // ADD (immediate): 1 0 0 10001 sh imm12 Rn Rd
    if ((instr & 0xFF800000) != 0x91000000) return 0;

    uint64_t imm12 = (instr >> 10) & 0xFFF;
    uint8_t sh = (instr >> 22) & 0x3;
    return imm12 << (sh * 12);  // lsl #0 or #12
}

uint64_t arm64_decode_movz(uint32_t instr) {
    // MOVZ: 1 10 100101 hw imm16 Rd
    if ((instr & 0xFF800000) != 0xD2800000) return 0;

    uint64_t imm16 = (instr >> 5) & 0xFFFF;
    uint8_t hw = (instr >> 21) & 0x3;
    return imm16 << (hw * 16);
}

uint64_t arm64_decode_movk(uint32_t instr, uint64_t existing) {
    // MOVK: 1 11 100101 hw imm16 Rd
    if ((instr & 0xFF800000) != 0xF2800000) return 0;

    uint64_t imm16 = (instr >> 5) & 0xFFFF;
    uint8_t hw = (instr >> 21) & 0x3;
    uint64_t mask = ~(0xFFFFULL << (hw * 16));
    existing &= mask;
    return existing | (imm16 << (hw * 16));
}

// === 游戏内存读写工具 ===

static kern_return_t scan_read(mach_port_t task, uint64_t addr, void *buf, size_t size) {
    vm_size_t outSz = size;
    return vm_read_overwrite(task, (vm_address_t)addr, size, (vm_address_t)buf, &outSz);
}

static kern_return_t scan_read_uint32(mach_port_t task, uint64_t addr, uint32_t *out) {
    return scan_read(task, addr, out, sizeof(uint32_t));
}

static kern_return_t scan_read_uint64(mach_port_t task, uint64_t addr, uint64_t *out) {
    return scan_read(task, addr, out, sizeof(uint64_t));
}

#pragma mark - AOB 扫描

uint64_t aob_scan(mach_port_t task, uint64_t start, uint64_t end,
                  const uint8_t *pattern, const uint8_t *mask, size_t len) {
    if (end <= start || len == 0 || len > 256) return 0;

    size_t bufSize = 0x10000; // 64KB chunks
    uint8_t *buf = (uint8_t *)malloc(bufSize);
    if (!buf) return 0;

    uint64_t result = 0;

    for (uint64_t addr = start; addr + len < end; ) {
        size_t chunkSize = bufSize;
        if (addr + chunkSize > end) chunkSize = (size_t)(end - addr);

        if (scan_read(task, addr, buf, chunkSize) != KERN_SUCCESS) {
            addr += chunkSize;
            continue;
        }

        for (size_t i = 0; i + len <= chunkSize; i++) {
            BOOL match = YES;
            for (size_t j = 0; j < len; j++) {
                if (mask[j] == 0xFF && buf[i + j] != pattern[j]) {
                    match = NO;
                    break;
                }
            }
            if (match) {
                result = addr + i;
                goto done;
            }
        }

        addr += chunkSize - len + 1; // overlap by len-1 to catch cross-chunk matches
    }

done:
    free(buf);
    return result;
}

#pragma mark - GWorld 签名扫描

// ADRP 指令模式: 寻找被多个函数引用的全局指针 (候选 GWorld)
// ARM64 常见模式:
//   ADRP Xn, #page    → 页基址
//   LDR  Xm, [Xn, #offset] → 加载 GWorld 指针

typedef struct {
    uint64_t target_addr;   // 解码后的目标地址 (DATA段)
    uint64_t func_addr;     // 所在函数地址
    uint8_t  reg_num;       // 目标寄存器
} AdrpLdrRef;

// 构建 ADRP+LDR 目标地址的字节扫描掩码
// 模式: ADRP x?, #imm + LDR x?, [x?, #imm]
// ADRP: 0x?0 0x00 0x00 0x90 (bits 30:29 = immlo)
// LDR:  0x?8 0x?0 0x40 0xF9 (ldr x?, [x?, #?])
//
// 更精确: 扫描 TEXT 段中所有 ADRP+LDR 对, 解码目标地址

uint64_t scan_gworld(mach_port_t task, uint64_t text_start, uint64_t text_end,
                     uint64_t data_start, uint64_t data_end) {
    HOOKS_LOG(@"GWorld scan: TEXT 0x%llx-0x%llx DATA 0x%llx-0x%llx",
              text_start, text_end, data_start, data_end);

    if (text_end <= text_start) return 0;

    size_t textSize = (size_t)(text_end - text_start);
    uint32_t *textBuf = (uint32_t *)malloc(textSize);
    if (!textBuf) return 0;

    if (scan_read(task, text_start, textBuf, textSize) != KERN_SUCCESS) {
        free(textBuf);
        return 0;
    }

    size_t instrCount = textSize / 4;
    uint64_t bestAddr = 0;
    int bestRefs = 0;

    // 扫描所有 ADRP 指令, 解码目标地址, 统计对 DATA 段的引用
    for (size_t i = 0; i + 2 < instrCount; i++) {
        uint32_t instr0 = textBuf[i];     // ADRP
        uint32_t instr1 = textBuf[i + 1]; // LDR

        // 检查指令1: ADRP
        if ((instr0 & 0x9F000000) != 0x90000000) continue;

        // 提取 ADRP 目标寄存器
        uint8_t rd_adrp = instr0 & 0x1F;

        // 检查指令2: LDR (64-bit unsigned offset, Rn == ADRP Rd)
        uint8_t rn_ldr = (instr1 >> 5) & 0x1F;
        uint8_t rt_ldr = instr1 & 0x1F;

        // LDR (unsigned offset, 64-bit): 11 111 0 01 01 imm12 Rn Rt
        if ((instr1 & 0xFFC00000) == 0xF9400000 && rn_ldr == rd_adrp) {
            uint64_t pc = text_start + i * 4;
            uint64_t pageBase = arm64_decode_adrp(instr0, pc);
            uint64_t byteOffset = arm64_decode_ldr_offset(instr1);

            if (pageBase == 0) continue;

            uint64_t targetAddr = pageBase + byteOffset;

            // 只关心指向 DATA 段的引用
            if (targetAddr >= data_start && targetAddr < data_end) {
                // 读取目标地址的值 (GWorld 候选)
                uint64_t pointedValue = 0;
                if (scan_read_uint64(task, targetAddr, &pointedValue) == KERN_SUCCESS) {
                    if (pointedValue > 0x100000000 && pointedValue < 0x200000000) {
                        // 计数引用 (相同目标的引用越多越可能是 GWorld)
                        int refCount = 1;
                        for (size_t j = i + 3; j + 1 < instrCount; j++) {
                            uint32_t ij0 = textBuf[j];
                            uint32_t ij1 = textBuf[j + 1];
                            if ((ij0 & 0x9F000000) != 0x90000000) continue;
                            uint8_t rj = ij0 & 0x1F;
                            uint8_t nl = (ij1 >> 5) & 0x1F;
                            if ((ij1 & 0xFFC00000) == 0xF9400000 && nl == rj) {
                                uint64_t pj = text_start + j * 4;
                                uint64_t pb = arm64_decode_adrp(ij0, pj);
                                uint64_t bo = arm64_decode_ldr_offset(ij1);
                                if (pb && pb + bo == targetAddr) refCount++;
                            }
                            // 限制搜索范围, 避免扫描整个 TEXT
                            if (j > i + 5000) break;
                        }

                        if (refCount > bestRefs) {
                            bestRefs = refCount;
                            bestAddr = targetAddr;
                            HOOKS_LOG(@"GWorld candidate: *0x%llx=0x%llx refs=%d",
                                      targetAddr, pointedValue, refCount);
                        }
                    }
                }
            }
        }
    }

    free(textBuf);

    if (bestAddr && bestRefs >= 3) {
        uint64_t gworld = 0;
        scan_read_uint64(task, bestAddr, &gworld);
        HOOKS_LOG(@"GWorld found: addr=0x%llx value=0x%llx refs=%d",
                  bestAddr, gworld, bestRefs);
    } else {
        HOOKS_LOG(@"GWorld scan: no high-confidence candidate (best refs=%d)", bestRefs);
    }

    return bestAddr;
}

#pragma mark - GName XOR 解密

// 红狼 xorString 完整实现 (sub_1000DF968)
// 计算单字节 XOR 密钥 — 同一个 XOR 字节应用到整个字符串

static uint8_t compute_xor_byte(size_t length, uint16_t key) {
    uint64_t switchIdx = (key >> 6) % 9;
    uint64_t t = 0;

    switch (switchIdx) {
        case 0: t = length + ((key >> 6) & 0x1F); break;
        case 1: t = (length ^ 0xDF) + length; break;
        case 2: t = (length | 0xCF) + length; break;
        case 3: t = 0x21 * length; break;
        case 4: t = length + (key >> 8); break;
        case 5: t = 3 * length + 5; break;
        case 6: t = ((4 * length) | 5) + length; break;
        case 7: t = length + ((key >> 10) | 7); break;
        case 8: t = (length ^ 0xC) + length; break;
        default: return 0; // No XOR
    }

    return (uint8_t)((t | 0x7F) + 0x80);
}

NSString *decrypt_gname_string(mach_port_t task, uint64_t nameEntryAddr,
                                uint16_t key, size_t length) {
    if (length == 0 || length > 256) return nil;

    uint8_t encrypted[256] = {0};
    if (scan_read(task, nameEntryAddr, encrypted, length) != KERN_SUCCESS) return nil;

    uint8_t xorByte = compute_xor_byte(length, key);
    uint8_t decrypted[257] = {0};

    for (size_t i = 0; i < length; i++) {
        decrypted[i] = encrypted[i] ^ xorByte;
    }
    decrypted[length] = '\0';

    return [NSString stringWithUTF8String:(const char *)decrypted];
}

#pragma mark - FName 解析

// FName 结构: Index (uint32) + Number (uint32)
// Index 用于在 GName 表中查找字符串
// GName 表结构 (UE4.24+):
//   GNames (TNameEntryArray)
//   Chunks: array of pointers to 0x8000-entry chunks

NSString *resolve_fname(mach_port_t task, uint64_t gameBase, uint32_t fnameIndex) {
    // GName 表偏移 — 需要运行时从符号定位
    // 参见红狼: _GNames at [0x100EB5200] + 0x143977C0
    // Delta Force 需通过特征扫描定位 _GNames

    // GName 表 chunk 结构常量
    static const int STRIDE = 2;            // FNameEntry 步长
    static const int CHUNK_SIZE = 0x8000;   // 每个 chunk 的条目数
    static const int HEADER_SIZE = 0xC8;    // Chunk header 大小

    // TODO: 扫描 GName 表基址
    // 目前使用硬编码偏移 (需每版本验证)
    uint64_t gname_base = gameBase + 0x0EE5000; // 临时: 需替换为扫描结果

    // 读取 chunk table
    uint64_t chunkTable = 0;
    uint32_t chunkIdx = fnameIndex / CHUNK_SIZE;
    uint32_t withinChunk = fnameIndex % CHUNK_SIZE;

    // FNameEntryHandle 查找
    // Entry = Chunk[chunkIdx] + withinChunk * STRIDE
    uint64_t chunkPtr = 0;
    uint64_t chunkTableEntry = gname_base + chunkIdx * 8 + HEADER_SIZE;
    if (scan_read_uint64(task, chunkTableEntry, &chunkPtr) != KERN_SUCCESS || !chunkPtr)
        return nil;

    // 读取 FNameEntry (2字节 header: flags+length)
    uint64_t entryAddr = chunkPtr + withinChunk * STRIDE + 2;
    uint16_t header = 0;
    if (scan_read(task, entryAddr - 2, &header, sizeof(header)) != KERN_SUCCESS)
        return nil;

    // header 编码: high 6 bits = length, low 10 bits = flags
    uint16_t nameLen = header >> 6;
    uint16_t flags = header & 0x3F;

    if (nameLen == 0 || nameLen > 256) return nil;

    // 如果有 wide char flag, 长度加倍
    if (flags & 0x01) nameLen *= 2;

    return decrypt_gname_string(task, entryAddr, header, nameLen);
}

#pragma mark - UWorld 实体遍历

// UWorld → PersistentLevel (ULevel) → Actors (TArray<AActor*>)
// UE4.x typical offsets:
//   UWorld::PersistentLevel  = 0x30
//   ULevel::Actors            = 0x98 (TArray: ptr at +0, count at +8, max at +0x10)

int get_actors_from_world(mach_port_t task, uint64_t gworld,
                          uint64_t *out_actors_array, int *out_actor_count) {
    if (!gworld || !out_actors_array || !out_actor_count) return -1;

    // UWorld + 0x30 → ULevel*
    uint64_t persistentLevel = 0;
    if (scan_read_uint64(task, gworld + 0x30, &persistentLevel) != KERN_SUCCESS)
        return -1;
    if (!persistentLevel || persistentLevel < 0x100000000) return -1;

    // ULevel + 0x98 → TArray<AActor*>
    uint64_t actorsPtr = 0;
    int32_t actorsCount = 0;
    if (scan_read(task, persistentLevel + 0x98, &actorsPtr, sizeof(uint64_t)) != KERN_SUCCESS)
        return -1;
    if (scan_read(task, persistentLevel + 0x98 + 8, &actorsCount, sizeof(int32_t)) != KERN_SUCCESS)
        return -1;

    if (!actorsPtr || actorsCount <= 0 || actorsCount > 5000) return -1;

    *out_actors_array = actorsPtr;
    *out_actor_count = actorsCount;
    return 0;
}

#pragma mark - 实体类名

NSString *get_entity_class_name(mach_port_t task, uint64_t gameBase, uint64_t entity) {
    if (!entity) return nil;

    // UE4 UObject 布局:
    //   +0x00: vtable ptr
    //   +0x18: FName NamePrivate (Index+Number)
    uint32_t fnameIndex = 0;
    if (scan_read(task, entity + 0x18, &fnameIndex, sizeof(uint32_t)) != KERN_SUCCESS)
        return nil;

    return resolve_fname(task, gameBase, fnameIndex);
}

#pragma mark - 主扫描入口

// 验证地址是否在合理范围内
static BOOL is_valid_heap_ptr(uint64_t addr) {
    return addr > 0x100000000 && addr < 0x200000000;
}

// 扫描 __TEXT 和 __DATA 段
static BOOL find_segments(mach_port_t task, uint64_t *out_text_start, uint64_t *out_text_end,
                           uint64_t *out_data_start, uint64_t *out_data_end) {
    vm_address_t addr = 0;
    vm_size_t size = 0;
    mach_msg_type_number_t depth = 1;

    BOOL found_text = NO, found_data = NO;

    while (1) {
        struct vm_region_submap_info_64 info;
        mach_msg_type_number_t count = VM_REGION_SUBMAP_INFO_COUNT_64;
        kern_return_t kr = vm_region_64(task, &addr, &size, VM_REGION_BASIC_INFO_64,
                                         (vm_region_info_t)&info, &count, &depth);
        if (kr != KERN_SUCCESS || addr > 0x200000000) break;

        // __TEXT: executable, readable
        if ((info.protection & VM_PROT_EXECUTE) && (info.protection & VM_PROT_READ)) {
            if (!found_text) {
                *out_text_start = addr;
                *out_text_end = addr + size;
                found_text = YES;
            } else {
                // Extend text region
                if (addr + size > *out_text_end) *out_text_end = addr + size;
            }
        }

        // __DATA: writable, readable
        if ((info.protection & VM_PROT_WRITE) && !(info.protection & VM_PROT_EXECUTE)) {
            if (!found_data) {
                *out_data_start = addr;
                *out_data_end = addr + size;
                found_data = YES;
            }
        }

        addr += size;
    }

    return found_text && found_data;
}

int scan_all_offsets(mach_port_t task, uint64_t gameBase) {
    if (task == MACH_PORT_NULL || gameBase == 0) return -1;

    HOOKS_LOG(@"=== scan_all_offsets: base=0x%llx ===", gameBase);

    // Step 1: 定位 TEXT / DATA 段
    uint64_t text_start = 0, text_end = 0, data_start = 0, data_end = 0;
    if (!find_segments(task, &text_start, &text_end, &data_start, &data_end)) {
        HOOKS_LOG(@"Failed to find TEXT/DATA segments");
        return -1;
    }
    HOOKS_LOG(@"Segments: TEXT=0x%llx-0x%llx DATA=0x%llx-0x%llx",
              text_start, text_end, data_start, data_end);

    // Step 2: 扫描 GWorld
    uint64_t gworld_ptr_addr = scan_gworld(task, text_start, text_end, data_start, data_end);
    if (gworld_ptr_addr) {
        g_scanned_offsets.gworld_ptr = gworld_ptr_addr;
        g_scanned_offsets.gworld_found = YES;
    } else {
        HOOKS_LOG(@"GWorld scan failed — will use hardcoded offsets as fallback");
    }

    // Step 3: 读取 GWorld 值 (用于验证)
    uint64_t gworld = 0;
    if (gworld_ptr_addr) {
        scan_read_uint64(task, gworld_ptr_addr, &gworld);
        HOOKS_LOG(@"GWorld value: 0x%llx (valid=%d)", gworld, is_valid_heap_ptr(gworld));
    }

    // Step 4: 尝试遍历 Actors (验证 UWorld 结构)
    if (gworld && is_valid_heap_ptr(gworld)) {
        uint64_t actorsArray = 0;
        int actorsCount = 0;
        if (get_actors_from_world(task, gworld, &actorsArray, &actorsCount) == 0) {
            HOOKS_LOG(@"Actors: array=0x%llx count=%d", actorsArray, actorsCount);
        } else {
            HOOKS_LOG(@"Failed to read Actors from UWorld — UWorld may be stale");
        }
    }

    // Step 5: 设置已知的 UE4 引擎偏移 (这些很少变化)
    g_scanned_offsets.uworld_persistent_level  = 0x30;
    g_scanned_offsets.ulevel_actors            = 0x98;
    g_scanned_offsets.aactor_rootcomponent     = 0x188;
    g_scanned_offsets.aactor_mesh              = 0x2D0;
    g_scanned_offsets.aactor_playerstate       = 0x290;
    g_scanned_offsets.uscenecomponent_translation = 0x140;
    g_scanned_offsets.uskinnedmesh_bones       = 0x6F0;
    g_scanned_offsets.uskeletalmesh_componenttoworld = 0x1E0;

    // Step 6: 游戏特定偏移 (硬编码基线, 需每版本验证)
    g_scanned_offsets.aactor_health       = 0x120;
    g_scanned_offsets.aactor_max_health   = 0x124;
    g_scanned_offsets.aactor_team_id      = 0xF0;
    g_scanned_offsets.aactor_pose_state   = 0x418;
    g_scanned_offsets.playercontroller_camera = 0x3D0;
    g_scanned_offsets.player_camera_manager   = 0x330;
    g_scanned_offsets.weapon_recoil       = 0x2B0;
    g_scanned_offsets.weapon_spread       = 0x2C0;

    g_scanned_offsets.scanned = YES;
    HOOKS_LOG(@"=== scan_all_offsets complete (gworld=%d gname=%d) ===",
              g_scanned_offsets.gworld_found, g_scanned_offsets.gname_found);

    return g_scanned_offsets.gworld_found ? 0 : -2;
}
