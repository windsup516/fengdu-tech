# DeltaForce TrollKit v2.1 — 技术文档

## 📐 整体架构

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Star.app (TrollStore)                        │
│                                                                      │
│  主线程                             后台线程                           │
│  ┌─────────────────────┐    ┌──────────────────────────┐            │
│  │ AppDelegate          │    │ XPF Kernel Framework      │            │
│  │  ├─ XPF 初始化       │    │  ├─ 内核符号解析          │            │
│  │  ├─ LoginViewController │  │  ├─ kcall 原语           │            │
│  │  ├─ AppViewController │    │  ├─ 物理内存 r/w         │            │
│  │  └─ HUDController    │    │  └─ PPL 绕过             │            │
│  └─────────────────────┘    └──────────────────────────┘            │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │                  HUD 覆盖层系统                                │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐   │   │
│  │  │ HUDMainWindow │  │TouchMainWindow│  │ SBSAccessibility │   │   │
│  │  │ (菜单UI)      │  │ (触摸捕获)    │  │ WindowHosting    │   │   │
│  │  │ Level:10M     │  │ Level:10.1M  │  │ (防检测托管)     │   │   │
│  │  └──────┬───────┘  └──────┬───────┘  └──────────────────┘   │   │
│  │         │                 │                                  │   │
│  │         └────────┬────────┘                                  │   │
│  │                  ▼                                           │   │
│  │         ┌──────────────────┐                                 │   │
│  │         │  Metal + ImGui   │  ← 60fps CADisplayLink          │   │
│  │         │  (ESP/菜单渲染)   │                                 │   │
│  │         └──────────────────┘                                 │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │                GameHooks — 游戏内存操作                        │   │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌────────────┐   │   │
│  │  │ 特征码扫描 │→ │ 内存补丁  │→ │ 数据读取  │→ │ 功能生效   │   │   │
│  │  │(模式匹配) │  │(NOP/JMP) │  │(实体/位置)│  │(NoRecoil) │   │   │
│  │  └──────────┘  └──────────┘  └──────────┘  └────────────┘   │   │
│  └──────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 一、入口层 — `main.m` + `AppDelegate`

### 功能
应用启动的入口点，负责初始化所有子系统并按顺序启动。

### 启动流程

```
main()
  └─ UIApplicationMain()
       └─ AppDelegate::application:didFinishLaunchingWithOptions:
            ├─ [1] xpf_initialize_kernel()     ← 初始化内核接口
            │      ├─ task_for_pid(0) 获取 kernel_task
            │      ├─ 获取 kernel_slide / kernel_base
            │      └─ 检测 PPL 状态 (iOS 16+)
            │
            ├─ [2] jb_init()                   ← 初始化 jailbreak 服务
            │      ├─ 内存页重映射
            │      └─ 沙箱绕过准备
            │
            ├─ [3] 创建 UIWindow               ← 主窗口
            │      └─ windowLevel = UIWindowLevelAlert
            │
            ├─ [4] 显示 LoginViewController    ← 授权界面
            │      └─ 等待 onAuthorized 回调
            │
            ├─ [5] 后台: xpf_resolve_all_symbols()  ← 异步解析内核符号
            │      └─ xpf_setup_kcall_primitive()   ← 设置 kcall
            │
            └─ [6] 授权成功后 → showMainMenu()
                   ├─ AppViewController (武器选择/状态)
                   └─ HUDController (作弊覆盖层)
```

### 关键代码

```objc
// 步骤1: XPF 内核初始化
int xpfResult = xpf_initialize_kernel();
if (xpfResult == 0) {
    // 内核原语可用 → 完整功能模式
} else {
    // 回退到 userspace-only 模式
}

// 步骤5: 异步解析内核符号
dispatch_async(backgroundQueue, ^{
    xpf_resolve_all_symbols();
    xpf_setup_kcall_primitive();
});
```

---

## 二、XPF 内核框架 — `XPFKernelInterface.c`

### 核心功能
基于反编译 `xpf_common_init` / `xpf_ppl_init` / `xpf_non_ppl_init` 的完整内核利用框架。

### 2.1 内核符号表

