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
#import <QuartzCore/QuartzCore.h>
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

// 验证地址是否在合理范围内 (堆范围 + 8字节对齐)
static BOOL is_valid_heap_ptr(uint64_t addr) {
    return addr > 0x100000000 && addr < 0x200000000 && (addr & 0x7) == 0;
}

// 真正的堆地址: 不在 TEXT, 不在任何 Mach-O 段内
static BOOL is_real_heap(uint64_t addr, uint64_t text_start, uint64_t text_end,
                          uint64_t *data_starts, uint64_t *data_ends, int data_count,
                          uint64_t *const_starts, uint64_t *const_ends, int const_count) {
    if (addr >= text_start && addr < text_end) return NO;
    for (int i = 0; i < data_count; i++) {
        if (addr >= data_starts[i] && addr < data_ends[i]) return NO;
    }
    for (int i = 0; i < const_count; i++) {
        if (addr >= const_starts[i] && addr < const_ends[i]) return NO;
    }
    return is_valid_heap_ptr(addr);
}

// vtable 有效性: 必须在任何 Mach-O 静态段内 (TEXT/DATA_CONST/AUTH_CONST/DATA)
// 不同编译器/SDK vtable 位置不同: 旧版放 __TEXT, 新版放 __DATA_CONST, 某些放 __DATA
// 但 vtable 绝不在堆上 — 可以通过排除堆来判断
static BOOL is_valid_vtable(uint64_t vtable, uint64_t text_start, uint64_t text_end,
                             uint64_t *const_starts, uint64_t *const_ends, int const_count,
                             uint64_t *data_starts, uint64_t *data_ends, int data_count) {
    if (vtable & 0x7) return NO; // ARM64 对齐
    // 堆范围检查: vtable 不应该在堆上
    if (vtable < 0x100000000 || vtable >= 0x200000000) return NO;
    // 在任何 Mach-O 映射段内即为有效 vtable
    if (vtable >= text_start && vtable < text_end) return YES;
    for (int i = 0; i < const_count; i++) {
        if (vtable >= const_starts[i] && vtable < const_ends[i]) return YES;
    }
    for (int i = 0; i < data_count; i++) {
        if (vtable >= data_starts[i] && vtable < data_ends[i]) return YES;
    }
    return NO;
}

