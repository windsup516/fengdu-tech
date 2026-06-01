#!/usr/bin/env python3
"""下载 CJK 字体到 Resources/ 目录 — 用于 CI/CD 环境
   Windows 本地直接用系统字体 (msyh.ttc)，此脚本为 macOS/Linux CI 提供字体下载"""

import sys
import os
import urllib.request

# 思源黑体 SC Regular — Adobe 官方 GitHub (~8MB OTF)
FONT_URLS = [
    "https://github.com/adobe-fonts/source-han-sans/raw/release/OTF/SimplifiedChinese/SourceHanSansSC-Regular.otf",
    "https://raw.githubusercontent.com/adobe-fonts/source-han-sans/release/OTF/SimplifiedChinese/SourceHanSansSC-Regular.otf",
    "https://github.com/googlefonts/noto-cjk/releases/download/Sans2.004/03_NotoSansCJKsc.zip",
]

RESOURCES_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Resources")
OUTPUT_FILE = os.path.join(RESOURCES_DIR, "CJKFont.otf")  # 用 .otf 避免 TTC 兼容问题

def download_font():
    os.makedirs(RESOURCES_DIR, exist_ok=True)

    # 如果已存在且足够大, 跳过
    if os.path.exists(OUTPUT_FILE) and os.path.getsize(OUTPUT_FILE) > 5_000_000:
        print(f"Font already exists: {OUTPUT_FILE} ({os.path.getsize(OUTPUT_FILE) / 1_000_000:.1f} MB)")
        return True

    for url in FONT_URLS:
        try:
            print(f"Downloading: {url}")
            req = urllib.request.Request(url, headers={
                'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'
            })
            with urllib.request.urlopen(req, timeout=180) as resp:
                data = resp.read()
                size_mb = len(data) / (1024 * 1024)
                print(f"Downloaded: {size_mb:.1f} MB")
                with open(OUTPUT_FILE, 'wb') as f:
                    f.write(data)
                return True
        except Exception as e:
            print(f"  Failed: {e}")
            continue

    print("All URLs failed!")
    return False

if __name__ == '__main__':
    success = download_font()
    sys.exit(0 if success else 1)
