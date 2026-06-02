// RootHelper.m — TrollStore 提权辅助进程
// 由主 App 通过 posix_spawn 启动，提供跨进程内存读写能力
// 与主 App 通过 Unix Domain Socket 进行 IPC 通信
// 编译: 作为独立可执行文件 (TOOL_NAME = RootHelper)

#import <Foundation/Foundation.h>
#import <mach/mach.h>
#import <sys/sysctl.h>
#import <sys/socket.h>
#import <sys/un.h>
#import <unistd.h>
#import <signal.h>
#import <dlfcn.h>
#import <spawn.h>

#define HELPER_SOCK_PATH "/tmp/deltaforce_helper.sock"
#define GAME_PROCESS_NAME "DeltaForceClient"

static FILE *g_log = NULL;

static void helper_log(const char *fmt, ...) {
    if (!g_log) g_log = fopen("/tmp/roothelper.log", "a");
    va_list args;
    va_start(args, fmt);
    if (g_log) {
        time_t now = time(NULL);
        struct tm *t = localtime(&now);
        char tb[16];
        strftime(tb, sizeof(tb), "%H:%M:%S", t);
        fprintf(g_log, "%s [RootHelper] ", tb);
        vfprintf(g_log, fmt, args);
        fprintf(g_log, "\n");
        fflush(g_log);
    }
    va_end(args);
}

// 进程名候选
static const char *g_names[] = {
    "DeltaForceClient", "DeltaForce", "DFM", "dfm", "tmgp", "Star", "Delta", NULL
};

// === sysctl 进程枚举 ===
static pid_t find_game_pid(void) {
    // 方法1: sysctl(KERN_PROC_ALL)
    {
        int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0};
        size_t bufSize = 0;
        if (sysctl(mib, 4, NULL, &bufSize, NULL, 0) == 0 && bufSize > 0) {
            struct kinfo_proc *procs = (struct kinfo_proc *)malloc(bufSize);
            if (procs && sysctl(mib, 4, procs, &bufSize, NULL, 0) == 0) {
                int count = (int)(bufSize / sizeof(struct kinfo_proc));
                helper_log("sysctl: %d processes found", count);
                for (int i = 0; i < count; i++) {
                    const char *pname = procs[i].kp_proc.p_comm;
                    for (const char **n = g_names; *n; n++) {
                        if (strcasecmp(pname, *n) == 0) {
                            pid_t pid = procs[i].kp_proc.p_pid;
                            helper_log("Found game: %s PID=%d", pname, pid);
                            free(procs);
                            return pid;
                        }
                    }
                }
                free(procs);
            }
        } else {
            helper_log("sysctl size query failed: errno=%d", errno);
        }
    }

    // 方法2: proc_listallpids
    {
        int pidbuf[1024];
        int npids = proc_listallpids(pidbuf, sizeof(pidbuf));
        helper_log("proc_listallpids: ret=%d errno=%d", npids, errno);
        if (npids > 0) {
            for (int i = 0; i < npids; i++) {
                char pname[64] = {0};
                proc_name(pidbuf[i], pname, sizeof(pname) - 1);
                for (const char **n = g_names; *n; n++) {
                    if (strcasecmp(pname, *n) == 0) {
                        helper_log("Found game via libproc: %s PID=%d", pname, pidbuf[i]);
                        return pidbuf[i];
                    }
                }
            }
        }
    }

    return -1;
}

