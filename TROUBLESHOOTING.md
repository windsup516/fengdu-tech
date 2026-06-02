# DeltaForce TrollKit 踩坑经验总结

## 1. ObjC 与 ObjC++ 混编链接错误

**问题**: `GameHooks.mm` (ObjC++) 调用 `Logging.m` (ObjC) 中的 `central_log` 函数时，链接器报 `Undefined symbol: _central_log`。

**原因**: C++ 有名称修饰 (name mangling)，`.mm` 文件编译时会把函数名修饰成 `_Z11central_logPKcPU8NSStringz` 之类，而 `.m` 文件编译保持 C 链接规则输出 `_central_log`。双方对不上。

**解决**: 在头文件中用 `extern "C"` 包裹函数声明：

```c
#ifdef __cplusplus
extern "C" {
#endif
void central_log(const char *tag, NSString *fmt, ...);
#ifdef __cplusplus
}
#endif
```

**通用原则**: 所有会被 `.mm` 和 `.m` 交叉调用的 C 函数，头文件声明都必须加 `extern "C"`。

---

## 2. iOS Mach API 参数数量差异

**问题**: `task_get_exception_ports` 和 `task_swap_exception_ports` 编译报参数数量错误。

**原因**: iOS SDK 版本不同，Mach API 签名不一样。iOS 16.5 SDK 需要 7 个参数 (不是 6 个)，`task_swap_exception_ports` 需要 10 个参数 (不是 9 个)。需要传完整的 `exception_mask_array_t` 数组和 `mach_msg_type_number_t*`。

**解决**:

```c
// task_get_exception_ports — 7 参数版本 (iOS 16.5 SDK)
exception_mask_t oldMasks[EXC_TYPES_COUNT];
mach_msg_type_number_t oldMasksCnt = 0;
exception_handler_t oldHandlers[EXC_TYPES_COUNT];
exception_behavior_t oldBehaviors[EXC_TYPES_COUNT];
thread_state_flavor_t oldFlavors[EXC_TYPES_COUNT];

kern_return_t kr = task_get_exception_ports(
    mach_task_self(),
    EXC_MASK_ALL,
    oldMasks,        // exception_mask_array_t
    &oldMasksCnt,    // mach_msg_type_number_t*
    oldHandlers,     // exception_handler_array_t
    oldBehaviors,    // exception_behavior_array_t
    oldFlavors       // exception_flavor_array_t
);

// task_swap_exception_ports — 10 参数版本
task_swap_exception_ports(
    mach_task_self(),
    EXC_MASK_ALL,
    MACH_PORT_NULL,
    EXCEPTION_DEFAULT,
    THREAD_STATE_NONE,
    oldMasks,        // 旧 masks 数组 (入参)
    &oldMasksCnt,    // 旧 masks 计数 (入参+出参)
    oldHandlers,     // 旧 handlers 数组 (出参)
    oldBehaviors,    // 旧 behaviors 数组 (出参)
    oldFlavors       // 旧 flavors 数组 (出参)
);
```

**通用原则**: 编译前确认 SDK 版本的 Mach API 签名，不同 iOS 版本参数数量和类型可能不同。直接查 SDK 头文件或 SDK 文档。

---

## 3. BSD 函数在 iOS 上不可用

**问题**: `setproctitle` 编译报 `undeclared identifier`。

**原因**: `setproctitle` 是 BSD 特有函数，iOS 没有。即使有头文件声明，链接时也可能找不到符号。

**解决**: 用返回 0 的 stub 替换：

```c
static int setproctitle(const char *fmt, ...) {
    // Not available on iOS, stub
    return 0;
}
```

**通用原则**: 移植 macOS/BSD 代码到 iOS 时，像 `setproctitle`、`sbrk`、`sysctlbyname` 特定字段等都可能不存在。

---

## 4. -Werror 把 warning 当 error 导致编译失败

**问题**: 未使用的静态函数 `vec3_dot`、`vec3_normalize` 被 `-Werror` 当成错误拦截。

**原因**: `-Werror` 把所有 warning 升级为 error，即使是不影响功能的 `-Wunused-function`。

**解决**: 在 Makefile 中加 `-Wno-error=unused-function` 允许未使用函数的 warning 存在而不阻止编译：

```makefile
Stocks_CFLAGS = -fobjc-arc -Wno-error=unused-function
Stocks_OBJCCFLAGS = -fobjc-arc -Wno-error=unused-function
```

**通用原则**: 不要到处 `-Wno-error=*`，先考虑删掉没用的代码。但如果函数是保留备用的，针对性 suppress 比删代码好。

---

## 5. C 字符串 vs NSString 格式串不匹配

**问题**: 旧的 `log_to_file` 接受 `const char *fmt`，新的 `central_log` 接受 `NSString *fmt`。84 处 `SAFE_LOG("...")` 需要改为 `SAFE_LOG(@"...")`。