定义了 **87 个内核符号**，分为 4 类：

| 类型 | 符号数 | 用途 |
|------|--------|------|
| `type=0` — 符号 | 50+ | 内核函数/变量地址 |
| `type=1` — 常量 | 5 | 内核常量值 |
| `type=2` — 结构体偏移 | 3 | task/vm_map/proc 结构体 |
| `type=3` — Gadgets | 2 | kcall_return, str_x8_x0 |

**关键符号分组：**

```
AMFI/沙箱:
  └─ launch_env_logging, developer_mode_status, nchashtbl, nchashmask
  
内存管理:
  └─ kalloc_data_external, kfree_data_external, phystokv, ptov_table
  └─ vm_page_array_beginning_addr, vm_page_array_ending_addr

进程/任务:
  └─ allproc, arm_vm_init, pmap_bootstrap

PPL (iOS 16+):
  └─ ppl_enter, ppl_bootstrap_dispatch, ppl_handler_table
  └─ pmap_enter_options_ppl, pmap_remove_options_ppl
  └─ ppl_trust_cache_rt, pmap_query_trust_cache_safe

IOKit/PerfMon:
  └─ perfmon_dev_open, perfmon_devices, cdevsw, vn_kqfilter

Gadgets:
  └─ kcall_return, exception_return, str_x8_x0
```

### 2.2 kcall 原语

在内核中执行任意函数的核心机制。

```
xpf_kcall(func, args, arg_count, result)
  ├─ [1] 获取当前线程的 machine_contextData
  ├─ [2] 备份 CPU 寄存器状态 (X0-X30, PC)
  ├─ [3] 设置 X0-X7 = 调用参数
  ├─ [4] 设置 LR = kcall_return_gadget
  ├─ [5] 设置 PC = 目标函数地址
  ├─ [6] 触发异常返回 → CPU 切换到内核上下文
  ├─ [7] 函数执行完毕后通过 gadget 返回
  └─ [8] 读取 X0 作为返回值
```

### 2.3 物理内存操作

```
xpf_phys_read(phys_addr, buffer, size)
  └─ phystokv(phys_addr) → 虚拟地址 → kern_reading()
  
xpf_phys_write(phys_addr, buffer, size)
  └─ phystokv(phys_addr) → 虚拟地址 → kern_writing()
  
xpf_phys_to_virt(phys_addr)
  ├─ 方法1: kcall(phystokv, phys_addr)
  └─ 方法2: ptov_table + phys_addr - gPhysBase
```

### 2.4 进程操作

```
xpf_find_process("Star")
  └─ 遍历 allproc 链表 → 匹配 p_comm (偏移 0x268)
  
xpf_sandbox_escape(proc)
  └─ mac_label_set(proc, slot=0, label=NULL)
  └─ 清空 syscall_filter_mask
  
xpf_bypass_developer_mode()
  └─ 写 developer_mode_enabled = 1
```

### 2.5 PPL Bypass (iOS 16+)

苹果在 iOS 16 引入了 Page Protection Layer (PPL)，本框架的绕过方式：

```
xpf_ppl_bypass_init()
  ├─ [1] 获取 ppl_bootstrap_dispatch 函数地址
  ├─ [2] 通过 ppl_enter 进入 PPL 上下文
  ├─ [3] 注册自定义 PPL handler
  ├─ [4] 修改 trust cache → 允许未签名代码执行
  └─ [5] 修改页表 PTE → 添加可写权限
```

---

## 三、授权系统 — `LoginViewController.m`

### 功能
用户输入32位授权密钥，验证后解锁作弊功能。

### 当前状态 (测试模式)

**已绕过服务器验证**，输入任意32位字符即可进入。

```
用户输入 32 位 key
  ├─ 长度校验 (必须 == 32)
  ├─ 显示 "Checking..." (UI 动画)
  └─ 直接调用 bypassAuthorize()
       ├─ 保存 key 到钥匙串
       └─ 触发 onAuthorized 回调 → 进入主菜单
```

### 字符串加密引擎 — `CryptoUtils.m`

所有 UI 文本在编译时加密，运行时通过 **splitmix64 + NEON XOR** 解密。

