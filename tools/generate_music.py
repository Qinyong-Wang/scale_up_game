#!/usr/bin/env python3
"""Generate long instrumental BGM via Replicate MusicGen.

一次性资产工具 (见 CLAUDE.md tools/ 约定)。用 Replicate 的 meta/musicgen 一次性生成
约 3.5 分钟的**连续**纯乐器曲 (自回归单段生成, 无拼接 → 无「切歌」接缝), 再用 ffmpeg
烘焙首尾淡入淡出并编码 MP3 (Godot 4.3 原生支持), 落到 assets/audio/music/。

真实模型名只出现在本工具里 (开发期生成), 不进游戏运行时代码 / UI 文案 (化名规范)。

鉴权复用美术工具的 token: 环境变量 REPLICATE_API_TOKEN 或 tools/art/.env。
依赖: ffmpeg / ffprobe (brew install ffmpeg) + replicate 库 (装在 tools/art/.venv)。
**必须用美术 venv 跑** (系统 python 无 replicate 库; 且 raw urllib 会被 Cloudflare
1010 拦, 必须走 replicate 库):
    tools/art/.venv/bin/python tools/generate_music.py [...]

用法:
    tools/art/.venv/bin/python tools/generate_music.py --list        # 曲目清单
    tools/art/.venv/bin/python tools/generate_music.py --only bgm_01  # 单首(验证)
    tools/art/.venv/bin/python tools/generate_music.py               # 全部(并发)
    tools/art/.venv/bin/python tools/generate_music.py --duration 180 # 覆盖时长(秒)

成本: 按 Replicate GPU 秒计费; musicgen stereo-large 出 ~210s 单首约几美分~一两毛。
"""

import argparse
import os
import shutil
import subprocess
import sys
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

import replicate  # 装在 tools/art/.venv; 必须用该 venv 的 python 跑本脚本

HERE = Path(__file__).resolve().parent
REPO = HERE.parent
OUT_DIR = REPO / "assets" / "audio" / "music"
ENV_FILE = HERE / "art" / ".env"  # 复用美术工具的 REPLICATE_API_TOKEN

MODEL = "meta/musicgen"
MODEL_VERSION = "stereo-large"   # 纯文生乐 (无 melody 条件), 立体声大模型
DURATION = 210                   # 秒 (~3.5 分钟)
FADE_SEC = 2.5                   # 首尾淡入 / 淡出
MP3_QUALITY = 4                  # libmp3lame -q:a (≈165kbps VBR)
WORKERS = 5                      # 并发生成数 (Replicate 端并行跑)

# 三种风格基调, 全部纯乐器无人声, 经营模拟向, 可循环。
# (A) 电子科技: 现有 bgm_01..15, 轻松合成器 / lo-fi / techno。
_BASE_ELECTRONIC = ("calm relaxing instrumental background music for a business "
         "management simulation game, electronic and techy, soft synths, no vocals, "
         "no drums heavy, smooth and steady, loopable")
# (B) 原声有机: bgm_16..27, 钢琴 / 弦乐 / 原声吉他 / 世界乐器, 温暖柔和, 与电子曲反差。
_BASE_ORGANIC = ("calm relaxing instrumental background music for a business "
         "management simulation game, warm organic acoustic instruments, no vocals, "
         "gentle soothing and intimate, smooth and steady, loopable")
# (C) 磅礴混合: bgm_28..31, 电影感管弦 (弦乐 / 铜管) 叠合成器与节奏, 用于大场面。
_BASE_EPIC = ("grand cinematic instrumental music for a business management "
         "simulation game, epic and majestic, orchestral strings and brass blended "
         "with synths, building and triumphant, no vocals, powerful")

# 各一种气质 (调性 / 速度 / 音色不同), 但落在各自基调内。
# 注: bgm_01/02/03/05/07/08/11/12 试听后删除 (低质), 编号留空档不复用。
_MOODS_ELECTRONIC = {
    "bgm_04": "deep minimal techno, steady hypnotic pulse, clean and futuristic",
    "bgm_06": "clean corporate tech, light and productive, optimistic",
    "bgm_09": "reflective minimal piano with soft synth pad, calm",
    "bgm_10": "soft future garage, gentle shuffled rhythm, airy",
    "bgm_13": "steady motivational electronica, gently driving, upbeat but calm",
    "bgm_14": "mellow night-city synthwave, smooth, laid back",
    "bgm_15": "light intricate IDM, delicate glitchy textures, gentle",
}
# 12 首原声有机, 轻松平静但音色偏原声 (与电子曲反差)。
_MOODS_ORGANIC = {
    "bgm_16": "solo grand piano, soft and reflective, spacious reverb, slow tempo",
    "bgm_17": "warm fingerstyle acoustic guitar, cozy and intimate, mellow",
    "bgm_18": "tender string quartet, hopeful, gentle slow swells",
    "bgm_19": "felt piano with subtle ambient pad, delicate and nostalgic",
    "bgm_20": "japanese koto and shakuhachi flute, serene zen garden, minimal",
    "bgm_21": "warm cello melody over light piano, heartfelt and calm",
    "bgm_22": "gentle harp and glockenspiel, dreamy and bright, lullaby-like",
    "bgm_23": "acoustic guitar and soft strings, pastoral and peaceful, mid-slow tempo",
    "bgm_24": "mellow rhodes electric piano with soft brushes, jazzy and laid back",
    "bgm_25": "classical guitar with warm woodwinds, romantic and tranquil",
    "bgm_26": "soft marimba and vibraphone, light and playful, gentle groove",
    "bgm_27": "ambient piano with airy textures, contemplative and spacious",
}
# 4 首磅礴大场面 (宇宙模拟 capstone / 重大里程碑)。
_MOODS_EPIC = {
    "bgm_28": "soaring orchestral strings and brass with pulsing synth bass, "
              "hopeful and triumphant, building to a climax",
    "bgm_29": "epic hybrid trailer score, driving cinematic percussion and synths, "
              "powerful and determined",
    "bgm_30": "majestic awe-inspiring swell, lush strings and deep brass with "
              "shimmering synth pads, vast and cosmic, slow grand build",
    "bgm_31": "heroic uplifting anthem, big orchestral hits with electronic pulse, "
              "victorious and grand",
}
TRACKS = {}
for _base, _moods in ((_BASE_ELECTRONIC, _MOODS_ELECTRONIC),
                      (_BASE_ORGANIC, _MOODS_ORGANIC),
                      (_BASE_EPIC, _MOODS_EPIC)):
    for _name, _mood in _moods.items():
        TRACKS[_name] = f"{_base}, {_mood}"