**解决**: 全局替换 `SAFE_LOG("` → `SAFE_LOG(@"`。注意 `replace_all` 时要确保没有误伤（比如字符串内部的双引号）。

**通用原则**: 重构日志函数签名时，先 grep 统计所有调用点，批量修改。ObjC 下 NSString 字面量可以带 `%@` 格式化对象，C 字符串不行——这是用 NSString 的核心好处。

---

## 6. pthread_mutex 在信号处理器中不安全

**问题**: Crash 信号处理器 (`SIGSEGV`/`SIGBUS`) 中调用 `SAFE_LOG`，而日志函数内部用了 `pthread_mutex_lock`。信号处理器中调用非异步信号安全的函数会导致死锁。

**解决**: 去掉 `pthread_mutex`，容忍极少数情况下日志行交错。对调试日志来说，偶尔的交错比死锁好得多。

**通用原则**: 信号处理器中只能调用异步信号安全函数（`write`、`open`、`_exit` 等）。`pthread_mutex_lock`、`malloc`、`NSLog`、任何 ObjC 方法都不安全。

---

## 7. TrollStore 日志路径选择

**问题**: 用户用 Windows，没有 Mac，无法通过 Xcode/iTunes 查看日志。需要把日志直接写到设备上能用 Filza 浏览的路径。

**路径优先级**:
1. `/var/mobile/Documents/风度_debug.log` — TrollStore 环境有 root 权限，可直接写 `/var/mobile/Documents/`，用 Filza 打开即可看
2. `/tmp/debug_stocks.log` — 系统临时目录，回退方案
3. App container `Documents/debug.log` — iTunes 文件共享可用，但 Windows 需要 iTunes 或第三方工具

**关键**: TrollStore 安装的 app 没有 sandbox，可以写 `/var/mobile/Documents/`。越狱检测绕过模块的 `clean_environment_markers` 不要删除自己的日志路径。

**通用原则**: 日志路径要考虑用户的查看方式。iOS 上 `NSLog` 需要 Mac + Console.app；`fprintf(stderr)` 需要 Xcode；直接写文件 + Filza 对 Windows 用户最友好。

---

## 8. 头文件未提交导致 CI 编译失败

**问题**: 本地 `include/GameHooks.h` 已更新（新增 AimbotConfig、ESPConfig 等结构体），但忘了 `git add`，CI 拉下来编译报 20 个 `unknown type` 错误。

**解决**: `git add include/GameHooks.h && git commit && git push`

**预防**: 新增文件或用新类型时，`git status` 确认所有依赖头文件都已 staged。

---

## 9. GitHub Actions CI 网络问题

**问题**: `git push` 反复报 `Could not connect to server`。

**原因**: 国内网络直连 GitHub 不稳定。

**解决**: 开启 VPN/代理后重试。

**通用原则**: 国内开发环境推送 GitHub，稳定的代理是刚需。

---

## 10. SBSAccessibilityWindowHostingController 注册失败

**问题**: 悬浮窗在切后台后消失，或完全不显示。

**原因**: 
- `_contextId` 为 0 时强制跳过注册（窗口上下文已丢失）
- SBS 类可能在某些 iOS 版本不存在
- 原始反编译中的 `registerWindow:contextID:windowLevel:` 选择器可能不匹配实际 SDK

**解决**:
- 使用 `registerWindowWithContextID:atLevel:` 选择器（太阳神实际采用的）
- contextId=0 时跳过而非崩溃
- 添加后台保活 fallback（监听 `UIApplicationWillResignActiveNotification` 强制刷新窗口）
- Scene 为 nil 时从 `connectedScenes` 取回退

**通用原则**: 私有 API 不可靠，必须有 fallback。多层级后备方案比单一依赖健壮。

---

## 11. SceneDelegate / UIWindowScene 关联问题

**问题**: iOS 13+ 强制使用 SceneDelegate，`UIWindow` 必须关联 `UIWindowScene` 才能显示。如果 `scene` 参数为 nil，窗口创建后不会出现在屏幕上。

**解决**: 在 `createWindowsOnScene:` 中检测 nil，fallback 到 `[UIApplication sharedApplication].connectedScenes.anyObject`。

**通用原则**: iOS 13+ app 必须理解 Scene-based 生命周期。旧代码假设 `UIWindow` 可以直接 `makeKeyAndVisible` 在 iOS 13+ 上不会工作。

---

## 12. makeKeyAndVisible 重置 windowLevel

**问题**: `hudWindow.windowLevel = 10000010.0; [hudWindow makeKeyAndVisible];` 之后读取 level 变成了 10000000。

