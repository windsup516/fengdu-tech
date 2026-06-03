# DeltaForce TrollKit — 完整差距分析 (Amazon2 vs 太阳神 vs 我们)

> 分析日期: 2026-06-03
> 对比对象: Amazon2 (Stocks 20.9MB) / 太阳神 pofi (25.4MB) / 我们 (<1MB)

---

## 1. 二进制体积对比

| 文件 | Amazon2 | 太阳神 | 我们 |
|------|---------|--------|------|
| 主二进制 | Stocks 20.9MB | pofi 25.4MB | Stocks ~500KB (源码编译) |
| libjailbreak.dylib | 708KB | 708KB | 708KB (同) |
| libchoma.dylib | 388KB | 388KB | 388KB (同) |
| DFOverlay.dylib | ❌ 不存在 | ❌ 不存在 | ~1.3MB (自建) |
| **总 .tipa** | **~16.2MB** | **~17.8MB** | **~1.2MB 含 DFOverlay** |

**结论**: 我们的二进制比参考小 40 倍。不是缺 libjailbreak/libchoma，而是主二进制本身严重不完整。

---

## 2. 函数 & 字符串统计

| 指标 | Amazon2 | 太阳神 | 我们 |
|------|---------|--------|------|
| 总函数数 | 5,237 | 48,072 | ~200 (估算) |
| 有名函数 | 876 | 5,657 | ~50 |
| 总字符串 | 104,038 | 120,241 | ~1,000 |
| 入口点 | DecryptSpace.xxx | DecryptSpace.xxx | main() |

太阳神函数数是 Amazon2 的 9 倍（48K vs 5K），部分是因为太阳神 IDA 分析更完整，但也说明其代码规模更大。

---

## 3. 逐系统差距分析

### 3.1 字符串加密引擎 ❌ 完全缺失

**参考实现**: splitmix64 PRNG + NEON SIMD XOR，编译时加密所有敏感字符串

```
加密流程:
编译时 → splitmix64 流加密 → 密文字节数组嵌入 .const 段
运行时 → DecryptSpace(seed) → splitmix64_next() XOR → 明文 NSString
```

**影响的字符串类型**:
- ObjC 选择器名称 (100+ 个)
- 类名
- 游戏数据结构名称
- 服务器 URL
- 反作弊相关字符串
- 错误消息
- 日志消息

**我们的状态**: [CryptoUtils.m](src/CryptoUtils.m) 有 `splitmix64_next` 和 `DecryptBytes`，但实际代码中几乎没有调用。所有字符串都是明文。

**影响**: 反作弊可以轻易通过 `strings Stocks | grep` 发现所有敏感内容。加密后可增加约 2-3MB 二进制体积（密文数据 + 解密 stub）。

---

### 3.2 内核 Logo 动画视图 ❌ 完全缺失

**类**: `KernelLogoView` (Amazon2 和 太阳神都有)

**组成**:
- `CAShapeLayer *dotLayer` — 中心光点
- `CAShapeLayer *dotGlowLayer` — 光点辉光
- `CAShapeLayer *orbitArc` — 轨道弧线
- `CAShapeLayer *innerCore` — 内核
- `CAShapeLayer *midRing` — 中环
- `CAShapeLayer *outerRing` — 外环
- `CAShapeLayer *crossLayer` — 十字线
- `CAShapeLayer *bullet` — 弹头标示
- `CAShapeLayer *innerStroke` — 内描边
- `CAShapeLayer *gridLayer` — 网格
- `NSMutableArray *glowBlobs` — 辉光斑点
- `CADisplayLink *displayLink` — 60fps 动画
- `CABasicAnimation` + `CAKeyframeAnimation` — 多层动画

**我们的状态**: 完全没有这个类。LoginViewController 里只有一个简单的按钮和文本框。

**需要创建**: `src/KernelLogoView.m` — 完整动画 Logo 组件

---

### 3.3 GlassCard / StatusPill / InfoRow / GlowBlob ❌ 缺失

**GlassCard**: 毛玻璃卡片组件（LoginViewController 的状态卡片容器）
**StatusPill**: 状态指示器（显示设备/网络/注入状态）
**InfoRow**: 信息行组件
**GlowBlob**: 辉光斑点动画元素

