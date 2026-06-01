# DeltaForce TrollKit v2.1 — 完整技术文档

## 1. 项目概述

DeltaForce TrollKit 是一个针对《三角洲行动》(Delta Force) 手游的 iOS 内核级作弊框架。通过 TrollStore (CoreTrust bug, CVE-2022-26766) 实现永久自签名安装，无需越狱即可运行大部分功能。伪装为苹果系统自带的 Stocks.app (com.apple.stocks)，具备完整的 ESP 透视、自瞄、无后坐力、无散布、武器配置等全功能。

**编译产物**: `Stocks.tipa`（TrollStore 安装包）
**目标架构**: arm64
**最低系统**: iOS 13.0
**支持环境**: TrollStore (CoreTrust) / 越狱 (unc0ver/Taurine/Dopamine)

---

## 2. 项目架构

```
DeltaForce_TrollKit/
├── src/                              # 源代码
│   ├── main.m                        # AppDelegate + 环境检测 + 启动流程
│   ├── SceneDelegate.m               # iOS 13+ Scene 生命周期
│   ├── LoginViewController.m         # 授权密钥验证 + 防封网关检测
│   ├── AppViewController.m           # 主界面 (武器选择 + 状态面板 + 激活按钮)
│   ├── HUDController.m               # 作弊覆盖层管理器 (双窗口 + SBS 托管)
│   ├── HUDMainWindow.m               # HUD 窗口 (伪装系统窗口标志)
│   ├── HUDRootViewController.mm      # Metal + ImGui 60fps 渲染控制器
│   ├── TouchMainWindow.m             # 触摸捕获窗口 (IOHIDEventSystemClient)
│   ├── TouchViewController.m         # 触摸事件视图控制器
│   ├── HIDEventManager.m             # IOHIDEventSystemClient 事件管理
│   ├── GameHooks.mm                  # 游戏内存读写钩子 (TrollStore 兼容)
│   ├── ESPOverlay.mm                 # 透视绘制 (W2S + Box/Health/Name/Distance ESP)
│   ├── MetalRenderer.mm              # Metal 渲染封装
│   ├── ImGuiAdapter.mm               # Dear ImGui 完整作弊菜单 (5 Tab)
│   ├── CryptoUtils.m                 # splitmix64 + NEON XOR 字符串解密引擎
│   ├── XPFKernelInterface.c          # XPF 内核接口 (安全存根, TrollStore 兼容)
│   ├── ExternalStubs.c               # 外部 dylib 替代实现 (kern_reading/writing)
│   ├── WeaponConfig.m                # 12种武器预设配置
│   └── DeviceInfo.m                  # 游戏实时信息采集 (FPS/Ping/玩家数)
│
├── include/                          # 头文件
│   ├── XPFKernelInterface.h          # 内核接口 + GameOffsets 结构 + xpf_attach_to_game
│   ├── CryptoUtils.h                 # 加密解密工具声明
│   ├── imgui/                        # Dear ImGui 源码 (v1.90+)
│   │   ├── imgui.h / imgui.cpp
│   │   ├── imgui_draw.cpp / imgui_widgets.cpp / imgui_tables.cpp
│   │   └── backends/imgui_impl_metal.h / imgui_impl_metal.mm
│   └── *.h                           # 各模块头文件
│
├── Frameworks/
│   └── libjailbreak.dylib / libchoma.dylib  # 原始内核库 (已替换为 ExternalStubs.c)
│
├── sign.plist                        # TrollStore 签名权限 (task_for_pid / HID / IOKit)
├── Makefile                          # theos 构建脚本
├── control                           # theos 包管理信息
├── Info.plist                        # iOS App 元数据 (伪装 com.apple.stocks)
├── AppIcon60x60@2x.png               # 伪装苹果股票图标
├── Assets.car / PkgInfo / Base.lproj/ # 应用资源
└── .github/workflows/build.yml       # GitHub Actions CI/CD 自动构建
```

---

## 3. 技术栈详解

### 3.1 运行环境与签名