**原因**: 对 touchWindow 调用 `makeKeyAndVisible` 时，UIKit 在 key window 切换过程中会调整其他窗口的 level。先设 level 再 makeKey 会被覆盖。

**解决**: **先 makeKeyAndVisible，后设 windowLevel**：

```objc
self.hudWindow.hidden = NO;
[self.hudWindow makeKeyAndVisible];
self.hudWindow.windowLevel = 10000010.0;  // AFTER makeKeyAndVisible
```

同时在 `show`、后台恢复、前台激活等所有路径中重新设置 windowLevel。

**通用原则**: `makeKeyAndVisible` / `makeKeyWindow` 都有副作用，会改变窗口的多个属性。关键属性（level、frame）应该在 makeKey 之后再设置。

---

## 13. SBS contextId 后台丢失与窗口重建

**问题**: App 切后台再回来，`_contextId` 变成 0。仅重新调用 SBS 注册无效，窗口永远无法再显示在游戏上层。

**根因**: `_contextId` 是窗口与 render server 的连接标识。App 进入后台后系统可能回收窗口的渲染资源，contextId 归零后仅靠 SBS 重注册无法恢复。必须**销毁窗口并完全重建**。

**解决**:

```objc
- (void)reRegisterSBSHosting {
    unsigned int ctx = [self.hudWindow _contextId];
    if (ctx == 0) {
        // 销毁 + 重建，不能只重注册
        self.hudWindow.hidden = YES;
        self.touchWindow.hidden = YES;
        self.hudWindow = nil;
        self.touchWindow = nil;
        self.hostingController = nil;
        self.windowsCreated = NO;

        id scene = [UIApplication sharedApplication].connectedScenes.anyObject;
        [self createWindowsOnScene:scene];
        [self show];
        return;
    }
    // 正常路径: contextId 有效，仅重注册 SBS
    attachWindowToHostingController(self.hudWindow, self.hostingController);
    attachWindowToHostingController(self.touchWindow, self.hostingController);
}
```

**通用原则**: `_contextId` 是窗口在 render server 侧的生命周期标识。变 0 = 窗口在服务端已不可用。此时任何注册/刷新都无效，必须重建 `UIWindow` 实例。

---

## 14. viewDidLoad 日志盲区 (NSLog vs 文件日志)

**问题**: `HUDRootViewController.viewDidLoad` 里大量 `NSLog` 但文件日志一条都没有。Metal 是否初始化成功完全不可观测。

**原因**: `NSLog` 写入 unified system log，不走 `central_log` 的文件路径。用户在设备上用 Filza 看文件日志，看不到 NSLog 输出。

**解决**: 所有关键路径日志改用 `HUD_LOG` 宏（走 `central_log` → 文件 + stderr）。在 viewDidLoad 关键节点加：

```objc
HUD_LOG(@"viewDidLoad: starting Metal+ImGui init...");
HUD_LOG(@"Screen: %.0fx%.0f scale=%.1f", w, h, scale);
HUD_LOG(@"ImGui context created");
HUD_LOG(@"ImGui Metal backend initialized (device=%s)", [device name UTF8String]);
HUD_LOG(@"Metal+ImGui ready, rendering=%d displayLink=%@", ...);
```

同时在渲染循环首帧确认：
```objc
static int frameCount = 0;
if (++frameCount == 1 || frameCount % 300 == 0) {
    HUD_LOG(@"ChangeUI rendering frame #%d", frameCount);
}
```

**通用原则**: 凡是需要在设备端离线查看的诊断信息，一律用文件日志宏（HUD_LOG/SAFE_LOG），不要只靠 NSLog。NSLog = Mac 专属；文件日志 = 任何设备都能看。

---

## 15. prepareForEntryAnimation 卡在 alpha=0

**问题**: `prepareForEntryAnimation` 先设 `self.view.alpha = 0.0` 再 `UIView animate` 到 1.0。如果动画触发时窗口还没上 render server，动画不会执行，view 永远透明。

**解决**: 加兜底定时器，0.5 秒后检测 alpha 是否恢复：

```objc
- (void)prepareForEntryAnimation {
    self.view.alpha = 0.0;
    [UIView animateWithDuration:0.25 animations:^{
        self.view.alpha = 1.0;
    }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        if (self.view.alpha < 0.5) {
            self.view.alpha = 1.0;  // force visible
        }
    });
}
```

**通用原则**: 涉及窗口/视图显示的动画不能假设一定执行。窗口可能不在 render tree 里，动画被静默跳过。加超时兜底是防御性编程的基本操作。

---

## 16. RootHelper dylib 路径拼接 bug

**问题**: RootHelper 尝试加载 dylib 时报 `errno=2`（文件不存在），路径是：
```
/.../Stocks/Frameworks/libjailbreak.dylib
```
正确路径应该是：
```
/.../Stocks.app/Frameworks/libjailbreak.dylib
```