def _require(b):
    if shutil.which(b) is None:
        sys.exit(f"[error] 缺少 {b}; 请先 `brew install ffmpeg`")


def _token() -> str:
    t = os.environ.get("REPLICATE_API_TOKEN")
    if not t and ENV_FILE.exists():
        for line in ENV_FILE.read_text().splitlines():
            if line.startswith("REPLICATE_API_TOKEN="):
                t = line.split("=", 1)[1].strip()
    if not t:
        sys.exit("[error] REPLICATE_API_TOKEN 未设置 (env 或 tools/art/.env)")
    return t


_VER = {}


def _version(client) -> str:
    # meta/musicgen 是普通模型 (非 official), run() 必须 model:version, 否则走
    # official-model 端点 404。先解析最新 version id 并缓存。
    if "id" not in _VER:
        _VER["id"] = client.models.get(MODEL).latest_version.id
    return _VER["id"]


def _read_output(out) -> bytes:
    if isinstance(out, list):
        out = out[0]
    if hasattr(out, "read"):       # replicate FileOutput
        return out.read()
    req = urllib.request.Request(str(out), headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=300) as r:   # 退化为 URL 字符串
        return r.read()


def _generate_bytes(client, prompt, duration) -> bytes:
    """阻塞生成一首, 返回音频字节。"""
    out = client.run(f"{MODEL}:{_version(client)}", input={
        "prompt": prompt,
        "model_version": MODEL_VERSION,
        "duration": duration,
        "output_format": "mp3",
        "normalization_strategy": "loudness",
    })
    return _read_output(out)


def _finalize(raw_path, out_path):
    """烘焙首尾淡入淡出, 重编码为 MP3。"""
    dur = float(subprocess.check_output([
        "ffprobe", "-v", "error", "-show_entries", "format=duration",
        "-of", "default=nw=1:nk=1", raw_path]).decode().strip())
    fos = max(0.0, dur - FADE_SEC)
    af = f"afade=t=in:st=0:d={FADE_SEC},afade=t=out:st={fos:.3f}:d={FADE_SEC}"
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    subprocess.run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
                    "-i", raw_path, "-af", af,
                    "-c:a", "libmp3lame", "-q:a", str(MP3_QUALITY), out_path],
                   check=True)
    final = float(subprocess.check_output([
        "ffprobe", "-v", "error", "-show_entries", "format=duration",
        "-of", "default=nw=1:nk=1", out_path]).decode().strip())
    mb = os.path.getsize(out_path) / 1024 / 1024
    print(f"[ok] {os.path.basename(out_path)}  {final:.0f}s  {mb:.1f} MiB", flush=True)


def _make_one(client, name, duration, tmp):
    print(f"[gen] {name} …", flush=True)
    data = _generate_bytes(client, TRACKS[name], duration)
    raw = tmp / f"{name}.src.mp3"
    raw.write_bytes(data)
    _finalize(str(raw), str(OUT_DIR / f"{name}.mp3"))


def _run(names, token, duration):
    client = replicate.Client(api_token=token)
    tmp = Path(subprocess.check_output(["mktemp", "-d"]).decode().strip())
    failed = []
    try:
        with ThreadPoolExecutor(max_workers=WORKERS) as ex:
            futs = {ex.submit(_make_one, client, n, duration, tmp): n for n in names}
            for fut in as_completed(futs):
                n = futs[fut]
                try:
                    fut.result()
                except Exception as e:  # 单首失败不拖垮整批
                    print(f"[fail] {n}: {e}", flush=True)
                    failed.append(n)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    if failed:
        print(f"[warn] 失败 {len(failed)} 首: {', '.join(failed)} (可 --only 重试)", flush=True)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--list", action="store_true", help="列出曲目清单后退出")
    ap.add_argument("--only", help="只生成某一首 (bgm_01 .. bgm_31)")
    ap.add_argument("--duration", type=int, default=DURATION, help="时长(秒)")
    ap.add_argument("--force", action="store_true", help="重生成已存在的曲目 (默认跳过)")
    args = ap.parse_args()

    if args.list:
        for n, p in TRACKS.items():
            print(f"{n}: {p}")
        return

    _require("ffmpeg")
    _require("ffprobe")
    token = _token()
    names = [args.only] if args.only else list(TRACKS.keys())
    for n in names:
        if n not in TRACKS:
            sys.exit(f"[error] 未知曲目 {n!r}; 可选: {', '.join(TRACKS)}")
    if not args.force and not args.only:
        skip = [n for n in names if (OUT_DIR / f"{n}.mp3").exists()]
        if skip:
            print(f"[skip] 已存在, 跳过: {', '.join(skip)} (--force 可重生成)")
        names = [n for n in names if n not in skip]
    if not names:
        print("[done] 无需生成")
        return
    _run(names, token, args.duration)


if __name__ == "__main__":
    main()