```
splitmix64 算法:
  z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9
  z = (z ^ (z >> 27)) * 0x94D049BB133111EB
  return z ^ (z >> 31)

解密过程:
  encrypted_bytes[i] XOR (splitmix64_next(&state) >> 31)
  
NEON 加速 (16字节并行):
  veorq_s8(encrypted, xor_key1, xor_key2)
```

已加密的字符串示例：
- `byte_10013838F` → "Checking..."
- `byte_100138372` → "Invalid key format"
- `byte_10013839F` → "Welcome, %@"
- `byte_100138324` → "License key loaded"

### 钥匙串存储

```objc
服务名: "com.star.auth"
账户名: "license_key"
访问权限: 仅本机解锁后可用
```

---

## 四、主菜单 — `AppViewController.m`

### 功能
武器选择 + 设备信息展示 + 激活作弊按钮。

### 4.1 武器选择器

12 种武器预设，每种有独立参数：

| 武器 | 后坐力X | 后坐力Y | 自瞄速度 | 自瞄FOV |
|------|---------|---------|---------|---------|
| AKM | 0.8 | 0.6 | 0.9 | 6.0° |
| M4A1 | 0.5 | 0.3 | 0.9 | 5.0° |
| K416 | 0.5 | 0.4 | 0.9 | 5.0° |
| AUG | 0.4 | 0.3 | 0.8 | 4.0° |
| M16A4 | 0.5 | 0.3 | 0.8 | 4.5° |
| QBZ95-1 | 0.6 | 0.4 | 0.8 | 5.0° |
| QBZ-17 | 0.7 | 0.5 | 0.8 | 5.5° |
| AKS-74U | 0.9 | 0.7 | 0.9 | 6.5° |
| ASH-12 | 1.0 | 0.8 | 0.7 | 7.0° |
| M7 | 0.7 | 0.5 | 0.9 | 5.5° |
| SC17 | 0.6 | 0.5 | 0.9 | 5.0° |
| 97M | 0.7 | 0.5 | 0.8 | 5.5° |

武器切换时发送 `WeaponConfigChanged` 通知 → `GameHooks` 接收并应用参数。

### 4.2 设备信息卡片

通过 XPF 内核接口读取游戏内存，每 0.5 秒更新一次：

```
├─ FPS:      从 0x100EE9000 读取
├─ Ping:     从 0x100EEA000 读取
├─ Players:  由 ESP 模块更新
├─ Weapon:   从 weapon_offset 读取字符串
└─ State:    ACTIVE / IDLE
```

### 4.3 激活按钮

- **按下时**: `HIDEventManager` 发送鼠标按下事件
- **抬起时**: 切换 HUD 作弊菜单的显示/隐藏

---

## 五、HUD 覆盖层系统

### 5.1 双窗口架构

这是整个作弊的核心创新 — 使用两个独立的 UIWindow 叠加在游戏之上：

```
Window Level 层级:
  Normal (0)        → 游戏主窗口
  StatusBar (1000)  → 系统状态栏
  Alert (2000)      → 系统警告
  HUDMainWindow (10000010)   → 作弊菜单 (Metal渲染)
  TouchMainWindow (10000011) → 触摸捕获层
```

### 5.2 HUDMainWindow — 菜单渲染层

```
HUDController
  └─ createWindowsOnScene:
       ├─ [1] HUDRootViewController (视图控制器)
       │      ├─ UITextField (持有 CAMetalLayer)
       │      └─ CAMetalLayer (Metal 渲染)
       │
       ├─ [2] CADisplayLink (60fps 帧循环)
       │      └─ renderFrame:
       │           ├─ ImGui::NewFrame()
       │           ├─ 渲染作弊菜单
       │           ├─ ImGui::Render()
       │           └─ Metal 命令提交
       │
       └─ [3] SBSAccessibilityWindowHostingController
              └─ 隐藏窗口存在 (防检测)
```

**防检测技巧:**
- `_isSystemWindow = YES` — 伪装成系统窗口
- `_isSecure = YES` — 防止截图检测
- `_ignoresHitTest = YES` — 忽略命中测试
- `UITextField.secureTextEntry = YES` — 防止屏幕捕获