**根因**: `_NSGetExecutablePath` 返回 `/.../Stocks.app/RootHelper`，拼接路径时多了一步 `stringByDeletingPathExtension`：

```objc
// BUG: stringByDeletingPathExtension 把 .app 删了
NSString *fwDir = [[[exeStr stringByDeletingLastPathComponent]
                   stringByDeletingPathExtension]  // Stocks.app → Stocks
                  stringByAppendingPathComponent:@"Frameworks"];
// 结果: /.../Stocks/Frameworks  ← 错误

// FIX: 直接拼接，不去扩展名
NSString *fwDir = [[exeStr stringByDeletingLastPathComponent]
                  stringByAppendingPathComponent:@"Frameworks"];
// 结果: /.../Stocks.app/Frameworks  ← 正确
```

**通用原则**: `stringByDeletingPathExtension` 对 `.app` 目录也是生效的（它会删最后一个 `.xxx` 后缀）。在 bundle 路径上做字符串操作时，永远验证最终路径是否与 `[[NSBundle mainBundle] bundlePath]` 一致。

---

## 17. TrollStore 环境权限边界

**问题**: RootHelper 名叫 RootHelper 但 log 显示 `euid=501 uid=501 gid=501`（普通 mobile 用户），不是 root。

**根因**: TrollStore 不是越狱。它通过 CoreTrust bug 绕过代码签名，拿到 `platform-application`、`no-sandbox`、`task_for_pid-allow` 等 entitlement，但**不会给你 root**。`euid=0` 需要越狱或独立的 kernel exploit。

**TrollStore 实际能给的权限（已验证）**:
- `platform-application = TRUE` — 平台应用级别
- `no-sandbox = TRUE` — 无沙盒，任意读写文件系统
- `task_for_pid-allow = TRUE` — 可以对任意进程 task_for_pid
- `proc_pidpath` / `proc_listallpids` / `sysctl(KERN_PROC_ALL)` — 进程枚举
- 直接 attach 游戏进程做 vm_read/vm_write

**TrollStore 不能给的**:
- `root` (euid=0) — 必须越狱或 kernel exploit
- `com.apple.system-task-ports` — 需要 Apple 签名
- `get-task-allow` — 需要 Apple 签名
- kernel task port — 需要 kernel exploit

**结论**: 当前走的是 **platform + no-sandbox + task_for_pid** 这条路，不是 kernel exploit 路线。RootHelper 改名叫 Helper 更准确。

**通用原则**: 做 iOS 工具首先要搞清楚自己在什么权限模型下运行。TrollStore ≠ 越狱，权限差距很大。不要用越狱思维做 TrollStore 开发。

---

## 18. libjailbreak.dylib 符号缺失诊断

**问题**: dylib 能正常 `dlopen` 加载，但 `dlsym` 查 `jb_init`、`exploit_get_kernel_task`、`kern_reading`、`kern_writing` 全部返回 NULL。

**根因**: 当前 dylib 只导出了 `physread64`、`physwritebuf`、`phystokv`、`kcall`、`kalloc` 这几个物理内存操作函数。`jb_init`（越狱环境初始化）、`exploit_get_kernel_task`（拿 kernel task port）、`kern_reading`/`kern_writing`（内核读写全局标志）这三个符号在 dylib 源码中未实现或未导出。

**实际可用 vs 缺失**:
```
可用: physread64=0x10787426c  physwritebuf=0x107873434
      phystokv=0x107874fd0    kcall=0x1078748f8
      kalloc=0x1078749c4

缺失: jb_init=0x0  exploit_get_kernel_task=0x0
      kern_reading=0x0  kern_writing=0x0
```

**影响**: 内核 exploit 路线不可用，但 `platform + task_for_pid` 路线正常。游戏进程 attach、vm_read、偏移扫描都正常工作。

**解决方向**: 需要在 dylib 源码中实现：
- `jb_init()` — 执行内核 exploit，获取 kernel task port，成功后设置 `kern_reading=1`、`kern_writing=1`
- `exploit_get_kernel_task()` — 返回 kernel task port（用于 kcall 内存操作）

**通用原则**: 先验证 dylib 导出符号是否完整再追其他问题。`dlopen` 成功 ≠ 符号完整。用 `dlsym` + NULL 检查每个关键函数指针。

---

## 19. GWorld 扫描失败 — vm_region 段检测完全不可靠

**问题**: 日志显示：
```
Segments: TEXT=0x100c54000-0x11e3cc000 DATA=0x111030000-0x111038000
GWorld scan: no high-confidence candidate (best refs=0)
```
TEXT 段 480MB（不可能一次 `malloc` + `vm_read_overwrite`），DATA 段只有 0x5000 字节（根本不是真正的数据段），扫描必然失败。

