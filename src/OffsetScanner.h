// OffsetScanner.h — UE4 GWorld/GName 签名扫描 + 指针解密
// 基于红狼/Amazon/太阳神逆向 + IDA Pro 分析
//
// 核心功能:
//   1. ARM64 ADRP+LDR 指令解码 → 提取全局指针地址
//   2. GWorld 签名扫描 (TEXT段搜索 ADRP+LDR 引用模式)
//   3. GName 表定位 + xorString 解密 (红狼 9-variant XOR)
//   4. UWorld→PersistentLevel→Actors TArray 实体迭代
//   5. 运行时偏移验证 (检查读出的值是否合理)

#ifndef OffsetScanner_h
#define OffsetScanner_h

#import <Foundation/Foundation.h>
#import <mach/mach.h>
#import <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// === ARM64 指令解码 ===

// ADRP: 形成 4KB 页对齐的 PC-relative 地址
// 编码: [31]=1, [30:29]=immlo, [28:24]=10000, [23:5]=immhi, [4:0]=Rd
uint64_t arm64_decode_adrp(uint32_t instr, uint64_t pc);

// LDR (unsigned offset): 从基址 + 偏移加载
// 编码: 11 111 0 01 01 imm12 Rn Rt
// size=11(64bit), V=0(integer), opc=01(load)
uint64_t arm64_decode_ldr_offset(uint32_t instr);

// ADD (immediate): 常用于指针修正
uint64_t arm64_decode_add_imm(uint32_t instr);

// MOVZ/MOVK: 用于构建64位立即数
uint64_t arm64_decode_movz(uint32_t instr);
uint64_t arm64_decode_movk(uint32_t instr, uint64_t existing);

// === 内存扫描 ===

// AOB (Array of Bytes) 扫描: 在指定内存范围搜索字节模式
// pattern: 字节数组, mask: 0xFF=必须匹配 0x00=跳过(通配符)
// 返回匹配地址, 0=未找到
uint64_t aob_scan(mach_port_t task, uint64_t start, uint64_t end,
                  const uint8_t *pattern, const uint8_t *mask, size_t len);

// === GWorld 扫描 ===

// GWorld 扫描策略 (内部实现, 由 scan_all_offsets 统一调度):
//   策略A: 扫描 DATA/BSS 段寻找 UWorld 指针 (验证 PersistentLevel→Actors 链)
//   策略B: ADRP+LDR 指令对扫描 TEXT 段前 120MB (引用计数>=3 为候选)
// 两种策略自动 fallback, 结果一致时置信度最高

// === GName 系统 ===

// xorString 解密 (红狼 9-variant XOR, 完全还原 sub_1000DF968)
// key: 16位加密密钥 (GName 表项)
// 返回解密后的字符串
NSString *decrypt_gname_string(mach_port_t task, uint64_t nameEntryAddr, uint16_t key, size_t length);

// 通过 FName Index 解析名字
// GName 表基址从模块基址 + 偏移定位
NSString *resolve_fname(mach_port_t task, uint64_t gameBase, uint32_t fnameIndex);

// === UWorld 遍历 ===

// 从 UWorld 获取 Actors 数组
// UWorld → +0x30 PersistentLevel → +0x98 Actors (TArray<AActor*>)
// 返回: Actor 数量, -1=失败
int get_actors_from_world(mach_port_t task, uint64_t gworld,
                          uint64_t *out_actors_array, int *out_actor_count);

// 获取实体类名 (通过 FName Index)
NSString *get_entity_class_name(mach_port_t task, uint64_t gameBase, uint64_t entity);

// === 偏移结构 ===

// 运行时扫描结果
typedef struct {
    // 全局对象 (runtime scanned)
    uint64_t gworld_ptr;        // GWorld 全局指针地址
    uint64_t gname_base;        // GName 表基址 (解析后)

    // UE4 引擎偏移 (固定, 跨版本很少变)
    uint64_t uworld_persistent_level;   // UWorld → PersistentLevel (通常 0x30)
    uint64_t ulevel_actors;             // ULevel → Actors TArray (通常 0x98)
    uint64_t aactor_rootcomponent;      // AActor → RootComponent
    uint64_t aactor_mesh;               // AActor → USkeletalMeshComponent
    uint64_t aactor_playerstate;        // AActor → PlayerState

    // 组件偏移
    uint64_t uscenecomponent_translation;  // ComponentToWorld 位移
    uint64_t uskinnedmesh_bones;           // 骨骼数组
    uint64_t uskeletalmesh_componenttoworld;

    // 角色属性偏移 (游戏特定, 需每版本验证)
    uint64_t aactor_health;
    uint64_t aactor_max_health;
    uint64_t aactor_team_id;
    uint64_t aactor_pose_state;     // 姿势 (站立/蹲下/趴下/倒地)
    uint64_t playercontroller_camera;
    uint64_t player_camera_manager;

    // 武器偏移
    uint64_t weapon_recoil;
    uint64_t weapon_spread;

    // 标记
    BOOL scanned;
    BOOL gworld_found;
    BOOL gname_found;
} ScannedOffsets;

extern ScannedOffsets g_scanned_offsets;

// === 主扫描入口 ===
int scan_all_offsets(mach_port_t task, uint64_t gameBase);

#ifdef __cplusplus
}
#endif

#endif /* OffsetScanner_h */