// 解析 Mach-O header 获取精确的段范围
// 区分三种段类型: TEXT (代码), DATA_WRITABLE (__DATA/__BSS/__DATA_DIRTY), DATA_CONST (__DATA_CONST/__AUTH_CONST)
// iOS 上 C++ vtables 和 GOT 在 DATA_CONST 中, 不在 TEXT
static BOOL find_segments(mach_port_t task, uint64_t gameBase,
                           uint64_t *out_text_start, uint64_t *out_text_end,
                           uint64_t *out_data_starts, uint64_t *out_data_ends, int *out_data_count, int max_data,
                           uint64_t *out_const_starts, uint64_t *out_const_ends, int *out_const_count, int max_const) {
    struct mach_header_64 mh;
    if (scan_read(task, gameBase, &mh, sizeof(mh)) != KERN_SUCCESS) {
        HOOKS_LOG(@"find_segments: failed to read Mach-O header at 0x%llx", gameBase);
        return NO;
    }
    if (mh.magic != MH_MAGIC_64) {
        HOOKS_LOG(@"find_segments: bad magic 0x%x (not Mach-O 64)", mh.magic);
        return NO;
    }

    HOOKS_LOG(@"Mach-O: ncmds=%u sizeofcmds=%u cputype=%u filetype=%u",
              mh.ncmds, mh.sizeofcmds, mh.cputype, mh.filetype);

    *out_text_start = 0;
    *out_text_end = 0;
    *out_data_count = 0;
    *out_const_count = 0;
    int64_t slide = 0;
    BOOL has_slide = NO;

    uint64_t cursor = gameBase + sizeof(struct mach_header_64);
    for (uint32_t i = 0; i < mh.ncmds && cursor < gameBase + sizeof(mh) + mh.sizeofcmds; i++) {
        struct load_command lc;
        if (scan_read(task, cursor, &lc, sizeof(lc)) != KERN_SUCCESS) break;

        if (lc.cmd == LC_SEGMENT_64) {
            struct segment_command_64 seg;
            if (scan_read(task, cursor, &seg, sizeof(seg)) != KERN_SUCCESS) break;

            if (!has_slide && strcmp(seg.segname, "__TEXT") == 0) {
                slide = (int64_t)(gameBase - seg.vmaddr);
                has_slide = YES;
                HOOKS_LOG(@"ASLR slide: 0x%llx (base=0x%llx vmaddr=0x%llx)",
                          slide, gameBase, seg.vmaddr);
            }

            uint64_t seg_start = seg.vmaddr + slide;
            uint64_t seg_end = seg_start + seg.vmsize;

            if (strcmp(seg.segname, "__TEXT") == 0) {
                *out_text_start = seg_start;
                *out_text_end = seg_end;
                HOOKS_LOG(@"Segment __TEXT: 0x%llx-0x%llx (vmsize=0x%llx)",
                          seg_start, seg_end, seg.vmsize);
            } else if (strcmp(seg.segname, "__DATA_CONST") == 0 ||
                       strcmp(seg.segname, "__AUTH_CONST") == 0) {
                // 只读常量段: 包含 C++ vtables + GOT entries
                if (*out_const_count < max_const && seg.vmsize > 0) {
                    out_const_starts[*out_const_count] = seg_start;
                    out_const_ends[*out_const_count] = seg_end;
                    HOOKS_LOG(@"Segment %s (const): 0x%llx-0x%llx (vmsize=0x%llx)",
                              seg.segname, seg_start, seg_end, seg.vmsize);
                    (*out_const_count)++;
                }
            } else if (strcmp(seg.segname, "__DATA") == 0 ||
                       strcmp(seg.segname, "__DATA_DIRTY") == 0 ||
                       strcmp(seg.segname, "__BSS") == 0) {
                // 可写数据段: 包含全局变量 (GWorld 指针在此)
                if (*out_data_count < max_data && seg.vmsize > 0) {
                    out_data_starts[*out_data_count] = seg_start;
                    out_data_ends[*out_data_count] = seg_end;
                    HOOKS_LOG(@"Segment %s (writable): 0x%llx-0x%llx (vmsize=0x%llx)",
                              seg.segname, seg_start, seg_end, seg.vmsize);
                    (*out_data_count)++;
                }
            }
        }
        cursor += lc.cmdsize;
    }

    if (*out_text_start == 0) {
        HOOKS_LOG(@"find_segments: __TEXT not found in Mach-O");
        return NO;
    }

    HOOKS_LOG(@"Segments: TEXT=0x%llx-0x%llx (%.1fMB) writable=%d const=%d",
              *out_text_start, *out_text_end,
              (*out_text_end - *out_text_start) / 1048576.0,
              *out_data_count, *out_const_count);
    return YES;
}