### 5.3 TouchMainWindow — 触摸捕获层

```
TouchMainWindow
  ├─ 定时器: 每 1/60 秒轮询 HID 事件
  ├─ IOHIDEventSystemClient 注册回调
  │
  └─ timerFired:
       ├─ 获取 IOHIDEvent
       ├─ 读取 senderID (区分游戏/作弊触摸)
       ├─ 检查触摸坐标是否在菜单区域
       └─ 如果在菜单区域 → 拦截事件 (setSenderID=0)
```

### 5.4 HIDEventManager — IOHID 事件管理

```
registerEventCallback:
  ├─ IOHIDEventSystemClientCreate()
  ├─ IOHIDEventSystemClientRegisterEventCallback()
  └─ IOHIDEventSystemClientScheduleWithRunLoop()

事件注入:
  sendTouchAtPoint:phase:
    └─ IOHIDEventCreateDigitizerEvent()
        └─ 设置 senderID = 0xDEADBEEFCAFE
```

### 5.5 Metal + ImGui 渲染

```
HUDRootViewController 60fps 渲染循环:
  ├─ CADisplayLink 触发 renderFrame:
  ├─ nextDrawable → 获取 Metal 可绘制对象
  ├─ ImGui::NewFrame()
  ├─ renderCheatMenu:
  │    ├─ AIM Tab:   自瞄设置
  │    ├─ VISUAL Tab: ESP/透视设置
  │    ├─ MISC Tab:  辅助功能
  │    ├─ WEAPON Tab:武器配置
  │    └─ CONFIG Tab:配置文件
  ├─ renderPersistentOverlay:
  │    └─ ESP 绘制 (即使菜单关闭)
  └─ ImGui::Render() → Metal 命令提交
```

---

## 六、GameHooks — 游戏内存操作

### 6.1 游戏内存偏移

Delta Force (Unreal Engine) 的关键数据偏移：

```c
typedef struct {
    uint64_t entity_list;       // 0x100EDF000  — 实体数组
    uint64_t local_player;      // 0x100EE1000  — 本地玩家指针
    uint64_t camera_manager;    // 0x100EE2000  — 相机矩阵
    uint64_t visible_mask;      // 0x100EE3000  — 可见性标志
    uint64_t health_offset;     // 0x120        — HP 值
    uint64_t team_offset;       // 0xF0         — 队伍 ID
    uint64_t position_offset;   // 0x180        — 世界坐标 (Vector3)
    uint64_t view_angle_offset; // 0x1C0        — 视角角度
    uint64_t weapon_offset;     // 0x2A0        — 当前武器名
    uint64_t aimbot_angle;      // 0x100EE4000  — 自瞄角度
    uint64_t recoil_offset;     // 0x2B0        — 后坐力参数
    uint64_t esp_offsets[4];    // 骨骼/名字/血条/距离
} GameOffsets;
```

### 6.2 进程附加

```
hooks_attach_to_game()
  ├─ xpf_find_process("Star") 或 "DeltaForce"
  ├─ task_for_pid() → 获取游戏 task port
  ├─ 失败时: xpf_attach_kernel_task() (内核级附加)
  └─ xpf_sandbox_escape() → 绕过游戏沙箱
```

### 6.3 特征码扫描

在游戏二进制中搜索特定字节模式来定位函数：

```
hooks_find_pattern(pattern, length, out_addr)
  ├─ vm_region() 遍历所有可执行内存区域
  ├─ 逐个区域 memcmp 匹配
  └─ 返回匹配地址
```

### 6.4 各功能实现原理

#### 6.4.1 No Recoil (无后坐力)

```
原理: 游戏每帧调用 ApplyRecoil() 对视角施加后坐力偏移
方法: 搜索后坐力计算函数的特征码 → NOP 掉浮点存储指令

hooks_patch_recoil(YES)
  ├─ 搜索模式: F3 44 0F 11 2D (SSE movss 指令)
  ├─ 保存原始指令
  └─ 写入 ARM64 NOP (0x1F2003D5)
  
hooks_patch_recoil(NO)
  └─ 恢复原始指令
```