| 层级 | 技术 | 用途 |
|------|------|------|
| 安装 | **TrollStore (CoreTrust bug)** | 利用 CVE-2022-26766 CoreTrust 签名绕过，永久安装自签 IPA |
| 权限 | **sign.plist 硬编码 entitlements** | `get-task-allow`, `task_for_pid-allow`, `com.apple.system-task-ports` |
| 进程间通信 | **Mach VM API** (`task_for_pid` + `mach_vm_read_overwrite` + `mach_vm_write`) | 跨进程读写游戏内存，无需内核 exploit |
| UI | **UIKit → UIWindow / UIViewController** | 主界面 (Login / AppView) |
| 渲染 | **Metal + CAMetalLayer** | 作弊覆盖层渲染 (60fps) |
| GUI | **Dear ImGui** (imgui_impl_metal) | 作弊菜单 5 Tab UI |
| 输入拦截 | **IOHIDEventSystemClient** (私有 IOKit API) | 捕获/注入触摸事件 |
| 窗口伪装 | **SBSAccessibilityWindowHostingController** (私有 SpringBoard 类) | 窗口注册反检测 |
| 加密 | **splitmix64 PRNG + NEON XOR (veorq_s8/veor_s8)** | 运行时字符串解密 |
| 内核层 | **XPF Kernel Interface** (仅越狱) | kcall / physread / PPL bypass / AMFI disable |
| 内存扫描 | **特征码扫描** (byte pattern matching) | 运行时定位游戏函数偏移 |

### 3.2 TrollStore 环境适配

TrollStore 应用**没有内核权限**，所有特权操作（kernel_task / physread / kcall）均不可用。本项目做了完整的 TrollStore 兼容适配：

```
启动流程:
detect_environment() → is_trollstore()=1
    ↓
xpf_initialize_kernel() → 标记 userspace-only mode (不尝试 task_for_pid(0))
    ↓
jb_init() → 安全返回 (不调用任何内核 exploit 原语)
    ↓
用户点击 ACTIVATE → HUDController.show()
    ↓
后台 hooks_attach_to_game()
    ├── sysctl KERN_PROC 查找游戏 PID
    ├── task_for_pid(mach_task_self(), gamePid, &gameTask)  ← 有 sign.plist 权限
    └── mach_vm_read/write 读写游戏内存
```

**关键设计**：所有内核相关函数在 TrollStore 环境下返回安全存根值而非崩溃。

### 3.3 Mach VM 内存访问

```c
// ExternalStubs.c - 安全跨进程内存读写
kern_return_t kern_reading(mach_port_t task, uint64_t addr, void *buf, size_t *size) {
    return vm_read_overwrite(task, (vm_address_t)addr, (vm_size_t)(*size),
                              (vm_address_t)buf, &out_size);
}

kern_return_t kern_writing(mach_port_t task, uint64_t addr, void *buf, size_t size) {
    return vm_write(task, (vm_address_t)addr, (vm_offset_t)buf,
                    (mach_msg_type_number_t)size);
}
```

---

## 4. 核心子系统

### 4.1 双窗口叠加层系统 (HUDController)

**初始化流程** (完全匹配原版 Amazon2 二进制):
```
-[HUDController createWindowsOnScene:]
  ├── 创建 HUDRootViewController + TouchViewController
  ├── 创建 HUDMainWindow (windowLevel 10000010)
  │   └── _initWithFrame:attached: → commonInit (原版私有初始化器模式)
  ├── 创建 TouchMainWindow (windowLevel 10000011)
  ├── setupHostingController
  │   └── attachWindowToHostingController (NSInvocation 三参数调用)
  │       └── registerWindow:contextID:windowLevel: (传递 _contextId + windowLevel)
  ├── 初始隐藏窗口 (注册完后再隐藏)
  └── registerHIDEventCallback (dispatch_once)
```