这些是参考应用的 LoginViewController 中使用的自定义 UI 组件，增加视觉完整性和用户体验。

---

### 3.4 Metal 封装层 ❌ 缺失

**参考有的类**:
- `MetalBuffer` — Metal 缓冲区封装
- `MetalTexture` — Metal 纹理封装
- `MetalContext` — Metal 上下文管理
- `FramebufferDescriptor` — 帧缓冲配置

**我们的实现**: 直接使用 ImGui 的 `imgui_impl_metal.mm`，没有自己的 Metal 封装。参考应用在 ImGui 之外还有自定义 Metal 渲染（ESP 线条/方框等不需要 ImGui 管线）。

---

### 3.5 双进程架构 ❌ 缺失 (太阳神特有)

太阳神使用双 UIApplication 架构:

```
MainApplication (com.rn.apollo)
├── LoginViewController (卡密 + 服务器验证)
├── MainViewController (部署管理)
└── UIWindow (标准)

HUDMainApplication (独立进程)
├── HUDRootViewController (ImGui + Metal)
├── TouchMainWindow (HID 事件)
└── HUDMainWindow (SBS 托管 + 高窗口层级)
```

**优势**:
- 覆盖层崩溃不影响主进程
- 反作弊检测主进程时隔离覆盖层
- 持久化安装 (persist install to /var/mobile/Documents)

**我们的实现**: 单进程，HUDController 直接创建额外窗口。

---

### 3.6 SBS 窗口托管 ❌ 不完整

**参考实现** (太阳神):
```objc
// 使用 NSInvocation 动态调用，参数类型简化
SEL sel = NSSelectorFromString(@"registerWindowWithContextID:atLevel:");
NSMethodSignature *sig = [hostingController methodSignatureForSelector:sel];
NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
[inv setTarget:hostingController];
[inv setSelector:sel];
[inv setArgument:&contextId atIndex:2];  // unsigned int
[inv setArgument:&level atIndex:3];      // double
[inv invoke];
```

**我们的实现**: [HUDController.m](src/HUDController.m) 直接调用选择器，参数类型可能不完全匹配导致 contextId=0 问题。

---

### 3.7 服务器通信 & 卡密验证 ❌ 严重缺失

**参考有而我们没有的**:

| 功能 | Amazon2 | 太阳神 | 我们 |
|------|---------|--------|------|
| 网络卡密验证 | ✅ | ✅ | ❌ (本地硬编码) |
| 多服务器选择 | ❌ | ✅ | ❌ |
| RSA 加密通信 | ❌ | ✅ | ❌ |
| AES 数据加密 | ❌ | ✅ | ❌ |
| SHA256 签名 | ❌ | ✅ | ❌ |
| MD5 校验 | ❌ | ✅ | ❌ |
| 部署安装管理 | ❌ | ✅ | ❌ |
| 持久化安装 | ❌ | ✅ | ❌ |

**太阳神加密导入**:
- `SecKeyEncrypt` — RSA 公钥加密
- `kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA256` — RSA 签名
- `CCCrypt` — AES 加密/解密
- `CC_SHA256_Init/Update/Final` — SHA256
- `CC_MD5` — MD5
- `NSMutableURLRequest` + `NSURLSession` — HTTP 通信

**我们的状态**: LoginViewController 用本地密钥比对，无网络通信能力。

---

### 3.8 设备指纹 ❌ 缺失

**类**: `LFSenderIDMonitor`

参考应用具有设备唯一标识监控能力，用于:
- 设备绑定验证
- 反滥用检测
- 服务器端设备追踪

---

### 3.9 方向/旋转管理 ❌ 缺失

**类**: `FBSOrientationObserver`

FrontBoard Services 方向观察者，用于跟踪设备旋转状态，确保覆盖层在横竖屏切换时正确布局。我们用的是基本 UIScreen bounds。

---

### 3.10 武器系统 ❌ 过于简陋

**参考**: 包含完整游戏事件项数据 (EventItem_WeaponDealerTrustTest_Name, EventItem_WeaponMPProgressTest_Name 等)，大量武器皮肤名称 (MS24SkinWeapon-Epic1/Legendary/epic2)。

**我们**: [WeaponConfig.m](src/WeaponConfig.m) 只有 12 种基础武器预设，无皮肤数据。

---

### 3.11 GameHooks ❌ 功能不完整

