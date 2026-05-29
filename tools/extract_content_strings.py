#!/usr/bin/env python3
"""One-shot tool. Run from repo root:

    python3 tools/extract_content_strings.py

扫描 resources/data/ 下所有 .tres, 抽取每个含中文 (CJK) 的双引号字符串字面量,
去重后写进 resources/i18n/content.csv。这是游戏内容文案的翻译源 (源中文串当 key,
见 design/国际化设计.md §2bis)。

为什么源串当 key: .tres 共 ~180 份, 显示处只需把读取包一层 tr(card.title) 即可,
.tres 一行都不用改。zh 永远正确 (查不到返回 key 自身=中文), content.csv 只需 en 列。

合并语义 (重要, 见 memory event-card-generator-drift): 重跑时**保留** content.csv 里
已填好的 en。流程: 读旧 content.csv → 扫当前 .tres → 输出 = 当前所有 key, 已有 key
沿用旧 en, 新 key 留空 en, .tres 里已删除的 key 丢弃。所以重跑不会抹掉我手填的译文,
只会同步 key 集合。

CSV 规范: 列 keys,en; 标准 CSV 转义 (Python csv 模块处理逗号/引号); key 即中文原串。
"""

import csv
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA_DIR = os.path.join(REPO, "resources", "data")
OUT_CSV = os.path.join(REPO, "resources", "i18n", "content.csv")

# 匹配一个双引号字符串字面量 (支持 \" 转义)。
_STR_RE = re.compile(r'"((?:[^"\\]|\\.)*)"')
# 含至少一个 CJH 汉字 → 判定为需要翻译的 prose 串。标点/英文 codename 不会命中。
_CJK_RE = re.compile(r"[一-鿿]")


def _iter_tres(root):
    for dirpath, _dirs, files in os.walk(root):
        for name in sorted(files):
            if name.endswith(".tres"):
                yield os.path.join(dirpath, name)


def _extract_from_file(path):
    out = set()
    with open(path, encoding="utf-8") as f:
        for line in f:
            for m in _STR_RE.finditer(line):
                s = m.group(1)
                if _CJK_RE.search(s):
                    out.add(s)
    return out


def _load_existing(path):
    """旧 content.csv → {key: en}, 保留人工填的 en。"""
    existing = {}
    if not os.path.exists(path):
        return existing
    with open(path, encoding="utf-8", newline="") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        for row in reader:
            if not row or not row[0]:
                continue
            existing[row[0]] = row[1] if len(row) > 1 else ""
    return existing


def main():
    keys = set()
    for tres in _iter_tres(DATA_DIR):
        keys |= _extract_from_file(tres)

    existing = _load_existing(OUT_CSV)
    rows = sorted(keys)

    preserved = 0
    new = 0
    with open(OUT_CSV, "w", encoding="utf-8", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["keys", "en"])
        for key in rows:
            en = existing.get(key, "")
            if en:
                preserved += 1
            else:
                new += 1
            writer.writerow([key, en])

    dropped = [k for k in existing if k not in keys]
    print(f"content.csv: {len(rows)} keys ({preserved} with en, {new} untranslated)")
    if dropped:
        print(f"dropped {len(dropped)} stale keys no longer in .tres")
    return 0


if __name__ == "__main__":
    sys.exit(main())