**窗口层级**:
```
┌─────────────────────────────────────────────┐
│ TouchMainWindow (windowLevel 10000011)        │  ← 最高层
│   └── TouchViewController (透明, 捕获触摸)    │     拦截作弊菜单区域的触摸
│   └── Background (colorWithWhite:1.0 alpha:0.001) │ 极浅白色, 视觉透明但能拦截触摸
│   └── 100Hz NSTimer (0.01s)                  │     timerFired: 屏幕尺寸调整
├─────────────────────────────────────────────┤
│ HUDMainWindow (windowLevel 10000010)          │
│   └── HUDRootViewController                   │
│       └── UITextField (CAMetalLayer 容器)     │  ← 反检测: UITextField 是常见 UIKit 组件
│           └── UIFieldEditor.layer             │     CAMetalLayer 加到 UIFieldEditor 的 layer
│               └── CAMetalLayer                │  ← ImGui 作弊菜单
│                   └── ImGuiAdapter (5 Tab + ESP)
├─────────────────────────────────────────────┤
│ DeltaForceClient (游戏窗口)                   │  ← 游戏渲染
├─────────────────────────────────────────────┤
│ Stocks.app (主界面, windowLevel normal)       │  ← 伪装应用
└─────────────────────────────────────────────┘
```

**SBS 窗口托管** (原版 sub_10000A514):
```objc
// 使用 NSInvocation 调用三参数方法 registerWindow:contextID:windowLevel:
// 不是简单的 registerWindow: (单参数)
NSMethodSignature *sig = [NSMethodSignature signatureWithObjCTypes:"v32@0:8@16Q24d28"];
NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
[inv setTarget:hostingController];
[inv setSelector:NSSelectorFromString(@"registerWindow:contextID:windowLevel:")];
[inv setArgument:&window atIndex:2];       // UIWindow*
[inv setArgument:&contextId atIndex:3];    // uint64_t _contextId
[inv setArgument:&winLevel atIndex:4];     // double windowLevel
[inv invoke];
```

**关键技术点**:
- `+[HUDMainWindow _isSystemWindow]` → `YES` (伪装为系统窗口)
- `-[HUDMainWindow _isSecure]` → `YES` (防截图/录制检测)
- `-[HUDMainWindow _ignoresHitTest]` → `YES` (避免触摸事件冲突)
- `-[HUDMainWindow _shouldCreateContextAsSecure]` → `YES` (安全渲染上下文)
- `HUDMainWindow` 使用 `_initWithFrame:attached:` + `commonInit` 两步初始化 (匹配原版)
- `gMetalContainer.secureTextEntry = YES` — UITextField 防截图

### 4.2 ImGui 渲染管线 (HUDRootViewController)

**反检测容器**: CAMetalLayer 并非直接添加到 UIView.layer，而是：
1. 创建 `UITextField` (常见 UIKit 组件，反作弊扫描器不会怀疑)
2. 设置 `secureTextEntry = YES` (防截图)
3. 将 CAMetalLayer 添加到 UITextField 的第一个子视图 `UIFieldEditor.layer`
4. 渲染选择器名为 `ChangeUI` (对应原版二进制中的混淆方法名)

**Metal 配置** (匹配原版):
- `framebufferOnly = YES` (非 NO — 更接近正常渲染行为)
- `maximumDrawableCount = 2` (非 3)
- `pixelFormat = MTLPixelFormatBGRA8Unorm`

**渲染管线**:
```
CADisplayLink (60fps)
    ↓ ChangeUI:
    ├── [gMetalLayer nextDrawable]
    ├── [gCmdQueue commandBuffer]
    ├── MTLRenderPassDescriptor (透明背景, clearColor=0,0,0,0)
    ├── ImGui_ImplMetal_NewFrame()
    ├── [ImGuiAdapter beginFrame:]
    │   └── io.DisplaySize / io.DeltaTime 设置
    ├── [ImGuiAdapter renderCheatMenu:]
    │   ├── renderPersistentOverlay: (每50ms更新实体 + ESP渲染)
    │   └── 5 Tab 菜单 (AIM/VISUAL/MISC/WEAPON/CONFIG)
    ├── [ImGuiAdapter endFrame:]
    │   ├── ImGui::Render()
    │   └── ImGui_ImplMetal_RenderDrawData()
    └── [cmdBuffer commit]
```

**导出全局变量** (供 TouchMainWindow timerFired 使用):
```objc
float g_screenScale;   // UIScreen.scale
float g_screenWidth;   // bounds.size.width
float g_screenHeight;  // bounds.size.height
```

### 4.3 ESP 透视引擎 (ESPOverlay)