// === 主循环: 监听 Unix Socket ===
int main(int argc, char *argv[]) {
    helper_log("RootHelper starting (PID=%d, argc=%d)", getpid(), argc);

    // 打印环境信息
    helper_log("euid=%d uid=%d gid=%d", geteuid(), getuid(), getgid());

    // 测试1: sysctl 进程枚举
    pid_t gamePid = find_game_pid();
    if (gamePid > 0) {
        helper_log("Game PID=%d found, attempting task_for_pid...", gamePid);

        mach_port_t gameTask = MACH_PORT_NULL;
        kern_return_t kr = task_for_pid(mach_task_self(), gamePid, &gameTask);
        helper_log("task_for_pid(%d): kr=%d task=%x", gamePid, kr, gameTask);

        if (kr == KERN_SUCCESS && gameTask != MACH_PORT_NULL) {
            // 测试读游戏内存
            uint64_t testAddr = 0x100000000; // 常见的 TEXT 段基址
            uint32_t magic = 0;
            vm_size_t sz = sizeof(magic);
            kr = vm_read_overwrite(gameTask, (vm_address_t)testAddr, sz,
                                    (vm_address_t)&magic, &sz);
            helper_log("vm_read(0x%llx): kr=%d magic=0x%x", testAddr, kr, magic);

            mach_port_deallocate(mach_task_self(), gameTask);
        }

        // 同时测试自身 task_for_pid
        mach_port_t selfTask = MACH_PORT_NULL;
        kr = task_for_pid(mach_task_self(), getpid(), &selfTask);
        helper_log("task_for_pid(self): kr=%d task=%x", kr, selfTask);
        if (selfTask != MACH_PORT_NULL) {
            mach_port_deallocate(mach_task_self(), selfTask);
        }
    }

    // 测试2: 尝试 exploit_get_kernel_task
    // 动态加载 libjailbreak.dylib
    char exePath[1024];
    uint32_t sz = (uint32_t)sizeof(exePath);
    if (_NSGetExecutablePath(exePath, &sz) == 0) {
        NSString *exeStr = [NSString stringWithUTF8String:exePath];
        NSString *fwDir = [[[exeStr stringByDeletingLastPathComponent]
                           stringByDeletingPathExtension]
                          stringByAppendingPathComponent:@"Frameworks"];
        NSString *dylibPath = [fwDir stringByAppendingPathComponent:@"libjailbreak.dylib"];

        void *handle = dlopen([dylibPath UTF8String], RTLD_LAZY);
        if (handle) {
            helper_log("libjailbreak.dylib loaded in helper");

            typedef kern_return_t (*exp_kt_fn)(mach_port_t *);
            exp_kt_fn get_kt = dlsym(handle, "exploit_get_kernel_task");
            if (get_kt) {
                mach_port_t kt = MACH_PORT_NULL;
                kern_return_t kr = get_kt(&kt);
                helper_log("exploit_get_kernel_task: kr=%d task=%x", kr, kt);
                if (kt != MACH_PORT_NULL) {
                    mach_port_deallocate(mach_task_self(), kt);
                }
            }
        } else {
            helper_log("Failed to load dylib in helper: %s", dlerror());
        }
    }

    // === 启动 Unix Domain Socket 服务，等待主 App 连接 ===
    unlink(HELPER_SOCK_PATH);
    int sock = socket(AF_UNIX, SOCK_STREAM, 0);
    if (sock < 0) {
        helper_log("socket() failed: %s", strerror(errno));
        return 1;
    }

    struct sockaddr_un addr = {0};
    addr.sun_family = AF_UNIX;
    strcpy(addr.sun_path, HELPER_SOCK_PATH);

    if (bind(sock, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        helper_log("bind() failed: %s", strerror(errno));
        close(sock);
        return 1;
    }

    if (listen(sock, 1) < 0) {
        helper_log("listen() failed: %s", strerror(errno));
        close(sock);
        return 1;
    }

    helper_log("RootHelper listening on %s", HELPER_SOCK_PATH);

    // 接受连接并处理命令
    while (1) {
        int client = accept(sock, NULL, NULL);
        if (client < 0) {
            helper_log("accept() failed: %s", strerror(errno));
            break;
        }

        // 简单协议: 字符串命令，换行分隔
        char buf[1024];
        ssize_t n = read(client, buf, sizeof(buf) - 1);
        if (n > 0) {
            buf[n] = '\0';
            helper_log("Received command: %s", buf);

            // 处理 "PING" 命令
            if (strncmp(buf, "PING", 4) == 0) {
                char resp[256];
                snprintf(resp, sizeof(resp), "PONG pid=%d euid=%d\n", getpid(), geteuid());
                write(client, resp, strlen(resp));
            }
            // 处理 "FINDGAME" 命令
            else if (strncmp(buf, "FINDGAME", 8) == 0) {
                pid_t pid = find_game_pid();
                char resp[64];
                snprintf(resp, sizeof(resp), "GAMEPID=%d\n", pid);
                write(client, resp, strlen(resp));
            }
            // 处理 "READ pid addr size" 命令
            else if (strncmp(buf, "READ ", 5) == 0) {
                int pid = 0;
                uint64_t addr = 0;
                int size = 0;
                sscanf(buf, "READ %d %llx %d", &pid, &addr, &size);

                mach_port_t task = MACH_PORT_NULL;
                kern_return_t kr = task_for_pid(mach_task_self(), pid, &task);
                if (kr == KERN_SUCCESS && task != MACH_PORT_NULL && size > 0 && size <= 4096) {
                    uint8_t data[4096];
                    vm_size_t outSz = (vm_size_t)size;
                    kr = vm_read_overwrite(task, (vm_address_t)addr, (vm_size_t)size,
                                           (vm_address_t)data, &outSz);
                    if (kr == KERN_SUCCESS) {
                        char resp[32];
                        snprintf(resp, sizeof(resp), "OK %zu bytes\n", (size_t)outSz);
                        write(client, resp, strlen(resp));
                        write(client, data, outSz);
                    } else {
                        char resp[64];
                        snprintf(resp, sizeof(resp), "ERR vm_read kr=%d\n", kr);
                        write(client, resp, strlen(resp));
                    }
                    mach_port_deallocate(mach_task_self(), task);
                } else {
                    char resp[64];
                    snprintf(resp, sizeof(resp), "ERR task_for_pid(%d) kr=%d\n", pid, kr);
                    write(client, resp, strlen(resp));
                }
            }
        }
        close(client);
    }

    close(sock);
    unlink(HELPER_SOCK_PATH);
    helper_log("RootHelper exiting");
    return 0;
}