#### 6.4.2 No Spread (无散布)

```
原理: 武器散布函数计算子弹随机偏移
方法: NOP 掉散布计算代码
```

#### 6.4.3 Wallhack (透视)

```
原理: 引擎的可见性检查 (IsVisible) 返回 false 时隐藏敌人
方法: 遍历实体列表 → 修改 visible_mask = 1

hooks_set_all_visible()
  ├─ 读取 local_player → 获取 local_team
  ├─ 遍历 entity_list (最大64实体)
  ├─ 对 team != local_team 的实体
  └─ 写 visible_mask = 1
```

#### 6.4.4 Aimbot (自瞄)

```
原理: 计算本地到目标的方位角/俯仰角, 写入视角数据

hooks_aimbot(target_entity)
  ├─ 读取 target_entity.position (Vector3)
  ├─ 读取 local_player.position (Vector3)
  ├─ 计算:
  │    dx = target.x - local.x
  │    dy = target.y - local.y
  │    dz = target.z - local.z
  │    yaw = atan2(dy, dx) * 180/π
  │    pitch = -asin(dz/dist) * 180/π
  └─ 写入 angles[yaw, pitch] → aimbot_angle 地址
```

---

## 七、ESPOverlay — 透视渲染

### 世界坐标 → 屏幕坐标转换

```
worldToScreen(worldPos, viewMatrix, projectMatrix, screenW, screenH, out)
  ├─ [1] 世界坐标 × ViewMatrix → 观察空间
  ├─ [2] 观察空间 × ProjectionMatrix → 裁剪空间
  ├─ [3] 透视除法 (clip.xyz / clip.w) → NDC
  ├─ [4] NDC → 屏幕像素坐标
  └─ 返回是否在屏幕上 (clip.w > 0.01 && ndc.z < 1.0)
```

### ESP 渲染要素

```
每个实体的绘制:
  ├─ 方框 (Box)
  │    ├─ 矩形边框 (基于距离计算大小)
  │    └─ 颜色: 绿=队友, 红=可见敌人, 黄=不可见敌人
  │
  ├─ 血量条 (Health Bar)
  │    ├─ 在方框右侧绘制垂直条
  │    └─ 颜色渐变: 绿→黄→红 (基于 HP%)
  │
  ├─ 名字标签 (Name)
  │    └─ 在方框上方绘制
  │
  └─ 距离 (Distance)
       └─ 在方框下方绘制 "XXm"
```

---

## 八、WeaponConfig — 武器配置系统

### 通知机制

```
用户选择武器
  └─ [[WeaponConfigManager shared] applyConfigForWeapon:@"M4A1"]
        ├─ 加载对应配置 (NSDictionary)
        ├─ 创建 WeaponConfig 对象
        ├─ 设置 currentConfig
        └─ postNotification: @"WeaponConfigChanged"
              └─ GameHooks 接收 → 应用后坐力/自瞄参数
```

### 配置参数说明

```objc
@property double recoilCompensationX;  // 水平后坐力补偿 0.0-1.0
@property double recoilCompensationY;  // 垂直后坐力补偿 0.0-1.0
@property double aimSpeed;             // 自瞄速度倍率
@property double fovScale;             // FOV 缩放
@property BOOL autoFire;               // 自动开火
@property BOOL aimAssist;              // 自瞄辅助
@property BOOL noRecoil;               // 无后坐力
@property BOOL wallhack;               // 透视
@property BOOL esp;                    // ESP
@property NSString *aimBone;           // 瞄准骨骼: head/neck/chest/pelvis
@property float aimFov;                // 自瞄 FOV 范围
@property float aimSmooth;             // 自瞄平滑度
```

---

## 九、防检测体系

### 9.1 窗口层防护

| 技术 | 原理 | 对抗目标 |
|------|------|---------|
| `_isSystemWindow=YES` | 伪装成系统 UIWindow | 窗口枚举检测 |
| `_isSecure=YES` | 安全窗口标志 | 截图检测 |
| `UITextField.secureTextEntry` | 防止 Metal 层被捕获 | 屏幕录制检测 |
| `SBSAccessibilityWindowHostingController` | 通过辅助功能托管, 不出现在窗口列表 | WindowServer 检测 |
| `windowLevel=10000010` | 极高层级, 在游戏 UI 之上 | 渲染覆盖检测 |