// 扫描 DATA 段寻找 GWorld 全局指针
// 原理: GWorld 是一个在 writable DATA/BSS 中的全局变量, 其值指向堆上的 UWorld 对象
// 只扫描可写段 (__DATA, __DATA_DIRTY, __BSS), 跳过只读段 (__DATA_CONST, __AUTH_CONST)
// vtable 验证允许 TEXT + 只读常量段 (iOS 上 C++ vtable 在 __DATA_CONST/__AUTH_CONST)
static uint64_t scan_gworld_in_data(mach_port_t task, uint64_t text_start, uint64_t text_end,
                                     uint64_t *data_starts, uint64_t *data_ends, int data_count,
                                     uint64_t *const_starts, uint64_t *const_ends, int const_count) {
    HOOKS_LOG(@"=== scan_gworld_in_data: %d writable + %d const regions ===", data_count, const_count);

    uint64_t best_addr = 0;
    int best_score = 0;
    int candidates_checked = 0;
    double scan_start = CACurrentMediaTime();
    double deadline = scan_start + 15.0; // 15秒硬限制, 留余量给后台任务

    for (int d = 0; d < data_count; d++) {
        uint64_t seg_start = data_starts[d];
        uint64_t seg_end = data_ends[d];
        size_t seg_size = (size_t)(seg_end - seg_start);

        if (seg_size < 8 || seg_size > 0x10000000) continue;

        HOOKS_LOG(@"Scanning writable region %d: 0x%llx-0x%llx (%.1fMB)",
                  d, seg_start, seg_end, seg_size / 1048576.0);

        size_t buf_size = 0x10000;
        uint64_t *buf = (uint64_t *)malloc(buf_size);
        if (!buf) continue;

        for (uint64_t addr = seg_start; addr + 8 <= seg_end; ) {
            // 超时检查
            if (CACurrentMediaTime() > deadline) {
                HOOKS_LOG(@"DATA scan: deadline reached at offset %zu/%zu (%.1f%%)",
                          (size_t)(addr - seg_start), seg_size,
                          100.0 * (addr - seg_start) / (double)seg_size);
                free(buf);
                goto done;
            }

            size_t chunk = buf_size;
            if (addr + chunk > seg_end) chunk = (size_t)(seg_end - addr);

            if (scan_read(task, addr, buf, chunk) != KERN_SUCCESS) {
                addr += chunk;
                continue;
            }

            size_t count = chunk / 8;
            for (size_t i = 0; i < count; i++) {
                uint64_t candidate = buf[i];
                if (!is_real_heap(candidate, text_start, text_end,
                                  data_starts, data_ends, data_count,
                                  const_starts, const_ends, const_count)) continue;

                // vtable: 允许在 TEXT 或只读常量段 (iOS: __DATA_CONST/__AUTH_CONST)
                uint64_t vtable = 0;
                if (scan_read_uint64(task, candidate, &vtable) != KERN_SUCCESS) continue;
                if (!is_valid_vtable(vtable, text_start, text_end,
                                      const_starts, const_ends, const_count,
                                      data_starts, data_ends, data_count)) continue;

                // PersistentLevel (+0x30) — 必须在堆上
                uint64_t plevel = 0;
                if (scan_read_uint64(task, candidate + 0x30, &plevel) != KERN_SUCCESS) continue;
                if (!is_real_heap(plevel, text_start, text_end,
                                  data_starts, data_ends, data_count,
                                  const_starts, const_ends, const_count)) continue;

                // Actors TArray (+0x98): ptr + count
                uint64_t actors_ptr = 0;
                int32_t actors_count = 0;
                if (scan_read(task, plevel + 0x98, &actors_ptr, sizeof(uint64_t)) != KERN_SUCCESS) continue;
                if (scan_read(task, plevel + 0x98 + 8, &actors_count, sizeof(int32_t)) != KERN_SUCCESS) continue;
                if (!is_real_heap(actors_ptr, text_start, text_end,
                                  data_starts, data_ends, data_count,
                                  const_starts, const_ends, const_count)) continue;
                if (actors_count < 1 || actors_count > 5000) continue;

                candidates_checked++;
                int score = actors_count;
                uint64_t gworld_addr = addr + i * 8;

                if (candidates_checked <= 5 || score > best_score) {
                    HOOKS_LOG(@"GWorld candidate #%d: addr=0x%llx actors=%d",
                              candidates_checked, gworld_addr, actors_count);
                }

                if (score > best_score) {
                    best_score = score;
                    best_addr = gworld_addr;
                }
                if (actors_count > 50) {
                    free(buf);
                    goto done;
                }
            }
            addr += chunk - 7 * 8;
        }

        free(buf);
    }

done:
    HOOKS_LOG(@"GWorld DATA scan: checked %d candidates through validation chain", candidates_checked);
    if (best_addr) {
        uint64_t gworld_val = 0;
        scan_read_uint64(task, best_addr, &gworld_val);
        HOOKS_LOG(@"GWorld found in DATA: addr=0x%llx -> UWorld=0x%llx score=%d",
                  best_addr, gworld_val, best_score);
    } else {
        HOOKS_LOG(@"GWorld not found in DATA segments (%d writable regions scanned)", data_count);
    }
    return best_addr;
}