**根因**: `vm_region_64` 遍历 VM 区域时有三个致命缺陷：

1. **TEXT 被无限扩展**: 代码找到第一个可执行区域后，把之后遇到的所有可执行区域都合并进 TEXT 范围。这会把 dyld shared cache（系统库）的地址也吞进去，导致 TEXT 膨胀到几百 MB。

2. **DATA 只取第一个可写区域**: iOS 进程内存布局中，第一个可写非可执行区域通常是 `__AUTH_CONST` 或 `__DATA_CONST`（只有几 KB），真正的 `__DATA`/`__BSS` 在更后面。只取第一个就漏掉了真正的数据段。

3. **单次 `malloc` 整个 TEXT**: 即使 TEXT 只有 200MB，iOS 进程的 malloc 也大概率失败。

**正确的是两种方案**：

### 方案 A: 解析 Mach-O header（推荐，精确快速）

不走 vm_region 遍历，直接读游戏二进制 Mach-O header 里的 `LC_SEGMENT_64` 命令：

```c
static BOOL find_segments(mach_port_t task, uint64_t gameBase,
                           uint64_t *text_start, uint64_t *text_end,
                           uint64_t *data_starts, uint64_t *data_ends,
                           int *data_count, int max_data) {
    struct mach_header_64 mh;
    scan_read(task, gameBase, &mh, sizeof(mh));

    int64_t slide = gameBase - text_seg.vmaddr;  // ASLR slide 对所有段一样

    for (each LC_SEGMENT_64 cmd) {
        uint64_t seg_start = seg.vmaddr + slide;
        if (segname == "__TEXT") { text_start, text_end }
        if (segname == "__DATA" || "__BSS" || "__DATA_CONST"...) {
            data_starts[i] = seg_start;  // 收集所有数据段
        }
    }
}
```

**关键点**:
- `seg.vmaddr` 是编译时地址，运行时地址 = `vmaddr + slide`
- slide = `gameBase - __TEXT.vmaddr`，一次性算出来，所有段通用
- `__DATA`、`__BSS`、`__DATA_CONST`、`__DATA_DIRTY`、`__AUTH_CONST` 全部收集，不遗漏

### 方案 B: DATA 段指针扫描（比 ADRP+LDR 更快更可靠）

有了精确的 DATA/BSS 段范围后，直接扫描这些段中存储的指针值，找 UWorld 对象：

```
遍历 DATA/BSS 中每 8 字节:
  读 candidate = *(addr)
  if candidate 不在堆范围 → 跳过
  读 *(candidate) → vtable_ptr
  if vtable_ptr 不在 TEXT 段 → 跳过（不是 UObject）
  读 *(candidate + 0x30) → PersistentLevel
  if PersistentLevel 不合法 → 跳过
  读 *(PersistentLevel + 0x98) → Actors数组 + count
  if count 在 1..5000 范围 → 找到 GWorld！
```

**为什么比 TEXT ADRP+LDR 扫描好**:
- DATA/BSS 段通常 20-80MB，远小于 TEXT（200-400MB）
- 验证链非常强（vtable + PersistentLevel + Actors），几乎不会误报
- 即使 GWorld 不在 DATA 而在 BSS（零初始化全局变量），也能扫到

### 方案 C: 分块 TEXT ADRP+LDR 扫描（兜底）

如果 DATA 扫描也没找到，对 TEXT 做分块 ADRP+LDR：

```c
for (chunk_start = text_start; chunk_start < text_end; ) {
    // 读 64KB
    vm_read_overwrite(task, chunk_start, 0x10000, buf, &outSize);
    // 逐指令检查 ADRP + LDR (Rn == Rd)
    // 解码目标地址，检查是否在 DATA 段
    // 缓存目标地址做引用计数（相同目标被 3+ 个函数引用 → GWorld）
    chunk_start += 0x10000 - 8;  // 重叠 8 字节防指令跨块
}
```

**关键防护**:
- **限制扫描范围**: TEXT > 120MB 时只扫前 120MB（引擎代码集中在前面）
- **最后一帧防死循环**: `chunk <= 8` 时直接 break，不执行 `chunk_start += chunk - 8`
- **内存泄漏**: goto 跳过早退前先 `free(buf)`

### 三层策略执行顺序

```
scan_all_offsets()
  ├─ Step 1: find_segments() Mach-O 解析 — 拿到精确段范围
  ├─ Step 2: scan_gworld_in_data() — 扫描 DATA/BSS 找 UWorld 指针
  │    └─ 强验证链: vtable∈TEXT → PersistentLevel → Actors(1..5000)
  ├─ Step 3: scan_gworld_text_chunked() — 策略 B 失败时跑 ADRP+LDR
  │    └─ 64KB 分块, 最大 120MB, 局部引用计数 >= 3
  └─ 全失败 → 返回 -2 → GameHooks 用硬编码偏移兜底
```