### 9.2 字符串加密

所有敏感字符串在编译时加密为字节数组, 运行时通过 splitmix64 算法解密:

```
编译时: "Checking..." → {0x5d,0x4c,0x15,0x5a,...}
运行时: DecryptBytes(encrypted, seed, length) → "Checking..."
```

### 9.3 IOHID 事件级操控

```
正向: 注册全局 HID 回调, 捕获游戏触摸事件
反向: 屏蔽菜单区域的触摸传递 (setSenderID=0)
```

### 9.4 内核级隐身

```
通过 XPF:
  ├─ AMFI 绕过 → 无签名验证
  ├─ 沙箱绕过 → 无进程访问限制
  ├─ 开发者模式绕过 → 无需开发者模式
  └─ PPL 绕过 → 无页表保护
```

---

## 十、完整数据流

```
用户启动 App
  │
  ▼
AppDelegate::didFinishLaunching
  │
  ├─ XPF 初始化 ────────────────────────────────────────────┐
  │   ├─ kernel_task 获取                                      │
  │   ├─ 内核符号解析 (异步)                                    │
  │   └─ kcall 原语设置                                        │
  │                                                            │
  ▼                                                            │
LoginViewController                                           │
  ├─ 输入32位key                                               │
  └─ bypassAuthorize()  [测试模式]                              │
       │                                                        │
       ▼                                                        │
AppViewController                                              │
  ├─ 选择武器 → WeaponConfig                                    │
  ├─ 点击 ACTIVATE → HUDController.show()                       │
  │                                                             │
  ▼                                                             │
HUDController                                                  │
  ├─ createWindowsOnScene                                       │
  │   ├─ HUDMainWindow (Metal + ImGui)                          │
  │   └─ TouchMainWindow (IOHID)                                │
  │                                                             │
  ▼                                                             │
GameHooks                                                      │
  ├─ hooks_attach_to_game()                                     │
  │   └─ xpf_find_process("Star") ──────────────────────────────┘
  ├─ hooks_patch_recoil(YES)     → XPF kcall → 内核内存写
  ├─ hooks_patch_no_spread(YES)  → XPF kcall → 内核内存写
  └─ hooks_patch_wallhack(YES)   → XPF kcall → visible_mask=1

  ▼
User 在游戏中
  ├─ ESP: 每帧通过 ImGui 渲染实体方框/血量/名字
  ├─ Aimbot: 计算角度 → XPF → 写 aimbot_angle
  ├─ No Recoil: 后坐力代码已被 NOP
  └─ Touch: HID 事件过滤 → 菜单交互不传递到游戏
```

---

## 附录: 文件依赖关系

```
main.m
  ├─ LoginViewController.m → CryptoUtils.m
  ├─ AppViewController.m → WeaponConfig.m → GameHooks.mm
  └─ HUDController.m
       ├─ HUDRootViewController.m
       │    ├─ MetalRenderer.mm
       │    └─ ImGuiAdapter.mm → ESPOverlay.mm
       └─ TouchMainWindow.m → HIDEventManager.m

XPFKernelInterface.c (独立, 被所有模块调用)
```

---

## 附录: 防封网关验证系统

### 原理

用户在游戏时必须通过 `202.189.9.12:443` 防封代理才能使用作弊，否则直接拒绝。

这样做的目的：
- 游戏反作弊系统检测到的流量来源是 `202.189.9.12`，而不是用户的真实 IP
- 即使检测到异常行为，封禁的也是代理 IP，用户换个端口继续用
- 批量封号时不会波及到真正的用户

### 实现

```objc
#define ANTIBAN_HOST @"202.189.9.12"
#define ANTIBAN_PORT 443
#define ANTIBAN_TIMEOUT 5

- (BOOL)checkAntibanGateway {
    // TCP connect 到 202.189.9.12:443
    // 成功 → 用户挂了代理 → 放行
    // 失败 → 用户裸连 → 拒绝并提示
}
```

检测放在输入32位key、点击
