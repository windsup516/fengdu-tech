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