**W2S (World-to-Screen) 管线**:
```
游戏内存读取 4x4 ViewMatrix + 4x4 ProjectionMatrix
    ↓
ViewProj = ProjectionMatrix × ViewMatrix (矩阵乘法)
    ↓
clip = ViewProj × (worldX, worldY, worldZ, 1.0)
    ↓
NDC 裁剪空间检查 (clip.w < 0.001 → 丢弃)
    ↓
screenX = (clip.x/clip.w + 1) * 0.5 * screenWidth
screenY = (1 - clip.y/clip.w) * 0.5 * screenHeight
    ↓
屏幕边界检查 → 过滤屏幕外实体
```

**ESP 绘制内容** (使用 ImGui `ImDrawList`):
| 元素 | 绘制方式 | 颜色规则 |
|------|---------|---------|
| 3D 方框 | 2px ImDrawList::AddRect + 1.5px 黑色外轮廓 | 可见=黄色, 不可见=红色 |
| 血条 | AddRectFilled 渐变 | >60%=绿, >30%=橙, ≤30%=红 |
| 距离标签 | AddText | 白色 |
| 名字标签 | AddText (从内存读取玩家名) | 白色 |
| HP 数字 | AddText | 可见黄/不可见红 |
| 头部标记 | AddLine (V形线) | 同框色 |

### 4.4 触摸事件拦截 (HIDEventManager + UIGestureRepresentation)

**HID 回调架构** (完全匹配原版 Amazon2 二进制):
```
registerEventCallback (dispatch_once)
  └── registerHIDCallbackInternal (sub_10000A7E8)
      ├── dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY)
      ├── dlsym("IOHIDEventSystemClientRegisterEventCallback")
      ├── IOHIDEventSystemClientCreate(kCFAllocatorDefault)
      ├── registerCallback(client, onHIDEvent, NULL, NULL)  ← 注册回调
      └── dlclose(handle)

onHIDEvent (sub_100007154) — HID 事件回调:
  ├── UIGestureRepresentation (iOS 私有类, 将 HID 事件转为手势表示)
  │   └── representationWithHIDEvent:hidStreamIdentifier:
  ├── 提取触摸位置 (location)
  ├── 检测触摸阶段 (isLift / isInRange / isInRangeLift / isCancel)
  ├── 计算触摸激活状态 → g_touchActive (uint8_t)
  └── 更新全局变量 → g_touchX / g_touchY (float)
```

**TouchMainWindow.timerFired:** (sub_100009608):
```
100Hz 定时器 (0.01s, 非 60Hz)
  └── 根据屏幕状态调整 Background 视图 frame/center
      ├── g_screenScale / g_screenWidth / g_screenHeight (来自 HUDRootViewController)
      └── g_useRotatedSize 标志 → 横屏 vs 竖屏
  (不处理 HID 事件 — HID 处理由 onHIDEvent 回调直接完成)
```

**全局触摸状态变量** (对应原版反编译):
```c
uint8_t g_touchActive;   // byte_10139CB60  — 0=触摸中, 1=未触摸
float   g_touchX;         // dword_10139CB68 — 触摸 X 坐标
float   g_touchY;         // dword_10139CB70 — 触摸 Y 坐标
```

**动态符号加载**: 所有 IOKit 函数通过 `dlopen(RTLD_LAZY)` + `dlsym()` 动态获取，避免静态链接被符号表扫描检测。使用后立即 `dlclose`。

### 4.5 游戏内存钩子 (GameHooks)

**进程附加流程**:
1. `find_pid_by_name("DeltaForceClient")` → sysctl KERN_PROC 遍历进程表
2. `task_for_pid(mach_task_self(), pid, &g_gameTask)` → 获取游戏 task 端口
3. `hooks_get_game_base()` → vm_region_64 遍历找到第一个 >1MB 的可执行区域 (Mach-O 头验证 MH_MAGIC_64)

**内存补丁**:
- 无后坐力: ARM64 NOP (0xD503201F) 写入 recoil_offset
- 无散布: ARM64 NOP 写入散布函数地址
- Wallhack: 遍历实体列表，设置 visible_mask = 1