**通用原则**:
1. **永远不要相信 `vm_region_64` 能给你正确的段范围**。它遍历的是 VM 内核视图，不是 Mach-O 逻辑段。dyld shared cache 的映射、submap 碎片都会让它产生垃圾结果。
2. **Mach-O header 是事实来源**。游戏二进制就在内存里，直接读 header 解析 `LC_SEGMENT_64` 拿到的是编译器生成的精确段布局。
3. **单次 `malloc` 整个 TEXT 段必然失败**。iOS 进程内存限制 + 碎片化，超过 100MB 的 malloc 就要用分块读。
4. **不要只搜一种模式**。ADRP+LDR 只是 UE4 访问全局变量的一种方式，MOVZ+MOVK、ADRP+ADD 也有可能。多策略 fallback 是唯一可靠的方案。
5. **GWorld 的 DATA 段指针扫描比 TEXT 扫描更优**——数据量小一个数量级，验证条件强，应该作为首选策略。

---

## 21. iOS Mach-O 段布局导致 GWorld 扫描全部失败

**问题**: GWorld 扫描同时失败：
```
GWorld not found in DATA segments 
GWorld TEXT scan: no candidate with >=3 refs (best=0, pairs=0)
```

两套策略都找不到任何候选——根本原因是假设 macOS/Linux 的段布局，忽略了 iOS 的关键差异。

**根因**:

### iOS 段布局(Apple Clang) vs macOS/Linux (GCC/Clang):

```
Apple Clang (iOS):
  __TEXT            → 纯代码, 不含 vtable
  __DATA_CONST      → C++ vtables + GOT entries (只读)
  __AUTH_CONST      → arm64e 签名 vtables + GOT (只读)
  __DATA            → 可写全局变量
  __BSS             → 零初始化全局变量 (GWorld 可能在这里)

GCC/Linux Clang:
  __TEXT / .text    → 代码 + vtable (部分编译器放这里)
  __DATA / .data    → 全局变量 + vtable
  __BSS / .bss       → 零初始化全局变量
```

### 三个致命假设:

1. **Vtable ∈ TEXT (错误)**: 原来检查 `vtable < text_start || vtable >= text_end` 要求 vtable 在 **TEXT** 段。但 iOS 上 C++ vtable 在 __DATA_CONST 或 __AUTH_CONST。这导致 **所有真正的 UE4 UObject 都被拒绝**。

2. **ADRP+LDR 直接引用全局变量 (不完整)**: macOS/Linux 上 `ADRP X, #page; LDR X, [X, #off]` 直接加载全局变量地址。但 iOS 使用 **GOT 间接访问**: `ADRP+LDR` → GOT entry (**__DATA_CONST**) → 全局变量地址 (**__DATA/BSS**) → 堆指针。原来的扫描只做一级间接，GOT entry 值(指向 DATA/BSS)被 `is_valid_heap_ptr()` 拒绝。

3. **所有数据段混在一起 (粗粒度)**: __DATA_CONST、__AUTH_CONST、__DATA、__BSS、__DATA_DIRTY 全放入同一个数组,无法区分只读常量(vtable/GOT)和可写全局变量(GWorld)。

### 修复:

**Segment 分类**:
```c
// 区分三种段类型
find_segments() {
    if (segname == "__TEXT")                     → text_start/end
    if (segname == "__DATA_CONST" || "__AUTH_CONST") → const_starts/ends (只读)
    if (segname == "__DATA" || "__BSS" || "__DATA_DIRTY") → data_starts/ends (可写)
}
```

**Vtable 验证**允许 TEXT + 只读常量段:
```c
BOOL is_valid_vtable(vtable) {
    if (vtable ∈ __TEXT) return YES;
    if (vtable ∈ __DATA_CONST) return YES;   // ← iOS 关键!
    if (vtable ∈ __AUTH_CONST) return YES;   // ← arm64e 关键!
    return NO;
}
```

**GOT 间接处理**:
```c
// ADRP+LDR target 在 __DATA_CONST → GOT entry
// 读 GOT entry → 全局变量地址 → 读全局变量 → 堆指针
if (target ∈ const_segments) {
    got_value = *target;              // GOT entry → &GWorld
    if (got_value ∈ data_segments)    // &GWorld 在 DATA/BSS
        pointed = *got_value;         // *GWorld → UWorld* (heap)
}
```

**新增指令模式**:
- ADRP+ADD+LDR: 编译器有时在 ADRP 和 LDR 之间插入 ADD 做页面内偏移
- MOVZ+MOVK+LDR: 某些情况下编译器用绝对地址构建 + LDR