// ADRP+LDR + MOVZ+MOVK+LDR 扫描
// iOS 上全局变量通过 GOT 访问: ADRP+LDR → GOT entry (__DATA_CONST) → &GWorld (DATA/BSS) → UWorld* (heap)
// 需要追踪两级间接: GOT→global_var→heap_pointer
static uint64_t scan_gworld_text_chunked(mach_port_t task, uint64_t text_start, uint64_t text_end,
                                          uint64_t *data_starts, uint64_t *data_ends, int data_count,
                                          uint64_t *const_starts, uint64_t *const_ends, int const_count) {
    size_t text_size = (size_t)(text_end - text_start);
    HOOKS_LOG(@"=== scan_gworld_text: 0x%llx-0x%llx (%.1fMB) ===",
              text_start, text_end, text_size / 1048576.0);

    if (text_size > 0x1E000000) {
        HOOKS_LOG(@"TEXT too large (%.1fMB), limiting scan to first 120MB", text_size / 1048576.0);
        text_size = 0x7800000;
    }

    size_t buf_size = 0x10000;
    uint32_t *buf = (uint32_t *)malloc(buf_size);
    if (!buf) return 0;

    uint64_t best_addr = 0;
    int best_refs = 0;
    #define RECENT_MAX 1024
    uint64_t recent_addrs[RECENT_MAX] = {0};
    int recent_refs[RECENT_MAX] = {0};
    int recent_idx = 0;
    int pairs_found = 0, got_hits = 0, movz_hits = 0;

    for (uint64_t chunk_start = text_start; chunk_start + 8 <= text_start + text_size; ) {
        uint64_t remaining = text_start + text_size - chunk_start;
        size_t chunk = (remaining > buf_size) ? buf_size : (size_t)remaining;

        if (scan_read(task, chunk_start, buf, chunk) != KERN_SUCCESS) {
            if (remaining <= buf_size) break;
            chunk_start += chunk - 8;
            continue;
        }

        size_t instr_count = chunk / 4;
        for (size_t i = 0; i + 1 < instr_count; i++) {
            uint32_t i0 = buf[i];
            uint32_t i1 = buf[i + 1];
            uint64_t pc = chunk_start + i * 4;

            uint64_t target = 0;
            BOOL from_adrp __attribute__((unused)) = NO, from_movz = NO;

            // 模式 A: ADRP + LDR (传统 UE4 全局变量访问)
            if ((i0 & 0x9F000000) == 0x90000000 && (i1 & 0xFFC00000) == 0xF9400000) {
                uint8_t rd = i0 & 0x1F;
                uint8_t rn = (i1 >> 5) & 0x1F;
                if (rn == rd) {
                    uint64_t page = arm64_decode_adrp(i0, pc);
                    uint64_t off = arm64_decode_ldr_offset(i1);
                    if (page) { target = page + off; from_adrp = YES; }
                }
            }

            // 模式 B: MOVZ + MOVK + LDR (绝对地址构建)
            // MOVZ Xd, #lo16, lsl #0  →  MOVK Xd, #hi16, lsl #16  →  LDR Xt, [Xd]
            // A2: ADRP + ADD + LDR (ADRP Xd,page -> ADD Xd,Xd,#off -> LDR Xt,[Xd])
            if (!target && (i0 & 0x9F000000) == 0x90000000 &&
                (i1 & 0xFF800000) == 0x91000000 && i + 2 < instr_count) {
                uint8_t rd_adrp = i0 & 0x1F;
                uint8_t rn_add = (i1 >> 5) & 0x1F;
                uint8_t rd_add = i1 & 0x1F;
                if (rn_add == rd_adrp && rd_add == rd_adrp) {
                    uint64_t page = arm64_decode_adrp(i0, pc);
                    uint64_t add_off = arm64_decode_add_imm(i1);
                    if (page) {
                        uint32_t i2 = buf[i + 2];
                        if ((i2 & 0xFFC00000) == 0xF9400000) {
                            uint8_t rn_ldr = (i2 >> 5) & 0x1F;
                            if (rn_ldr == rd_add) {
                                uint64_t ldr_off = arm64_decode_ldr_offset(i2);
                                target = page + add_off + ldr_off;
                                from_adrp = YES;
                            }
                        }
                    }
                }
            }

            // B: MOVZ + MOVK + LDR
            if (!target && (i0 & 0xFF800000) == 0xD2800000 && (i1 & 0xFF800000) == 0xF2800000) {
                uint8_t rd_movz = i0 & 0x1F;
                uint8_t rd_movk = i1 & 0x1F;
                if (rd_movz == rd_movk && i + 2 < instr_count) {
                    // Check if next instruction is LDR using same register as base
                    uint32_t i2 = buf[i + 2];
                    if ((i2 & 0xFFC00000) == 0xF9400000) {
                        uint8_t rn_ldr = (i2 >> 5) & 0x1F;
                        if (rn_ldr == rd_movz) {
                            uint64_t val = arm64_decode_movz(i0);
                            val = arm64_decode_movk(i1, val);
                            uint64_t off = arm64_decode_ldr_offset(i2);
                            target = val + off;
                            from_movz = YES;
                        }
                    }
                }
            }

            if (!target) continue;
            pairs_found++;

            // 直接目标: 在可写数据段 → 直接就是 GWorld 指针
            BOOL in_writable = NO;
            for (int d = 0; d < data_count; d++) {
                if (target >= data_starts[d] && target < data_ends[d]) {
                    in_writable = YES;
                    break;
                }
            }

            // GOT 间接: 目标在只读常量段 → 读 GOT entry → 得到全局变量地址 → 再读其值
            BOOL in_const = NO;
            if (!in_writable) {
                for (int d = 0; d < const_count; d++) {
                    if (target >= const_starts[d] && target < const_ends[d]) {
                        in_const = YES;
                        break;
                    }
                }
            }

            if (!in_writable && !in_const) continue;

            uint64_t pointed = 0;

            if (in_writable) {
                // 直接: ADRP+LDR 目标就是 GWorld 全局变量地址
                if (scan_read_uint64(task, target, &pointed) != KERN_SUCCESS) continue;
                if (!is_valid_heap_ptr(pointed)) continue;
            } else {
                // GOT 间接: target = GOT entry → 读 GOT entry 值 → 全局变量地址 → 读全局变量 → 堆指针
                uint64_t got_value = 0;
                if (scan_read_uint64(task, target, &got_value) != KERN_SUCCESS) continue;
                // GOT entry 值应该指向可写数据段 (全局变量地址)
                BOOL got_to_writable = NO;
                for (int d = 0; d < data_count; d++) {
                    if (got_value >= data_starts[d] && got_value < data_ends[d]) {
                        got_to_writable = YES;
                        break;
                    }
                }
                if (!got_to_writable) continue;
                // 读全局变量的值 → 应该指向堆上的 UWorld
                if (scan_read_uint64(task, got_value, &pointed) != KERN_SUCCESS) continue;
                if (!is_valid_heap_ptr(pointed)) continue;
                got_hits++;
            }

            // 引用计数: 相同 target 被多个函数引用 → 更有可能是全局变量
            int refs = 1;
            for (int r = 0; r < RECENT_MAX; r++) {
                if (recent_addrs[r] == target) {
                    refs = ++recent_refs[r];
                    break;
                }
            }
            if (refs == 1) {
                recent_addrs[recent_idx] = target;
                recent_refs[recent_idx] = 1;
                recent_idx = (recent_idx + 1) % RECENT_MAX;
            }

            if (from_movz) movz_hits++;

            if (refs > best_refs) {
                best_refs = refs;
                best_addr = target;
                if (refs >= 5) {
                    HOOKS_LOG(@"GWorld TEXT hit: *0x%llx=0x%llx refs=%d via %s%s",
                              target, pointed, refs,
                              in_const ? "GOT" : "DATA",
                              from_movz ? "+MOVZ" : "");
                }
            }
        }

        if (remaining <= buf_size) break;
        chunk_start += chunk - 8;
    }

    free(buf);

    HOOKS_LOG(@"TEXT scan: %d ADRP+LDR/MOVZ pairs, %d GOT hits, %d MOVZ hits, best_refs=%d",
              pairs_found, got_hits, movz_hits, best_refs);

    if (best_addr && best_refs >= 3) {
        uint64_t gv = 0;
        scan_read_uint64(task, best_addr, &gv);
        HOOKS_LOG(@"GWorld from TEXT scan: addr=0x%llx -> 0x%llx refs=%d", best_addr, gv, best_refs);
    } else {
        HOOKS_LOG(@"GWorld TEXT scan: no candidate with >=3 refs (best=%d, pairs=%d)", best_refs, pairs_found);
    }

    return best_addr;
}