**自瞄**:
```
读取目标实体坐标 (position_offset)
读取本地玩家坐标
计算 yaw = atan2(dy, dx), pitch = -asin(dz/dist)
写入 aimbot_angle 地址
```

### 4.6 字符串加密引擎 (CryptoUtils)

三层加密体系：
1. **splitmix64**: 64-bit 伪随机生成器产生 XOR 密钥流
2. **NEON 128-bit (veorq_s8)**: 16 字节 NEON XOR 解密
3. **NEON 64-bit (veor_s8)**: 8 字节 NEON XOR 解密

SBS 类名字符串解密用的就是第 4 种特殊模式 — 三段 NEON XOR（16+16+8 字节）。

解密后立即 `memset(buffer, 0, sizeof(buffer))` 安全擦除。

---

## 5. 反检测机制 (Anti-Detection)

### 5.1 窗口检测绕过

| 检测向量 | 对抗手段 |
|---------|---------|
| `UIWindow` 枚举扫描 | `_isSystemWindow` → YES (反作弊会跳过系统窗口) |
| 窗口层级异常检测 | `_isWindowServerHostingManaged` → YES |
| 屏幕截图/录制检测 | `_isSecure` / `_shouldCreateContextAsSecure` → YES |
| 命中测试 (hitTest) | `_ignoresHitTest` → YES |
| SpringBoard 窗口注册 | `SBSAccessibilityWindowHostingController.registerWindow:contextID:windowLevel:` (三参数 NSInvocation 系统级托管) |
| CAMetalLayer 容器检测 | 使用 `UITextField` 而非 `UIView` 作为容器 — UITextField 是常见 UIKit 组件，不会引起怀疑 |
| 窗口内容截图 | `UITextField.secureTextEntry = YES` + `_isSecure` → YES |

### 5.2 静态分析对抗

| 检测向量 | 对抗手段 |
|---------|---------|
| 符号表扫描 | 所有 IOKit 函数通过 `dlopen`/`dlsym` 动态加载，不静态链接 |
| 字符串扫描 | 关键字符串在编译时加密，运行时通过 splitmix64 + NEON XOR 解密，用完立即清零 |
| 类名检测 | SBS 类名使用三段 NEON XOR (`veorq_s8` + `veor_s8`) 解密后 `NSClassFromString` 动态获取 |
| 方法混淆 | 渲染用 `ChangeUI` (对应原版二进制中的混淆选择器名) |
| Metal 渲染层检测 | `CAMetalLayer.framebufferOnly = YES` (匹配正常渲染行为)，`maximumDrawableCount = 2` |
| HID 事件拦截检测 | 使用 `UIGestureRepresentation` 私有类 + 回调模式，不维护事件队列 (减少可检测特征) |

### 5.3 运行时检测绕过

| 检测向量 | 对抗手段 |
|---------|---------|
| 应用完整性校验 | TrollStore CoreTrust 签名绕过 + `com.apple.security.cs.disable-library-validation` |
| 调试检测 | `com.apple.security.cs.debugger` 权限 + `com.apple.security.cs.allow-unsigned-executable-memory` |
| 进程列表扫描 | Stocks.app 伪装为 `com.apple.stocks` (苹果官方 Bundle ID) |
| 窗口覆盖检测 | `CAMetalLayer.framebufferOnly = YES` 使用透明 clearColor (0,0,0,0) 不遮挡游戏 |
| 触摸注入检测 | 通过 IOHIDEventSystemClient 回调 + UIGestureRepresentation 拦截，非注入模式 |
| HUD 激活检测 | `clock_gettime(CLOCK_MONOTONIC)` 安全计时器 + 500ms 防快速点击冷却 |
| TCC 权限保护 | `com.apple.private.tcc.allow: kTCCServiceAll` |

### 5.4 防封网关 (LoginViewController)

```
授权验证流程:
1. 用户输入 32 字符授权密钥
2. TCP 连接检测 202.189.9.12:443 (防封代理连通性)
   ├── 连通 → 允许使用 (用户挂了防封代理)
   └── 不通 → 拒绝使用 (裸连会被游戏反作弊检测)
3. 测试模式: 离线授权 (BypassAuthorize)
4. 正式模式: NetworkManager 服务器验证 (需防封网关在线)
```