**通用原则**:
1. **iOS 和 macOS 的 Mach-O 段布局不同**。Apple Clang 把 C++ vtable 放在 __DATA_CONST（有时是 __AUTH_CONST），不在 __TEXT。
2. **iOS 使用 GOT 做位置无关代码**。全局变量访问走 GOT 间接(两跳: GOT→var_addr→value)，不是直接 ADRP+LDR→value。
3. **区分只读段和可写段是关键**。只读段包含 vtable + GOT；可写段包含 GWorld 等全局变量。混在一起会同时破坏两种扫描策略。
4. **多指令模式覆盖**。编译器对同一个逻辑可能生成不同指令序列(ADRP+LDR、ADRP+ADD+LDR、MOVZ+MOVK+LDR)，每种都可能被用于访问 GWorld。漏一种模式=漏掉整个扫描。

---

## 22. is_valid_vtable 拒绝 __DATA 段中的 vtable

**问题**: 游戏二进制 `const=0`（无 __DATA_CONST/__AUTH_CONST 段），所有 C++ vtable 在 `__DATA`（可写段）。`is_valid_vtable` 只检查 TEXT + CONST 段, 导致全部 vtable 被拒绝, DATA 扫描零结果。

**根因**: 部分游戏用旧版 Xcode 或自定义编译, 不区分 __DATA 和 __DATA_CONST。Vtable 与全局变量混在同一个可写段中。原检查:
```c
// 旧: 只允许 TEXT + CONST
if (vtable in TEXT) return YES;
if (vtable in CONST) return YES;
return NO;
// → 所有在 __DATA 的 vtable 被拒绝
```

**修复**: vtable 可以在任何 Mach-O 映射段内 (TEXT/DATA_CONST/AUTH_CONST/DATA), 只要不在堆上:
```c
BOOL is_valid_vtable(vtable, ...) {
    if (vtable & 0x7) return NO;
    // 堆范围检查优先 — vtable 不应该在堆上
    if (vtable < 0x100000000 || vtable >= 0x200000000) return NO;
    // 任何 Mach-O 段都可以
    if (vtable in TEXT) return YES;
    if (vtable in CONST) return YES;
    if (vtable in DATA) return YES;  // ← 新增
    return NO;
}
```

**通用原则**: 不要假设编译器行为。Vtable 位置取决于 Xcode 版本、编译标志、架构。唯一可靠的判断：vtable 在 Mach-O 映射的静态段中(任何段), 绝不在堆上。

---

## 23. DATA 扫描超时 — 68MB × vm_read_overwrite = 23秒+

**问题**: 68.6MB writable DATA 段, 用 64KB 分块 vm_read_overwrite 扫描, ~1100 次跨进程内存读取, 每次 1-20ms, 总耗时 15-25 秒。iOS 后台任务限制 ~25 秒, 扫描经常超时被杀。

**日志特征**: 扫描开始但从未看到 "GWorld found" 或 "not found" — 说明扫描循环被系统杀死前没结束:
```
19:04:06 Scanning writable region 0: 0x11523c000-0x1196dc000 (68.6MB)
19:04:29 后台任务即将超时
```

**修复**: 添加硬性时间限制:
```c
double deadline = CACurrentMediaTime() + 15.0;
for (...) {
    if (CACurrentMediaTime() > deadline) {
        HOOKS_LOG(@"deadline reached at %.1f%%", ...);
        goto done;  // 提前退出, 用当前 best_addr
    }
    // ... continue scanning
}
```

**为什么 15 秒**: 后台任务限制 ~25 秒, 15 秒截止给后续的 TEXT 扫描和 GName 扫描留余量。

**通用原则**: 跨进程内存扫描 (vm_read_overwrite) 不是免费的。每个 64KB 读取都是 Mach IPC roundtrip。扫描大数据段时必须加时间限制, 否则在后台任务环境中必然超时。

---

## 24. HUD 横竖屏坐标 — Stocks (竖屏) vs 游戏 (横屏)

**问题**: Stocks app 只支持竖屏, `[UIScreen mainScreen].bounds` 始终返回 820×1180。但三角洲行动是横屏游戏。HUD 窗口 frame 和 CAMetalLayer drawableSize 都是竖屏尺寸, 在横屏游戏上显示时:
- 窗口被旋转/裁剪到横屏空间
- ImGui 菜单绘制在竖屏坐标系(0,0,820,1180), 但实际显示区域是横屏(0,0,1180,820)
- 悬浮球位置可能在屏幕外或比例严重失真

**日志证据**:
```
Screen: 820x1180 scale=2.0   ← 竖屏, 但游戏是横屏
```

**修复**: `syncCurrentOrientation` 检测设备物理方向, 横屏时交换宽高:
```objc
UIDeviceOrientation dev = [[UIDevice currentDevice] orientation];
BOOL isLandscape = (dev == UIDeviceOrientationLandscapeLeft ||
                    dev == UIDeviceOrientationLandscapeRight);
if (isLandscape && screenWidth < screenHeight) {
    swap(screenWidth, screenHeight);  // 820×1180 → 1180×820
}
// 同时更新 gMetalLayer.frame 和 drawableSize
```