int scan_all_offsets(mach_port_t task, uint64_t gameBase) {
    if (task == MACH_PORT_NULL || gameBase == 0) return -1;

    HOOKS_LOG(@"=== scan_all_offsets: base=0x%llx ===", gameBase);

    // Step 1: 解析 Mach-O 获取精确段范围 (区分可写/只读)
    uint64_t text_start = 0, text_end = 0;
    uint64_t data_starts[8] = {0}, data_ends[8] = {0};
    uint64_t const_starts[4] = {0}, const_ends[4] = {0};
    int data_count = 0, const_count = 0;

    if (!find_segments(task, gameBase, &text_start, &text_end,
                        data_starts, data_ends, &data_count, 8,
                        const_starts, const_ends, &const_count, 4)) {
        HOOKS_LOG(@"Failed to parse Mach-O segments");
        return -1;
    }

    // Step 2: 策略A — 扫描 writable DATA 段寻找 UWorld 指针
    uint64_t gworld_data_addr = scan_gworld_in_data(task, text_start, text_end,
                                                     data_starts, data_ends, data_count,
                                                     const_starts, const_ends, const_count);

    // Step 3: 策略B — ADRP+LDR+MOVZ TEXT 扫描 (含 GOT 间接)
    uint64_t gworld_text_addr = scan_gworld_text_chunked(task, text_start, text_end,
                                                          data_starts, data_ends, data_count,
                                                          const_starts, const_ends, const_count);

    // Step 4: 交叉验证 — 两个策略结果一致才高置信度
    uint64_t gworld_ptr_addr = 0;
    if (gworld_data_addr && gworld_text_addr && gworld_data_addr == gworld_text_addr) {
        // 双策略一致 → 高置信度
        gworld_ptr_addr = gworld_data_addr;
        HOOKS_LOG(@"GWorld cross-validated: DATA=0x%llx TEXT=0x%llx MATCH",
                  gworld_data_addr, gworld_text_addr);
    } else if (gworld_data_addr && gworld_text_addr) {
        // 两个策略找到了不同的地址 — 优先用 TEXT 扫描结果 (ADRP+LDR 模式更可靠)
        HOOKS_LOG(@"GWorld mismatch: DATA=0x%llx TEXT=0x%llx — using TEXT result",
                  gworld_data_addr, gworld_text_addr);
        gworld_ptr_addr = gworld_text_addr;
    } else if (gworld_text_addr) {
        // 只有 TEXT 扫描找到 — ADRP+LDR 模式比纯指针扫描更可靠
        gworld_ptr_addr = gworld_text_addr;
        HOOKS_LOG(@"GWorld from TEXT scan only: 0x%llx", gworld_text_addr);
    } else if (gworld_data_addr) {
        // 只有 DATA 扫描找到 — 保守接受但标记需验证
        gworld_ptr_addr = gworld_data_addr;
        HOOKS_LOG(@"GWorld from DATA scan only (unverified): 0x%llx", gworld_data_addr);
    }

    if (gworld_ptr_addr) {
        g_scanned_offsets.gworld_ptr = gworld_ptr_addr;
        g_scanned_offsets.gworld_found = YES;
    } else {
        HOOKS_LOG(@"GWorld scan failed — will use hardcoded offsets as fallback");
    }

    // Step 5: 读取 GWorld 值验证
    uint64_t gworld = 0;
    if (gworld_ptr_addr) {
        scan_read_uint64(task, gworld_ptr_addr, &gworld);
        HOOKS_LOG(@"GWorld value: 0x%llx (valid=%d)", gworld, is_valid_heap_ptr(gworld));
    }

    // Step 6: 验证 UWorld 结构
    if (gworld && is_valid_heap_ptr(gworld)) {
        uint64_t actorsArray = 0;
        int actorsCount = 0;
        if (get_actors_from_world(task, gworld, &actorsArray, &actorsCount) == 0) {
            HOOKS_LOG(@"Actors: array=0x%llx count=%d", actorsArray, actorsCount);
        } else {
            HOOKS_LOG(@"Failed to read Actors from UWorld — may be stale or wrong GWorld");
        }
    }

    // Step 7: 设置已知的 UE4 引擎偏移 (这些很少变化)
    g_scanned_offsets.uworld_persistent_level  = 0x30;
    g_scanned_offsets.ulevel_actors            = 0x98;
    g_scanned_offsets.aactor_rootcomponent     = 0x188;
    g_scanned_offsets.aactor_mesh              = 0x2D0;
    g_scanned_offsets.aactor_playerstate       = 0x290;
    g_scanned_offsets.uscenecomponent_translation = 0x140;
    g_scanned_offsets.uskinnedmesh_bones       = 0x6F0;
    g_scanned_offsets.uskeletalmesh_componenttoworld = 0x1E0;

    // Step 8: 游戏特定偏移 (硬编码基线, 需每版本验证)
    g_scanned_offsets.aactor_health       = 0x120;
    g_scanned_offsets.aactor_max_health   = 0x124;
    g_scanned_offsets.aactor_team_id      = 0xF0;
    g_scanned_offsets.aactor_pose_state   = 0x418;
    g_scanned_offsets.playercontroller_camera = 0x3D0;
    g_scanned_offsets.player_camera_manager   = 0x330;
    g_scanned_offsets.weapon_recoil       = 0x2B0;
    g_scanned_offsets.weapon_spread       = 0x2C0;

    // Step 9: GName 表扫描 — 寻找 TNameEntryArray chunk 指针数组
    uint64_t gname_ptr = 0;
    {
        // GName 表特征: DATA 中一个指向堆数组的指针, 堆数组中包含多个 chunk 指针
        // 每个 chunk 是 ~0x20000 字节的 FName entry 块
        for (int d = 0; d < data_count && !gname_ptr; d++) {
            uint64_t seg_start = data_starts[d];
            uint64_t seg_end = data_ends[d];
            size_t seg_size = (size_t)(seg_end - seg_start);
            if (seg_size < 8) continue;

            size_t buf_size = 0x10000;
            uint64_t *buf = (uint64_t *)malloc(buf_size);
            if (!buf) continue;

            for (uint64_t addr = seg_start; addr + 8 <= seg_end && !gname_ptr; ) {
                size_t chunk = buf_size;
                if (addr + chunk > seg_end) chunk = (size_t)(seg_end - addr);
                if (scan_read(task, addr, buf, chunk) != KERN_SUCCESS) { addr += chunk; continue; }

                size_t count = chunk / 8;
                for (size_t i = 0; i < count && !gname_ptr; i++) {
                    uint64_t candidate = buf[i];
                    if (!is_real_heap(candidate, text_start, text_end,
                                                  data_starts, data_ends, data_count,
                                                  const_starts, const_ends, const_count)) continue;

                    // 读候选 chunk 指针数组 (最多 8 个 chunk)
                    uint64_t cptrs[8] = {0};
                    if (scan_read(task, candidate, cptrs, sizeof(cptrs)) != KERN_SUCCESS) continue;

                    int valid = 0;
                    uint64_t prev_size = 0;
                    for (int j = 0; j < 8; j++) {
                        if (!cptrs[j]) continue;
                        if (!is_real_heap(cptrs[j], text_start, text_end,
                                                      data_starts, data_ends, data_count,
                                                      const_starts, const_ends, const_count)) break;
                        // 验证: 读 chunk 中第一个 FName entry header
                        uint16_t hdr = 0;
                        if (scan_read(task, cptrs[j], &hdr, sizeof(hdr)) != KERN_SUCCESS) break;
                        uint16_t nlen = hdr >> 6;
                        if (nlen < 1 || nlen > 128) break;
                        // Chunk 大小应该相近 (0x10000-0x20000)
                        if (j > 0 && prev_size > 0) {
                            uint64_t cur_size = cptrs[j] - cptrs[j-1];
                            if (cur_size < 0x8000 || cur_size > 0x40000) break;
                        }
                        if (j > 0) prev_size = cptrs[j] - cptrs[j-1];
                        valid++;
                    }
                    if (valid >= 3) {
                        gname_ptr = addr + i * 8;
                        HOOKS_LOG(@"GName found: addr=0x%llx -> chunks=0x%llx valid=%d",
                                  gname_ptr, candidate, valid);
                    }
                }
                addr += chunk - 7 * 8;
            }
            free(buf);
        }
    }

    if (gname_ptr) {
        uint64_t gname_val = 0;
        scan_read_uint64(task, gname_ptr, &gname_val);
        g_scanned_offsets.gname_base = gname_val;
        g_scanned_offsets.gname_found = YES;
        HOOKS_LOG(@"GName base: 0x%llx", gname_val);
    } else {
        HOOKS_LOG(@"GName not found — FName resolution will use hardcoded offset");
    }

    g_scanned_offsets.scanned = YES;
    HOOKS_LOG(@"=== scan_all_offsets complete (gworld=%d gname=%d) ===",
              g_scanned_offsets.gworld_found, g_scanned_offsets.gname_found);

    return g_scanned_offsets.gworld_found ? 0 : -2;
}