**参考内存操作**:
- `arm64_kcall_init` — 内核调用初始化
- `kmap` / `kread64` / `kread_ptr` / `kreadbuf` — 内核内存读写
- `physread32/64` / `physreadbuf` / `physwritebuf` — 物理内存读写
- `phystokv` / `vtophys` — 地址转换
- `proc_find` / `proc_task` — 进程查找
- `pmap_lookup_in_loaded_trust_caches_internal` — AMFI 绕过

**我们**: [GameHooks.mm](src/GameHooks.mm) 只有基本的 Mach VM 读写。

---

### 3.12 libchoma 功能利用 ❌ 未充分使用

参考应用导入了大量 libchoma 函数用于内存扫描:

```
arm64_gen_mov_reg / arm64_gen_mov_imm / arm64_gen_b_l  → 代码生成
arm64_dec_ldr_imm / arm64_dec_str_imm / arm64_dec_adr_p → 指令解码
pfmetric_pattern_init / pfmetric_run / pfmetric_run_in_range → 模式匹配
pfmetric_string_init / pfmetric_xref_init → 字符串/交叉引用搜索
pfsec_init_from_macho / pfsec_read32 / pfsec_read64 → 段读取
pfsec_find_function_start / pfsec_find_next_inst → 函数边界查找
pfsec_resolve_adrp_ldr_str_add_reference_auto → 指针解析
```

我们只用 libchoma 做基本代码生成 (`encode_mov64`)。没有用它的模式匹配和段解析功能来做游戏偏移自动发现。

---

### 3.13 libarchive/compression ❌ 缺失

**参考导入**: `libarchive.2.dylib`, `libcompression.dylib` (`compression_decode_buffer`)

用于解压内嵌资源或从服务器下载的配置数据。

---

## 4. 优先级排序 (按重要性)

### P0 — 阻塞功能
1. **字符串加密引擎** — 安全基础，保护所有敏感字符串
2. **服务器卡密验证** — 分发控制，防止未授权使用
3. **SBS 窗口托管修复** — HUD 后台存活 (当前 contextId=0 bug)

### P1 — 核心功能缺失
4. **Dylib 注入完整实现** — 游戏中 Metal overlay 渲染
5. **GameHooks 扩展** — 更多游戏内存偏移 + 自动化扫描
6. **Metal 封装层** — ESP 渲染性能优化
7. **武器系统扩展** — 完整游戏武器数据

### P2 — 体验增强
8. **KernelLogoView** — Logo 动画
9. **GlassCard / StatusPill** — UI 组件
10. **FBSOrientationObserver** — 旋转适配
11. **libarchive 资源解压** — 内嵌资源加载

### P3 — 高级功能
12. **双进程架构** — 覆盖层隔离
13. **设备指纹** — 反滥用
14. **持久化安装** — 自动恢复

---

## 5. 文件映射表 (Amazon2 类 ↔ 我们的文件)