并在退后台前 (`UIApplicationWillResignActiveNotification`) 调用同步, 确保进入游戏时 HUD 已是横屏尺寸。

**通用原则**: SBS 窗口的 frame 使用物理屏幕坐标系, 不是 app 的 UI 坐标系。如果 app 和设备/目标 app 方向不一致, 必须手动处理方向差异。`UIScreen.bounds` 反映的是当前 app 的方向, 不一定等于物理屏幕方向。

---

## 20. GWorld 扫描误报 — 验证链太弱导致假阳性

**问题**: 扫描成功返回 `GWorld found in DATA: addr=0x110ea33a0 -> UWorld=0x110ea3360 score=56`，但实际是假阳性：

```
vtable=0x10eeaa362   ← 不是 8 字节对齐！(0x362 & 7 = 2)
plevel=0x110ea3350   ← UWorld - 16，不可能
actors=0x10eeaa57f   ← 在 TEXT 段且不对齐
UWorld=0x110ea3360   ← 在 __DATA 段内，不是堆
```

**根因**: 验证链只检查了"数值在合理地址范围内"，没有检查三个关键约束：

1. **ARM64 指针必须 8 字节对齐** — `addr & 0x7 == 0` 是硬件要求，不合规的一定不是指针
2. **UWorld/PersistentLevel/Actors 必须在真正的堆上** — 不在 TEXT（代码段），也不在 DATA/BSS（静态数据段）。UE4 shipping build 中 UWorld 是 `NewObject<>()` 分配的，一定在堆上
3. **只跑了一个策略就相信结果** — DATA 扫描找到了 actors_count=56 就 `goto done` 早退，没有等 TEXT ADRP+LDR 交叉验证

**修复**:

### A. 强化地址验证

```c
// 旧: 只检查范围
BOOL is_valid_heap_ptr(addr) {
    return addr > 0x100000000 && addr < 0x200000000;
}

// 新: 范围 + 对齐
BOOL is_valid_heap_ptr(addr) {
    return addr > 0x100000000 && addr < 0x200000000 && (addr & 0x7) == 0;
}

// 新增: 排除 TEXT/DATA 段的真正堆检查
BOOL is_real_heap(addr, text_start, text_end, data_starts, data_ends, data_count) {
    if (addr >= text_start && addr < text_end) return NO;  // 不在代码段
    for (int i = 0; i < data_count; i++)
        if (addr >= data_starts[i] && addr < data_ends[i]) return NO;  // 不在数据段
    return is_valid_heap_ptr(addr);
}
```

### B. 全部指针走严格验证

```c
// vtable: 对齐 + TEXT 段范围
if (vtable & 0x7) continue;

// UWorld/PersistentLevel/Actors: 必须在真正堆上
if (!is_real_heap(candidate, ...)) continue;
if (!is_real_heap(plevel, ...)) continue;
if (!is_real_heap(actors_ptr, ...)) continue;
```

### C. 双策略交叉验证

```
scan_all_offsets():
  data_result = scan_gworld_in_data()    // 策略 A
  text_result = scan_gworld_text_chunked() // 策略 B (独立跑，不等 A 失败)
  
  if (data_result == text_result) → 高置信度，双策略一致
  if (data_result != text_result) → 取 TEXT 结果（ADRP+LDR 比纯指针扫描可靠）
  if (仅 text_result)              → 取 TEXT 结果
  if (仅 data_result)              → 标记"未验证"，保守使用
```

**为什么 TEXT ADRP+LDR 比 DATA 指针扫描更可靠**:
- ADRP+LDR 是编译器生成的指令模式，不是内存数据。指令不会"碰巧"形成有效的 ADRP+LDR 对
- 引用计数（同一个全局变量被多个函数引用）是天然的去重机制
- 而 DATA 段中的随机数据碰巧看起来像"UWorld→PersistentLevel→Actors"的可能性虽然低，但在扫描数千万个指针时总会遇到

**通用原则**:
1. **指针不是只有范围检查就够了**。ARM64 指针必须 8 字节对齐；堆指针不能在 Mach-O 映射的段内；不同的段有不同的地址范围
2. **单一验证链一定会有假阳性**。68MB 数据段 = 890 万个 uint64。即使只有 0.01% 碰巧通过验证，也是 890 个假候选
3. **交叉验证是免费的可靠性提升**。两个独立策略结果一致 → 置信度趋近 100%；不一致 → 至少知道有问题的
4. **不要找到第一个高置信度候选就早退**。跑完所有策略再决策，`goto done` 省的时间远不如误报浪费的时间
