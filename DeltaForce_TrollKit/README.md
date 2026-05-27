# DeltaForce TrollKit v2.1

**内核级 iOS 游戏作弊框架** — 基于 XPF 内核利用 + PPL 绕过

## 架构总览

```
┌─────────────────────────────────────────────────────┐
│                  Star.app (TrollStore)               │
│  ┌──────────────────────────────────────────────┐   │
│  │  AppDelegate                                 │   │
│  │  ├── XPF Kernel Init (iOS 15-18)             │   │
│  │  ├── LoginViewController (授权验证)            │   │
│  │  └── AppViewController (主菜单)                │   │
│  └──────────────────────────────────────────────┘   │
│                                                      │
│  ┌──────────────────────────────────────────────┐   │
│  │  HUDController (作弊覆盖层)                    │   │
│  │  ├── HUDMainWindow (level 10000010)          │   │
│  │  ├── TouchMainWindow (level 10000011)        │   │
│  │  ├── SBSAccessibilityWindowHostingController │   │
│  │  └── Metal + ImGui 渲染                      │   │
│  └──────────────────────────────────────────────┘   │
│                                                      │
│  ┌──────────────────────────────────────────────┐   │
│  │  GameHooks (Delta Force 进程)                 │   │
│  │  ├── 特征码扫描 / 内存补丁                     │   │
│  │  ├── No Recoil / No Spread                    │   │
│  │  ├── ESP / Wallhack / Aimbot                  │   │
│  │  └── Speed Hack / God Mode                    │   │
│  └──────────────────────────────────────────────┘   │
│                                                      │
│  ┌──────────────────────────────────────────────┐   │
│  │  XPF Kernel Framework                         │   │
│  │  ├── xpf_common_init (内核符号解析)            │   │
│  │  ├── xpf_ppl_init (PPL bypass, iOS 16+)      │   │
│  │  ├── xpf_non_ppl_init (iOS 15 fallback)      │   │
│  │  ├── kcall/kexec 原语                         │   │
│  │  └── 物理内存 r/w / 进程操作                   │   │
│  └──────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────┘
```

## 功能清单

### 🎯 自瞄 (Aimbot)
- ✅ 自瞄开关 (Aimbot Toggle)
- ✅ 自动开火 (Auto Fire)
- ✅ 激活方式: Always / ADS / Toggle
- ✅ FOV 范围设置 (1-30°)
- ✅ 平滑度调节 (0.1-1.0)
- ✅ 瞄准骨骼选择 (Head/Neck/Chest/Pelvis)
- ✅ 最大距离限制
- ✅ 强制爆头 (Force Headshot)

### 👁 视觉 (Visual)
- ✅ ESP 方框 (Box ESP)
- ✅ 透视穿墙 (Wallhack)
- ✅ 玩家名称显示
- ✅ 血量条
- ✅ 距离显示
- ✅ 骨骼透视 (Skeleton)
- ✅ 物品/载具 ESP
- ✅ 自定义颜色 (队友/敌人/可见)

### ⚙ 辅助 (Misc)
- ✅ 无后坐力 (No Recoil)
- ✅ 无散布 (No Spread)
- ✅ 无需换弹 (No Reload)
- ✅ 快速射击 (Rapid Fire)
- ✅ 子弹追踪 (Magic Bullet)
- ✅ 加速 (Speed Hack 1-5x)
- ✅ 穿墙 (No Clip)
- ✅ 无限弹药
- ✅ 无敌模式 (God Mode)

### 🔫 武器配置
- ✅ 12 种武器预设 (AKM, M4A1, K416, AUG等)
- ✅ 独立后坐力/弹道参数
- ✅ 一键应用配置
- ✅ 自定义微调

## 系统要求

| 组件 | 要求 |
|------|------|
| iOS | 14.0 - 18.5 |
| 架构 | arm64 / arm64e |
| 越狱 | 无需 (TrollStore + XPF) |
| 安装 | TrollStore 2.0+ (.tipa) |
| 目标 | Delta Force (iOS) |

## 编译指南

### 方法1: Theos (推荐)

```bash
# 安装 Theos
bash -c "$(curl -fsSL https://raw.githubusercontent.com/theos/theos/master/bin/install-theos)"

# 编译
cd DeltaForce_TrollKit
make package

# 输出: .deb / .tipa
```

### 方法2: Xcode + TrollStore

```bash
# 使用 xcodebuild
xcodebuild -project Star.xcodeproj -scheme Star -sdk iphoneos \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO \
  PRODUCT_BUNDLE_IDENTIFIER=com.star.deltaforce.trollkit

# 打包为 .tipa
mkdir -p Payload
cp -r build/Release-iphoneos/Star.app Payload/
zip -r Star.tipa Payload/
```

### 方法3: 交叉编译

```bash
# 使用 iOS toolchain
export CC=$(xcrun --sdk iphoneos --find clang)
export SDK=$(xcrun --sdk iphoneos --show-sdk-path)

$CC -arch arm64 -arch arm64e -isysroot $SDK \
  -framework UIKit -framework Metal -framework CoreGraphics \
  -framework IOKit -framework Foundation \
  -ObjC -fobjc-arc \
  -o Star src/*.m src/*.mm \
  -Iinclude -lz
```

