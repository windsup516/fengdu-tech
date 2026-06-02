#!/bin/bash
set -e

# ============================================================
# DeltaForce TrollKit — macOS 一键构建脚本
# 在朋友的 Mac 上运行这个脚本即可完成全部环境配置 + 编译
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
die()  { echo -e "${RED}[X]${NC} $1"; exit 1; }

echo "============================================"
echo " DeltaForce TrollKit — macOS Build Setup"
echo "============================================"
echo ""

# ============================================================
# Step 1: 检查基本环境
# ============================================================
log "Step 1/6: 检查 Xcode Command Line Tools..."

if ! xcode-select -p &>/dev/null; then
    log "安装 Xcode Command Line Tools..."
    xcode-select --install
    warn "请在弹出的对话框中点击'安装'，安装完成后按回车继续..."
    read -r
fi
log "Xcode CLT: OK"

# ============================================================
# Step 2: 检查/安装 Homebrew (用于下载工具)
# ============================================================
log "Step 2/6: 检查 Homebrew..."

if ! which brew &>/dev/null; then
    log "安装 Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    # Apple Silicon Mac 需要设置 PATH
    if [ -f /opt/homebrew/bin/brew ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
fi
log "Homebrew: OK"

# ============================================================
# Step 3: 安装 Theos 构建系统
# ============================================================
log "Step 3/6: 安装 Theos..."

THEOS_DIR="/tmp/theos"
if [ -d "$THEOS_DIR" ]; then
    log "Theos 已存在，更新..."
    cd "$THEOS_DIR"
    git pull --depth 1 2>/dev/null || true
else
    log "克隆 Theos..."
    git clone --depth 1 --recursive https://github.com/theos/theos.git "$THEOS_DIR"
fi

# 安装 ldid (用于 TrollStore 伪签名)
LDID_URL="https://github.com/ProcursusTeam/ldid/releases/download/v2.1.5-procursus7/ldid_macosx_x86_64"
ARM_LDID_URL="https://github.com/ProcursusTeam/ldid/releases/download/v2.1.5-procursus7/ldid_macosx_arm64"

# 检测架构
if [ "$(uname -m)" = "arm64" ]; then
    LDID_URL="$ARM_LDID_URL"
fi

if [ ! -f "$THEOS_DIR/bin/ldid" ]; then
    log "下载 ldid..."
    curl -L --retry 5 --retry-delay 5 -o "$THEOS_DIR/bin/ldid" "$LDID_URL"
    chmod +x "$THEOS_DIR/bin/ldid"
fi

# 去掉 quarantine 标记
xattr -d com.apple.quarantine "$THEOS_DIR/bin/ldid" 2>/dev/null || true

log "Theos + ldid: OK"
echo "  Theos: $THEOS_DIR"
echo "  ldid:  $($THEOS_DIR/bin/ldid --version 2>&1 || echo 'v2.1.5')"

# ============================================================
# Step 4: 下载 iPhoneOS SDK
# ============================================================
log "Step 4/6: 下载 iPhoneOS 16.5 SDK..."

SDK_DIR="$THEOS_DIR/sdks"
SDK_FILE="iPhoneOS16.5.sdk.tar.xz"
SDK_PATH="$SDK_DIR/iPhoneOS16.5.sdk"
mkdir -p "$SDK_DIR"

if [ ! -d "$SDK_PATH" ]; then
    if [ ! -f "$SDK_DIR/$SDK_FILE" ]; then
        log "下载 SDK (约 500MB，请耐心等待)..."
        curl -L --retry 5 --retry-delay 10 \
            -o "$SDK_DIR/$SDK_FILE" \
            "https://github.com/theos/sdks/releases/download/master-146e41f/iPhoneOS16.5.sdk.tar.xz"
    fi
    log "解压 SDK..."
    tar -xJf "$SDK_DIR/$SDK_FILE" -C "$SDK_DIR/"
fi
log "SDK: OK ($SDK_PATH)"

# ============================================================
# Step 5: 下载中文字体
# ============================================================
log "Step 5/6: 下载中文字体..."

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESOURCES_DIR="$SCRIPT_DIR/Resources"
mkdir -p "$RESOURCES_DIR"

if [ ! -f "$RESOURCES_DIR/CJKFont.otf" ] && [ ! -f "$RESOURCES_DIR/CJKFont.ttc" ]; then
    log "下载思源黑体 (约 20MB)..."
    curl -L --retry 5 --retry-delay 10 \
        -o "$RESOURCES_DIR/CJKFont.otf" \
        "https://github.com/adobe-fonts/source-han-sans/raw/release/OTF/SimplifiedChinese/SourceHanSansSC-Regular.otf"
    log "字体下载完成"
else
    log "字体已存在"
fi
ls -lh "$RESOURCES_DIR/"

# ============================================================
# Step 6: 编译项目
# ============================================================
log "Step 6/6: 编译 DeltaForce TrollKit..."

cd "$SCRIPT_DIR"
export THEOS="$THEOS_DIR"
export PATH="$THEOS_DIR/bin:$PATH"

log "清理旧构建..."
make clean 2>/dev/null || true

log "开始编译 (make package)..."
make package FINAL_PACKAGE=1

echo ""
echo "============================================"
echo " 构建完成！"
echo "============================================"

# 查找输出的 .tipa
TIPA=$(find "$SCRIPT_DIR" -name "Stocks.tipa" -type f 2>/dev/null | head -1)
if [ -z "$TIPA" ]; then
    # 可能在 packages/ 目录
    TIPA="$SCRIPT_DIR/packages/Stocks.tipa"
fi

if [ -f "$TIPA" ]; then
    SIZE=$(du -sh "$TIPA" | awk '{print $1}')
    log "输出文件: $TIPA"
    log "文件大小: $SIZE"
    echo ""
    log "把这个 Stocks.tipa 发给对方："
    echo ""
    echo "  1. 在 iPhone 上打开 TrollStore"
    echo "  2. 点击 + 号"
    echo "  3. 选择 Stocks.tipa"
    echo "  4. 点击 Install"
    echo ""
else
    warn "未找到 Stocks.tipa，检查编译输出..."
    echo "  THEOS_STAGING_DIR 内容："
    ls -la "$THEOS_DIR/.theos/" 2>/dev/null || echo "  (无 .theos 目录)"
    echo ""
    echo "  项目目录："
    ls -la "$SCRIPT_DIR/" 2>/dev/null
fi