### 5.5 环境感知与降级

```
环境检测分级:
├── 越狱 (Jailbroken): 完整功能 (kcall + physread + PPL bypass)
├── TrollStore (CoreTrust): 用户态功能 (mach_vm + HID + Metal overlay)
└── 普通 (Normal): 仅可查看主界面 (无游戏交互能力)
```

---

## 6. CI/CD 自动构建

GitHub Actions macOS-14 Runner:
1. 安装 theos 构建系统
2. 下载 iPhoneOS16.5 SDK
3. `make package FINAL_PACKAGE=1`
4. 输出 `Stocks.tipa` 作为 artifact

---

## 7. 部署指南

### 前置条件
- iOS 13.0 - 18.x 设备
- TrollStore (通过 CoreTrust bug 安装) 或越狱
- 三角洲行动游戏已安装运行

### 安装步骤

```bash
# 1. 编译
cd DeltaForce_TrollKit
make clean
make package FINAL_PACKAGE=1

# 2. 安装到设备
# 将生成的 Stocks.tipa 通过 AirDrop/文件/iTunes 传到设备
# 在 TrollStore 中: 点击 + → 选择 Stocks.tipa → Install

# 3. 启动
# 桌面找到 "Stocks" 应用 (伪装为苹果股票图标)
# 输入授权密钥 (32字符)
# 等待防封网关检测通过
# 点击 ACTIVATE CHEAT → 作弊菜单覆盖层显示
```

### 使用说明

```
菜单控制:
- ESC/关闭窗口按钮: 隐藏作弊菜单 (功能继续运行)
- 小绿条 "CHEAT ON" 指示器: 菜单隐藏时显示
- EMERGENCY HIDE: 关闭所有功能 (应对突发检测)

5 个 Tab:
1. AIM:     自瞄开关 / 自动开火 / FOV / 平滑度 / 骨骼选择 / 最大距离
2. VISUAL:  ESP开关 / 方框透视 / 名字 / 血量 / 距离 / 物品 / 载具 / 颜色
3. MISC:    无后坐力 / 无散布 / 快速换弹 / 射速 / 魔法子弹 / 加速 / 穿墙 / 无敌
4. WEAPON:  12种武器预设 (AKM/QBZ95-1/M4A1/K416/AUG等) / 后坐力滑块
5. CONFIG:  保存/加载/重置配置 / 紧急隐藏
```

### 注意事项

- 偏移地址 (`g_game_offsets`) 是占位值，需要通过游戏实际版本调试获取真实偏移
- TrollStore 环境下 XPF 内核功能 (kcall/physread/PPL bypass) 不可用
- 仅在连接防封网关 (202.189.9.12:443) 时使用，否则有封号风险
- 禁止在排位模式中使用 Wallhack，仅在匹配/娱乐模式使用 ESP

---

## 8. 安全注意事项

1. **偏移更新**: 游戏每次更新后 `g_game_offsets` 需要重新扫描
2. **防封网关**: 必须通过 202.189.9.12 防封代理连接，裸连会被 njshield V5 (kgvmp) 检测
3. **谨慎使用**: Wallhack (SetAllVisible) 和 Aimbot 功能有较高检测风险
4. **TrollStore 限制**: 无法使用内核级隐藏 (PPL bypass/AMFI disable)，反作弊检测风险高于完整越狱
5. **签名权限**: `sign.plist` 中的权限仅在 TrollStore/CoreTrust 环境下有效，普通签名无效

---

## 9. 已知限制

| 限制 | 原因 | 影响 |
|------|------|------|
| 偏移为占位值 | 需要实际调试获取 | ESP/自瞄/无后坐力可能不生效 |
| 无内核隐藏 | TrollStore 无内核权限 | 反作弊检测风险略高 |
| FairPlay 加密 | 游戏二进制加密 | 无法静态分析游戏逻辑，只能运行时扫描 |
| Metal 渲染开销 | 60fps DisplayLink | 约 2-5% CPU 开销 (A12+) |
| 仅 arm64 | iOS 架构限制 | 不支持 iPhone 5s 以下 |