## 安装部署

### 通过 TrollStore

1. 编译生成 `Star.tipa`
2. 通过 AirDrop / 文件传输 发送到设备
3. 用 TrollStore 打开 .tipa
4. 点击 "Install"
5. 从桌面打开 "Star" 应用

### 通过手动侧载

```bash
# 使用 ldid (TrollStore 内置)
ldid -Ssign.plist Star
# 复制到 /Applications/
cp -r Star.app /Applications/
uicache -p /Applications/Star.app
```

## 使用方法

### 首次运行

1. 打开 Star 应用
2. 在授权界面输入 32 位授权密钥
3. 点击 "Authorize"
4. 验证成功后自动进入主菜单

### 主菜单

1. **武器选择**: 点击预设武器按钮 (AKM, M4A1 等)
2. **设备信息**: 右上角显示 FPS/Ping/玩家数
3. **状态卡**: 左下角显示当前状态
4. **激活按钮**: 点击 "ACTIVATE CHEAT" 打开作弊菜单

### 作弊菜单 (HUD)

- **AIM**: 自瞄设置
- **VISUAL**: 透视/ESP 设置
- **MISC**: 辅助功能
- **WEAPON**: 武器配置
- **CONFIG**: 配置保存

### 按键操作

- 点击主按钮: 切换 HUD 菜单
- 触摸屏幕: 自动识别游戏触摸/作弊触摸
- 菜单按钮: 点击切换功能

## 内核利用细节

### XPF 框架初始化流程

```
xpf_start_with_kernel_path()
├── open/mmap kernelcache
├── fat_init / fat_find_slice
├── pfsec_init (__TEXT_EXEC, __PPLTEXT, __DATA)
├── pfsec_init (AppleMobileFileIntegrity)
├── pfsec_init (sandbox, AppleImage4)
├── 解析内核版本 (Darwin Kernel Version)
│
├── xpf_ppl_init() [iOS 16+]
│   ├── ppl_enter / ppl_bootstrap_dispatch
│   ├── pmap_enter_options_ppl / ppl_trust_cache_rt
│   └── PPL 页表修改
│
├── xpf_non_ppl_init() [iOS 15]
│   ├── pmap_tt_deallocate
│   ├── vm_first_phys / vm_last_phys
│   └── pmap_image4_trust_caches
│
└── xpf_common_init()
    ├── kernelSymbol (allproc, pmap, proc)
    ├── kcall_return gadget
    └── exception_return
```

### 防检测措施

1. **SBSAccessibilityWindowHostingController**: 窗口通过辅助功能托管, 不显示在窗口列表中
2. **TouchMainWindow 标志**: `_isSystemWindow=YES`, `_isSecure=YES`, `_ignoresHitTest=YES`
3. **字符串加密**: 所有字符串运行时通过 splitmix64 + NEON XOR 解密
4. **IOHID 事件拦截**: 使用 HID 事件系统捕获/过滤触摸, 不修改游戏代码
5. **Metal 绕过截图**: 使用 CAMetalLayer + secureTextEntry 防止截图检测
6. **内核级操作**: 通过 XPF 直接修改内核内存, 绕过用户态检测

## 文件结构

```
DeltaForce_TrollKit/
├── Makefile                    # Theos 编译
├── Info.plist                  # 应用元信息
├── sign.plist                  # 权限签名
├── README.md                   # 本文件
├── include/
│   ├── XPFKernelInterface.h    # XPF 内核接口
│   ├── CryptoUtils.h           # 解密工具
│   ├── LoginViewController.h
│   ├── AppViewController.h
│   ├── HUDController.h
│   └── GameHooks.h
└── src/
    ├── main.m                  # 入口 + AppDelegate
    ├── XPFKernelInterface.c    # 内核利用框架
    ├── CryptoUtils.m           # splitmix64 解密
    ├── LoginViewController.m   # 授权登录
    ├── AppViewController.m     # 主菜单
    ├── HUDController.m         # 覆盖层管理
    ├── HUDRootViewController.m # Metal 渲染控制器
    ├── TouchMainWindow.m       # 触摸捕获窗口
    ├── TouchViewController.m   # 触摸控制器
    ├── HIDEventManager.m       # HID 事件系统
    ├── GameHooks.mm            # 游戏内存钩子
    ├── ESPOverlay.mm           # ESP 透视绘制
    ├── MetalRenderer.mm        # Metal 渲染
    ├── ImGuiAdapter.mm         # ImGui 菜单
    ├── WeaponConfig.m          # 武器配置
    └── DeviceInfo.m            # 设备信息
```

## 免责声明

本代码仅供安全研究和教育目的。禁止用于任何非法用途。使用本软件造成的任何后果由使用者自行承担。

---

**DeltaForce TrollKit v2.1** | Kernel Level | iOS 15-18 | arm64/arm64e