| Amazon2 类 | 我们的文件 | 状态 |
|------------|-----------|------|
| AppDelegate | [AppDelegate.m](src/AppDelegate.m) | ✅ 存在，功能不足 |
| AppSceneDelegate | [SceneDelegate.m](src/SceneDelegate.m) | ✅ 存在 |
| LoginViewController | [LoginViewController.m](src/LoginViewController.m) | ⚠️ 存在但缺少 UI 组件 |
| AppViewController | [AppViewController.m](src/AppViewController.m) | ⚠️ 存在但功能简化 |
| HUDController | [HUDController.m](src/HUDController.m) | ⚠️ SBS 托管有 bug |
| HUDMainWindow | [HUDMainWindow.m](src/HUDMainWindow.m) | ✅ 存在 |
| HUDRootViewController | [HUDRootViewController.mm](src/HUDRootViewController.mm) | ✅ 存在 |
| TouchMainWindow | [TouchMainWindow.m](src/TouchMainWindow.m) | ✅ 存在 |
| TouchViewController | [TouchViewController.m](src/TouchViewController.m) | ✅ 存在 |
| HIDEventManager | [HIDEventManager.m](src/HIDEventManager.m) | ✅ 存在 |
| GameHooks | [GameHooks.mm](src/GameHooks.mm) | ⚠️ 功能不完整 |
| ESPOverlay | [ESPOverlay.mm](src/ESPOverlay.mm) | ✅ 存在 |
| MetalRenderer | [MetalRenderer.mm](src/MetalRenderer.mm) | ✅ 存在 |
| ImGuiAdapter | [ImGuiAdapter.mm](src/ImGuiAdapter.mm) | ✅ 存在 |
| WeaponConfig | [WeaponConfig.m](src/WeaponConfig.m) | ⚠️ 过于简陋 |
| CryptoUtils | [CryptoUtils.m](src/CryptoUtils.m) | ⚠️ 算法有但未使用 |
| DylibInjector | [DylibInjector.m](src/DylibInjector.m) | ✅ 存在 (自建) |
| DFOverlayController | [DFOverlayController.mm](dylib/DFOverlayController.mm) | ✅ 自建 (注入用) |
| **KernelLogoView** | ❌ 不存在 | 🔴 缺失 |
| **GlassCard** | ❌ 不存在 | 🔴 缺失 |
| **StatusPill** | ❌ 不存在 | 🔴 缺失 |
| **InfoRow** | ❌ 不存在 | 🔴 缺失 |
| **GlowBlob** | ❌ 不存在 | 🔴 缺失 |
| **MetalBuffer** | ❌ 不存在 | 🔴 缺失 |
| **MetalTexture** | ❌ 不存在 | 🔴 缺失 |
| **MetalContext** | ❌ 不存在 | 🔴 缺失 |
| **FramebufferDescriptor** | ❌ 不存在 | 🔴 缺失 |
| **LFSenderIDMonitor** | ❌ 不存在 | 🔴 缺失 |
| **FBSOrientationObserver** | ❌ 不存在 | 🔴 缺失 |

---

## 6. 太阳神独有的高级特性

以下特性只在太阳神中，Amazon2 也没有:

| 特性 | 描述 |
|------|------|
| 双 UIApplication | 主应用 + HUD 独立进程 |
| RSA 加密通信 | SecKeyEncrypt |
| AES 加密 | CCCrypt |
| SHA256/MD5 | 数据完整性 |
| BKSHIDEventRegisterEventCallback | BackBoard 级别 HID，比 IOHID 更底层 |
| NSPipe | 进程间通信 |
| NSRegularExpression | 字符串解析 |
| 持久化安装到 /var/mobile/Documents | 自动恢复 |
| 多服务器支持 | 服务器选择功能 |

---

## 7. 二进制体积来源估算

Amazon2 20.9MB 体积分解:

| 组件 | 估算体积 | 说明 |
|------|---------|------|
| ImGui (imgui/imgui_draw/imgui_widgets/imgui_tables/imgui_impl_metal) | ~1.5MB | C++ 模板展开后体积大 |
| String encryption data section | ~3-5MB | 104K 个字符串每个平均 40-60 字节加密存储 |
| DecryptSpace stub code | ~2-3MB | 5K+ 函数每个都有解密 stub |
| Custom UI components (Logo/GlassCard/etc.) | ~1-2MB | CAShapeLayer + 动画代码 |
| Metal wrappers | ~0.5MB | MetalBuffer/Texture/Context |
| ESP/Aimbot/NoRecoil/NoSpread logic | ~1-2MB | 游戏特定计算 |
| Server communication | ~0.5MB | HTTP + JSON |
| libarchive/compression | ~0.5MB | 资源解压 |
| Other ObjC classes | ~2-3MB | ViewControllers + Window management |
| Debug info / symbols | ~3-5MB | 可能包含 DWARF 调试信息 |

---

## 8. 下一步行动计划

### 立即执行 (P0)
1. 实现完整 splitmix64 + NEON XOR 字符串加密，加密所有现有字符串
2. 添加服务器卡密验证 (NSURLSession + JSON API)
3. 修复 SBS 窗口托管 contextId=0 问题

### 短期 (P1)
4. 创建 KernelLogoView.m
5. 创建 GlassCard / StatusPill 组件
6. 创建 Metal 封装层 (MetalBuffer/Texture/Context)
7. 扩展 WeaponConfig 为完整武器数据库
8. 使用 libchoma pfmetric/pfsec 做自动偏移扫描

### 中期 (P2)
9. 考虑双进程架构
10. 添加设备指纹
11. 持久化安装支持
