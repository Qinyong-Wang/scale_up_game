#!/usr/bin/env python3
"""Generate raw 2D UI image assets via Replicate, then (optionally) post-process.

一次性资产工具 (见 CLAUDE.md tools/ 约定 + design/图片素材生成流程.md): 调用
Replicate 上的文生图模型, 按内置批次的 subject + 统一 style 前缀出图, 把 raw PNG
(纯洋红底) 写进 tools/art/runs/<label>/raw.png, 再交给 process_asset.py 去背 /
裁切 / 居中。真实模型名只出现在本工具里 (开发期生成), 不进游戏运行时 / UI 文案,
符合化名规范。

鉴权 (任选其一, 不要把 token 提交进 git):
    export REPLICATE_API_TOKEN=r8_xxx          # 进程环境变量
    echo 'REPLICATE_API_TOKEN=r8_xxx' > tools/art/.env   # 本目录 .env (已 gitignore)

用法:
    python3 tools/art/generate.py --list                       # 列出批次与每档 prompt
    python3 tools/art/generate.py --probe                       # 打印所选模型的真实入参 schema (自检)
    python3 tools/art/generate.py --batch infra_buildings       # 生成整批 raw 图
    python3 tools/art/generate.py --batch infra_buildings --process   # 生成 + 立刻跑 harness 后处理
    python3 tools/art/generate.py --only facility-solo --process       # 只做一档, 端到端
    python3 tools/art/generate.py --batch infra_buildings --model recraft   # 换模型

成本: 默认 flux 系列单图约几美分; 一批 18 张约 < $1。
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import subprocess
import sys
import time
from pathlib import Path

import requests

HERE = Path(__file__).resolve().parent
RUNS = HERE / "runs"
LOGGER = logging.getLogger("art_generate")

# ── 统一 style 前缀 (见 design/图片素材生成流程.md §3.1; 不改措辞以保证一致性) ──
STYLE = (
    "clean HD 2D game UI icon, modern flat editorial tech illustration, "
    "isometric 3/4 view, single centered subject with generous margin, "
    "cohesive cool palette of slate blue, teal and soft cyan accents on light grey, "
    "crisp vector-like edges, subtle soft shadow under the subject only, "
    "no text, no numbers, no logos, no real-world brands, no people, "
    "no scenery, no sky, no planet, no starfield, "
    "subject fully isolated on a perfectly flat uniform pure bright magenta "
    "chroma-key background (RGB 255 0 255), no gradient, no vignette, "
    "square 1:1 composition"
)

# 肖像风格 (招聘 lead 头像): 与 icon 同色板, 程式化人物半身像 (不是写实照片)。
# 关键: die-cut 剪纸贴纸式, 洋红直接贴到人物轮廓 — 否则 flux 会画一圈灰色棚拍底/光晕,
# 那圈灰不是洋红, 去背吃不掉, 会在头像里留一个灰底方块 (见 §8bis 坑)。
STYLE_PORTRAIT = (
    "clean HD 2D game UI character avatar, modern flat editorial illustration, "
    "a friendly stylized person, head and shoulders, facing forward, "
    "flat simple shapes, cohesive cool palette of slate blue, teal and soft cyan, "
    "no text, no logos, no real-person likeness, not a photo, "
    "NO circle, NO round badge, NO frame, NO border, NO sticker outline, "
    "NO vignette, NO backdrop panel, NO drop shadow, "
    "the entire background is one flat uniform pure bright magenta (RGB 255 0 255) "
    "filling every edge, the person is the only non-magenta element, square 1:1"
)

# 写实肖像风格 (新游戏创始人头像, 2026-05 重做): 旧 portrait 偏"扁平插画 + 统一青色调",
# 用户嫌脏 → 改"干净写实游戏头像": 自然肤色、柔和均匀棚拍光、去掉青色滤镜、服装低饱和。
# 仍按 chroma-key 出图 (纯洋红底), harness 去背为透明。NO frame/border/vignette 让去背干净。
STYLE_PORTRAIT_REAL = (
    "clean HD 2D game UI character avatar, polished semi-realistic stylized illustration, "
    "a friendly person, head and shoulders, facing forward, "
    "soft natural shading, natural skin tones, neutral balanced color grade, "
    "modern smart-casual clothing in muted understated tones, calm confident slight smile, "
    "no text, no logos, no real-person likeness, not a photo, "
    "NO circle, NO round badge, NO frame, NO border, NO sticker outline, "
    "NO vignette, NO backdrop panel, NO studio backdrop, NO drop shadow, no strong color filter, "
    "the entire background is one flat uniform pure bright magenta (RGB 255 0 255) "
    "filling every edge right up to the silhouette, "
    "the person is the only non-magenta element, square 1:1"
)

# 历史 AI 公司标志风格。运行时 brand/task 图标已改由
# build_deterministic_ui_icons.py 确定性绘制; 此 preset 仅保留给实验性重出图。
# 抽象符号不涉及真实品牌, 符合化名规范。
STYLE_LOGO = (
    "clean modern abstract tech company logo mark, a single bold minimalist symbol "
    "in one solid flat accent color, simple geometric vector shapes, optional subtle two-tone, "
    "no glow, no sparkle dust, no neon, "
    "geometric memorable and instantly readable at small size, "
    "centered with generous margin, perfectly balanced, "
    "no text, no letters, no numbers, no real-world brand, no mascot face, "
    "NO frame, NO border, NO square tile, NO background gradient, NO vignette, NO drop shadow, "
    "the entire background is one flat uniform pure bright magenta (RGB 255 0 255) "
    "filling every edge, the symbol is the only non-magenta element, square 1:1"
)

# 场景背景风格 (办公室房间 room-bg, 2026-05): 与 icon 同冷色板, 但不是孤立 magenta 主体,
# 而是一整张铺满画面的室内背景插画 (无 chroma-key, 不去背)。宽幅构图给宽屏 tab 用。
# 关键: NO magenta, full-bleed scene, 留出中下方空地让引擎再叠办公桌精灵 (desk prop)。
STYLE_SCENE = (
    "clean HD 2D game background illustration, modern flat editorial style, "
    "soft natural daylight, calm serene mood, "
    "cohesive cool palette of slate blue, teal and soft cyan with warm light-wood tones "
    "on light neutral surfaces, gentle soft shading, crisp clean vector-like shapes, "
    "no text, no numbers, no logos, no real-world brands, no people, "
    "wide horizontal composition, full-bleed scene filling the entire frame edge to edge, "
    "no magenta, no chroma-key, no border, no vignette"
)

# 道具风格 (办公室 desk / trophy 等要叠进场景的透明精灵, 2026-05): 同 icon 等距画风,
# 但**去掉 baked 投影**——投影会在主体与 magenta 之间拉出一条 pink→purple→dark 的渐变,
# 任何单一阈值都切不干净 (会留紫斑或啃掉主体)。同理强调纯洋红铺到轮廓, 暖色主体 (金奖杯/
# 木桌) 与洋红色距才够远, 低 flood-bg-tol 即可干净抠像。
STYLE_PROP = (
    "clean HD 2D game UI prop illustration, modern flat editorial style, isometric 3/4 view, "
    "single centered subject with generous margin, "
    "cohesive cool palette of slate blue, teal and soft cyan accents with warm light-wood tones, "
    "crisp vector-like edges, flat even lighting, "
    "NO shadow, NO drop shadow, NO cast shadow on the ground, NO reflection, NO glow, NO gradient, "
    "no text, no numbers, no logos, no real-world brands, no people, no scenery, no sky, "
    "subject fully isolated on a perfectly flat uniform pure bright magenta (RGB 255 0 255) "
    "background filling every edge right up to the subject silhouette, square 1:1 composition"
)

# 收藏画作风格 (拍卖行 painting 类, 2026-05): 收藏品卡缩略图沿用 icon 的孤立 + magenta
# 去背, 但画作要画框里的人物 / 风景, 与 icon 的 "no people/scenery/sky" 冲突 → 单列一档,
# 只保留 "画框名画作为单个孤立物体 + 纯洋红底", 去掉那几条禁制。内容抽象化、不复刻真实作品。
STYLE_COLLECTIBLE_ART = (
    "clean HD 2D game UI collectible icon, a single ornately framed fine-art painting "
    "shown as one isolated object, isometric 3/4 view, generous margin, "
    "rich painterly artwork inside an elegant picture frame, "
    "cohesive tasteful palette, crisp clean edges, subtle soft shadow under the frame only, "
    "no text, no numbers, no logos, no real-world brand, not a reproduction of any real artwork, "
    "subject fully isolated on a perfectly flat uniform pure bright magenta "
    "chroma-key background (RGB 255 0 255), no gradient, no vignette, square 1:1 composition"
)

# 模拟阶梯风格 (宇宙模拟工程 5 阶, 2026-05): 主题是模拟天气/海洋/地球/太阳系/宇宙,
# 天然与 icon 的 "no scenery/sky/planet/starfield" 冲突 → 单列一档。把每一阶画成**一颗
# 孤立的全息数据可视化球体** (科学仿真感, 非写实照片), 被模拟的内容收在球体内部, 背景不撒
# 星点 (否则 magenta 上散落亮点抠不净)。仍纯洋红铺底去背成透明精灵。
STYLE_SIM = (
    "clean HD 2D game UI icon, modern flat editorial tech illustration, "
    "a single glowing holographic scientific simulation as one isolated centered object "
    "with generous margin, a stylized luminous data-visualization sphere, "
    "cohesive cool palette of slate blue, teal and soft cyan with a gentle glow, "
    "crisp vector-like edges, subtle soft shadow under the subject only, "
    "the simulated subject is contained inside the single isolated sphere, "
    "nothing scattered outside it in the background, "
    "no text, no numbers, no logos, no real-world brands, no people, "
    "not a photo, not realistic photography, "
    "subject fully isolated on a perfectly flat uniform pure bright magenta "
    "chroma-key background (RGB 255 0 255), no gradient, no vignette, square 1:1 composition"
)

_STYLES: dict[str, str] = {
    "icon": STYLE,
    "portrait": STYLE_PORTRAIT,
    "portrait_real": STYLE_PORTRAIT_REAL,
    "logo": STYLE_LOGO,
    "scene": STYLE_SCENE,
    "prop": STYLE_PROP,
    "collectible_painting": STYLE_COLLECTIBLE_ART,
    "sim": STYLE_SIM,
}

# ── 模型注册表 (preset key -> Replicate ref + 入参构造). 真实模型名仅限本表。 ──
def _flux_input(prompt: str, seed: int | None, aspect: str = "1:1") -> dict:
    inp = {
        "prompt": prompt,
        "aspect_ratio": aspect,
        "output_format": "png",
        "prompt_upsampling": False,
        "safety_tolerance": 2,
    }
    if seed is not None:
        inp["seed"] = int(seed)
    return inp


def _recraft_input(prompt: str, seed: int | None, aspect: str = "1:1") -> dict:
    # recraft v3 用 style 控一致性, 不暴露 seed; vector_illustration 偏扁平图标。
    size = "1820x1024" if aspect in ("16:9", "21:9") else "1024x1024"
    return {"prompt": prompt, "size": size, "style": "digital_illustration"}


MODELS: dict[str, dict] = {
    "flux":     {"ref": "black-forest-labs/flux-1.1-pro", "build": _flux_input},
    "flux-dev": {"ref": "black-forest-labs/flux-dev",     "build": _flux_input},
    "recraft":  {"ref": "recraft-ai/recraft-v3",          "build": _recraft_input},
}
DEFAULT_MODEL = "flux"

# ── 批次清单. label = .tres id 的连字符化 (见 §3.4); subject 见 §4.1。 ──
# 整批共用一个 seed → flux 同 seed 不同 prompt 出图风格更统一。
BATCHES: dict[str, dict] = {
    "infra_buildings": {
        "seed": 70123,
        "background_mode": "sampled",
        "background_tolerance": 45,
        "assets": [
            ("facility-solo",        "a single desktop tower with one glowing GPU card on a small desk"),
            ("facility-pod",         "a small open-frame mini server cabinet holding a few stacked GPU blades"),
            ("facility-rack-16",     "one short server rack half-filled with GPU blades, tidy cabling"),
            ("facility-rack-32",     "one full-height server rack fully filled with GPU blades"),
            ("facility-rack",        "a pair of tall server racks side by side, fully populated"),
            ("facility-room",        "a small server room with two short rows of racks on a raised floor"),
            ("facility-hall",        "a server hall with several long rows of racks and overhead cable trays"),
            ("facility-floor",       "a full data-center floor, many parallel rack rows in isometric view"),
            ("facility-building-s",  "a small standalone data-center building, a low box with side cooling vents"),
            ("facility-building-m",  "a medium data-center building, a long low hall with rooftop chiller units"),
            ("facility-building-l",  "a large windowless data-center hall with a big rooftop cooling array"),
            ("facility-campus-s",    "a small data-center campus, two halls linked by walkways with cooling units around"),
            ("facility-campus-m",    "a mid data-center campus, several halls plus a small electrical substation"),
            ("facility-campus-l",    "a large data-center campus, many halls, a substation and water-cooling ponds"),
            ("facility-metropolis",  "a metropolis-scale compute district, a dense cluster of data-center halls like a tiny city"),
            ("facility-space-s",     "a compact orbital server satellite module with two solar-panel wings, fully isolated"),
            ("facility-space-m",     "a medium orbital data-center station, a central truss with server modules and solar arrays"),
            ("facility-space-l",     "a vast orbital data-center megastructure, a ring of server modules with sprawling solar sails"),
            ("facility-planet",      "a small spherical compute megastructure like a tiny engineered planet, the sphere wrapped with banded server modules, glowing GPU window lights and slim solar rings around it, single fully isolated centered object"),
            ("facility-cloud",       "a cloud-computing rental icon, a glossy rounded cloud symbol fused with a compact server rack with glowing GPU blades inside, representing rented cloud compute"),
        ],
    },
    # ── 核心卡片图标 (label = <类>-<key>, 接受时落到 assets/sprites/ui/<类>/<key>.png) ──
    "datasets": {
        "seed": 81001,
        "background_mode": "sampled",
        "background_tolerance": 45,
        "assets": [
            ("dataset-text",  "a text dataset icon, a document page with lines of paragraph text"),
            ("dataset-image", "an image dataset icon, a framed picture with a small mountain and sun"),
            ("dataset-code",  "a code dataset icon, a window showing code brackets and indented lines"),
            ("dataset-audio", "an audio dataset icon, a pair of glossy headphones over a clear sound waveform with a music note"),
            ("dataset-video", "a video dataset icon, a film strip frame with a play triangle"),
        ],
    },
    "products": {
        "seed": 81002,
        "background_mode": "sampled",
        "background_tolerance": 45,
        "assets": [
            ("product-chatbot",              "a chatbot product icon, a single clean rounded chat speech bubble with three dots inside"),
            ("product-agent",                "an AI agent product icon, a small autonomous robot assistant with a gear halo"),
            ("product-api",                  "an API product icon, a plug connecting code brackets, an integration socket motif"),
            ("product-coding_agent",         "a coding agent product icon, a code editor window with a small robot cursor"),
            ("product-multimodal_assistant", "a multimodal assistant product icon, overlapping text, image and audio symbols in one badge"),
        ],
    },
    "tech": {
        "seed": 81003,
        "reject_edge": False,   # 复杂图标常铺满画面, 不按触边判废
        "background_mode": "sampled",
        "background_tolerance": 45,
        "assets": [
            ("tech-arch",        "a neural network architecture icon, stacked layered blocks like a model blueprint"),
            ("tech-attention",   "an attention mechanism icon, focus rays converging onto one highlighted node in a small graph"),
            ("tech-loss",        "a training loss icon, a descending loss curve on a small line chart"),
            ("tech-engineering", "an engineering optimization icon, a gear combined with a lightning speed bolt"),
            ("tech-application", "an application icon, an app window launching with a small rocket"),
            ("tech-context",     "a context-length icon, an expanding bracket window with a long scroll"),
        ],
    },
    "tasks": {
        "seed": 81004,
        "reject_edge": False,
        "background_mode": "sampled",
        "background_tolerance": 45,
        "assets": [
            ("task-pretrain",        "a pretraining task icon, a glowing model core with a big data funnel pouring in"),
            ("task-posttrain",       "a fine-tuning task icon, a model core with a small wrench and a polish sparkle"),
            ("task-evaluate",        "an evaluation task icon, a model core beside a checklist and a score gauge"),
            ("task-data_collection", "a data collection task icon, a funnel gathering scattered data dots into a bucket"),
            ("task-tech_research",   "a research task icon, a lab flask with a glowing lightbulb idea above it"),
        ],
    },
    # ── 基建补充 (GPU 植物族 / 供电) ──
    "gpu": {
        "seed": 81005,
        "background_mode": "sampled",
        "background_tolerance": 45,
        "assets": [
            ("gpu-cypress", "a high-end AI accelerator board icon, a sleek GPU card with a cypress evergreen leaf emblem"),
            ("gpu-maple",   "an AI accelerator board icon, a GPU card with a red maple leaf emblem"),
            ("gpu-bamboo",  "a compact AI accelerator board icon, a GPU card with a green bamboo stalk emblem"),
        ],
    },
    "power": {
        "seed": 81006,
        "background_mode": "sampled",
        "background_tolerance": 45,
        "assets": [
            ("power-grid",  "an electric grid power icon, a transmission pylon tower with power lines"),
            ("power-green", "a green renewable power icon, a solar panel beside a wind turbine with a small leaf"),
        ],
    },
    # ── 招聘 lead 人物肖像 (portrait 风格) ──
    # 多元肖像池 (按 lead.id 哈希分配, 见 IconRegistry.lead_portrait): 性别均衡 +
    # 族裔 / 年龄多样, 角色无关 (具体职位靠卡片文字/徽章, 不靠头像道具)。
    "leads": {
        "seed": 82001,
        "style": "portrait",
        "reject_edge": False,
        "component_mode": "all",
        "background_mode": "sampled",
        "background_tolerance": 45,
        "assets": [
            ("lead-portrait-01", "a young East Asian woman with short black hair, smiling, casual blazer"),
            ("lead-portrait-02", "a middle-aged Black man with a short beard and glasses, button-up shirt"),
            ("lead-portrait-03", "a young white man with tousled brown hair, casual hoodie"),
            ("lead-portrait-04", "a middle-aged South Asian woman with long dark hair and earrings, smart casual"),
            ("lead-portrait-05", "an older white woman with a grey bob and glasses, blazer"),
            ("lead-portrait-06", "a young Black woman with curly hair and hoop earrings, casual top"),
            ("lead-portrait-07", "a middle-aged Hispanic man with short dark hair and a mustache, polo shirt"),
            ("lead-portrait-08", "a young Middle Eastern man with a short beard wearing headphones, casual tee"),
            ("lead-portrait-09", "an older East Asian man with greying hair and glasses, cardigan"),
            ("lead-portrait-10", "a young Latina woman with wavy brown hair, casual denim jacket"),
            ("lead-portrait-11", "a middle-aged bald white man with a beard, plain t-shirt"),
            ("lead-portrait-12", "a young Southeast Asian woman with glasses and a ponytail, smart casual"),
        ],
    },
    # ── 创始人专属头像 (玩家自己, 新游戏可选; portrait 风格, 同肖像池一致) ──
    # 写到 Lead.avatar_id, 接受时落到 assets/sprites/ui/founder/avatar-NN.png。
    # 与 leads 肖像池分开但同一画风; 多元 (性别 / 族裔 / 年龄), 角色无关。
    # 见 design/出身系统设计.md §3 + IconRegistry.founder_avatar。
    "founders": {
        "seed": 82002,
        "style": "portrait_real",
        "reject_edge": False,
        "component_mode": "all",
        "background_mode": "sampled",
        "background_tolerance": 45,
        "defringe": 0,
        "assets": [
            ("founder-avatar-01", "a confident young East Asian woman with a sleek bob, blazer over a tee"),
            ("founder-avatar-02", "a young Black man with short locs and glasses, casual zip hoodie"),
            ("founder-avatar-03", "a young white woman with red hair in a ponytail, denim jacket"),
            ("founder-avatar-04", "a young South Asian man with a trimmed beard, crew-neck sweater"),
            ("founder-avatar-05", "a young Latino man with wavy dark hair, casual henley shirt"),
            ("founder-avatar-06", "a young Middle Eastern woman with a headscarf, smart-casual blouse"),
            ("founder-avatar-07", "a young Southeast Asian man with side-parted hair, polo shirt"),
            ("founder-avatar-08", "a young white man with curly hair and round glasses, casual cardigan"),
        ],
    },
    # ── 历史公司标志实验批 (运行时已改用 build_deterministic_ui_icons.py) ──
    # 若临时尝试 AI 重出, 接受前仍必须通过 brand/task alpha 填充率测试。
    # 抽象符号, 不涉及真实品牌 (化名规范)。multi-part 渐变符号 → component_mode=all。
    # 颜色须够深/饱和 (浅灰底上可读), 别用白/浅色 (会糊在底上)。
    "company_logos": {
        "seed": 83001,
        "style": "logo",
        "reject_edge": False,
        "component_mode": "all",
        "background_mode": "sampled",
        "background_tolerance": 45,
        "defringe": 1,  # 削掉去背残留的洋红/混色边
        "assets": [
            ("brand-01", "a teal upward trending arrow made of three stacked chevrons"),
            ("brand-02", "a sky-blue stylized origami crane bird mid-flight, folded geometric planes"),
            ("brand-03", "a flat geometric royal-blue mountain peak symbol, solid fill, no snow, no white, no ground, no landscape"),
            ("brand-04", "a cyan faceted crystal gem, sharp symmetric facets"),
            ("brand-05", "a bright golden-amber bold four-point sparkle star, large and centered"),
            ("brand-06", "a green set of concentric orbit rings circling a solid center dot"),
            ("brand-07", "an emerald-green stylized sprouting leaf seedling, two clean leaves"),
            ("brand-08", "a blue abstract infinity knot of two interlocking loops"),
            ("brand-09", "a bright orange clean isometric cube with three visible faces, simple flat shading"),
            ("brand-10", "a flat vivid-red rocket symbol pointing up, solid fill, no smoke, no exhaust, no white"),
            ("brand-11", "a flat vivid-orange lightning bolt symbol, solid fill, no shadow"),
            ("brand-12", "a bright lime-green bold hexagon badge with a center dot"),
            ("brand-13", "a bold solid deep cobalt-blue paper plane, fully filled navy blue, not white"),
            ("brand-14", "a bright cyan bold abstract camera aperture iris with six blades"),
        ],
    },
    # 模型架构族 (model.arch 经 IconRegistry._arch_family 归到这 5 类之一)。
    "model_arch": {
        "seed": 83001,
        "reject_edge": False,
        "background_mode": "sampled",
        "background_tolerance": 45,
        "assets": [
            ("model-dense",      "a dense neural network icon, a fully connected stack of glowing layered nodes"),
            ("model-moe",        "a mixture-of-experts model icon, several expert blocks with a router switch directing arrows"),
            ("model-encoder",    "an encoder model icon, an arrow funneling text into one compact latent block"),
            ("model-enc_dec",    "an encoder-decoder model icon, two linked blocks with arrows flowing in and out"),
            ("model-multimodal", "a multimodal model icon, text image and audio symbols merging into one glowing core"),
        ],
    },
    # 事件卡按 category 取图 (opportunity / crisis / flavor; routine 不出卡)。
    "events": {
        "seed": 83002,
        "reject_edge": False,
        "background_mode": "sampled",
        "background_tolerance": 45,
        "assets": [
            ("event-opportunity", "an opportunity event icon, a glowing upward arrow with a spark, an open door of light"),
            ("event-crisis",      "a crisis event icon, a warning triangle with an alert mark over a small storm cloud"),
            ("event-flavor",      "a news flavor event icon, a rolled newspaper with a small announcement megaphone"),
            ("event-routine",     "a routine office event icon, a desk calendar with a small coffee cup, casual and light"),
        ],
    },
    # 慈善公益方向 (icon 风格): label = charity-<cause_id>, 落 assets/sprites/ui/charity/<id>.png,
    # IconRegistry.charity_icon 读取。三方向概念性图标, 无 scenery 冲突, 走默认 icon 风格。
    "charity": {
        "seed": 86001,
        "reject_edge": False,
        "component_mode": "all",
        "background_mode": "sampled",
        "background_tolerance": 45,
        "defringe": 1,
        "assets": [
            ("charity-bio_science",         "a frontier life-science research grant icon, a glowing teal DNA double helix rising out of an open book with a small microscope beside it"),
            ("charity-fundamental_compute", "a fundamental physics and supercomputing donation icon, a glowing atom with orbiting electron rings fused with a compact glowing supercomputer server core"),
            ("charity-social_welfare",      "a social welfare charity icon, two open cupped hands gently holding up a glowing warm heart, a caring giving-back symbol"),
        ],
    },
    # 宇宙模拟工程 5 阶 (sim 风格=孤立全息数据球): label = simulation-<stage_id>,
    # 落 assets/sprites/ui/simulation/<id>.png, IconRegistry.simulation_icon 读取。
    "simulation": {
        "seed": 86002,
        "style": "sim",
        "reject_edge": False,
        "component_mode": "all",
        "background_mode": "sampled",
        "background_tolerance": 45,
        "defringe": 1,
        "assets": [
            ("simulation-weather",      "a planet-scale weather simulation, a holographic globe wrapped in swirling spiraling storm clouds and cyclone systems"),
            ("simulation-ocean",        "a planet-scale ocean simulation, a holographic globe covered in glowing blue ocean currents, swirling gyres and flowing wave lines"),
            ("simulation-earth",        "a whole-earth digital-twin simulation, a holographic wireframe globe of a planet with glowing continents and grid latitude and longitude lines"),
            ("simulation-solar_system", "a solar-system simulation, a holographic orrery of concentric glowing orbit rings with small planet spheres circling one bright central star, all contained as a single compact object"),
            ("simulation-universe",     "a whole-universe simulation, one single isolated glowing spiral galaxy disk hologram with luminous star clusters swirling in its spiral arms, a bright glowing core, nothing else floating around it"),
        ],
    },
    # ── 办公室房间 (scene 风格, 宽幅, 不去背) ──
    # room-bg 是一整张铺满的极简办公室背景: 大面积落地窗 + 窗外宁静湖泊。引擎用 COVER 平铺,
    # 中下方留空让 desk 精灵叠上去 (点击热区对齐)。处理: 不走 process_asset (无 chroma-key),
    # 直接缩放 raw → assets/sprites/ui/office/room-bg.png。见 design/办公室与收藏系统设计.md §8.1。
    "office_room": {
        "seed": 84001,
        "style": "scene",
        "aspect": "16:9",
        "assets": [
            ("office-room-bg",
             "a first-person point of view of sitting at a minimalist office desk, the near "
             "light-wood desk surface spans the whole lower foreground with one sleek computer "
             "monitor and a keyboard on it facing the viewer, the desk top mostly empty and clear, "
             "a deep spacious room with lots of open floor, in the mid-ground to the left stands a "
             "low rectangular minimalist wood coffee table with a completely empty clear flat top "
             "and clear space around it, far in the background the entire back wall is a huge "
             "floor-to-ceiling glass window showing a calm tranquil mirror-like lake and soft low "
             "hills under a gentle pale sky, light warm wood floor, soft diffuse morning daylight, "
             "airy peaceful and clean, strong sense of depth"),
        ],
    },
    # ── 办公室道具 (prop 风格=无 baked 投影, magenta 去背成透明精灵, 叠到房间墙角) ──
    # 每枚奖杯一张, 接受时落 assets/sprites/ui/office/trophy-<trophy_id>.png; OfficeView 按
    # 奖杯 id 取图 (缺则回退通用 trophy.png → 图标字形)。办公桌+电脑已烤进 room-bg, 无需单独精灵。
    "office_props": {
        "seed": 84002,
        "style": "prop",
        "reject_edge": False,
        "component_mode": "all",
        "background_mode": "sampled",
        "background_tolerance": 45,
        "defringe": 0,
        "assets": [
            ("office-trophy",
             "a shiny golden trophy cup award standing on a small dark pedestal base, "
             "a classic two-handled champion cup, polished gold, simple and clean"),
            ("office-trophy-leaderboard_first",
             "a tall first-place champion trophy cup in polished gold with a laurel wreath "
             "around it, standing on a dark marble base, simple and clean"),
            ("office-trophy-charity_global",
             "a humanitarian charity award trophy, a small globe cradled by two open hands, "
             "polished teal and silver, on a dark base, simple and clean"),
            ("office-trophy-universe_answer",
             "a cosmic mystery award trophy, a glowing deep-blue orb with a tiny ringed planet "
             "and a few stars, gold accents, on a dark obsidian base, simple and clean"),
            # 奖章 (form=medal, 摆近处桌上): 圆形勋章带绶带, 与奖杯区分。
            ("office-medal-charity_bronze",
             "a charity award medal, a round polished bronze copper medal with a small heart "
             "engraved in the center, hanging from a short teal ribbon, simple and clean"),
            ("office-medal-charity_silver",
             "a charity award medal, a round polished silver medal with a small heart "
             "engraved in the center, hanging from a short teal ribbon, simple and clean"),
            ("office-medal-charity_global",
             "a humanitarian charity award medal, a round polished gold medal with a small globe "
             "and a heart engraved in the center, hanging from a short teal ribbon, simple and clean"),
        ],
    },
    # ── 拍卖行收藏品·逐件缩略图 (icon 风格, magenta 去背成透明精灵) ──
    # label = collectible-<id> (id 即 CollectibleSpec.id), 接受时落
    # assets/sprites/ui/collectible/<id>.png, 由 IconRegistry.collectible_icon(id) 读取。
    # crypto / trading_card / ai_hardware / supercar 四类走 icon 风格 (孤立物体);
    # painting 类内容含人物/风景, 与 icon 的 no-people/scenery 冲突, 另列 collectibles_art。
    # 名字/描述对照 tools/build_collectibles.py 的 ITEMS; 内容遵化名规范 (不复刻真实品牌/作品)。
    # 见 design/办公室与收藏系统设计.md §8/§9。
    "collectibles": {
        "seed": 85001,
        "reject_edge": False,
        "background_mode": "sampled",
        "background_tolerance": 45,
        "defringe": 0,
        "assets": [
            # ── crypto: 纪念金币 / NFT 牌 / 私钥残片 ──
            ("collectible-genesis_coin_7", "a gleaming golden commemorative crypto coin with a faceted gem set at its center"),
            ("collectible-zero_block_relic", "an engraved metallic plaque tablet stamped with a single solid cube emblem, the origin-block relic"),
            ("collectible-cypherpunk_mail", "a glowing holographic sealed envelope token, a digital founding email minted as a collectible"),
            ("collectible-first_smart_contract", "a dark bronze and navy scroll tablet etched with glowing teal circuit-board contract traces, deep saturated colors, not pale, not white"),
            ("collectible-lost_wallet_fragment", "a broken glinting golden key fragment, a shard of a lost digital wallet key"),
            ("collectible-pixel_ape_0001", "a blocky pixel-art ape avatar portrait on a rounded collectible token card"),
            ("collectible-quantum_resist_coin", "a deep blue metallic coin emblazoned with a glowing teal hexagonal lattice shield emblem, dark saturated metal, not silver, not pale, not white"),
            ("collectible-meme_shiba_genesis", "a playful cartoon shiba dog face minted on a golden meme coin token"),
            ("collectible-cold_titanium_plate", "a brushed titanium metal plate engraved with rows of small word slots, a cold-storage seed plate"),
            ("collectible-dark_market_ghost", "a translucent shadowy ghost-shaped coin token, mysterious and dark"),
            ("collectible-fork_war_snapshot", "a crystalline coin splitting cleanly into two diverging forked branches"),
            ("collectible-dao_constitution_nft", "a glowing scroll token wrapped in a web of connected network nodes"),
            ("collectible-defi_genesis_lp", "a pair of interlocking liquidity-pool tokens forming a linked-ring symbol"),
            ("collectible-halving_relic", "a golden coin cut cleanly in half, a halving commemorative relic on a stand"),
            ("collectible-stablecoin_proto", "a smooth balanced silver coin resting level on a tiny weighing scale"),
            ("collectible-miner_signed_board", "a small green mining circuit board with a coin emblem and a hand-signed swoosh"),
            # ── trading_card: 全息卡牌 (强调"矩形卡片"本体, 否则 flux 只画里面的怪物) ──
            ("collectible-holy_dragon_gem", "a single upright rectangular collectible trading card with rounded corners and a glossy holographic rainbow-foil border, the card artwork depicting a radiant golden holy dragon"),
            ("collectible-illustrator_award", "a single upright rectangular collectible trading card with rounded corners and a golden foil border, the card artwork framed by a laurel wreath, a special-award card"),
            ("collectible-flame_beast_card", "a single upright rectangular collectible trading card with rounded corners and a shimmering holographic rainbow-foil border, the card artwork depicting a fierce blue-flame beast monster"),
            ("collectible-tournament_champion", "a single upright rectangular collectible trading card with rounded corners and a holographic foil border, the card artwork showing a golden victory cup"),
            ("collectible-banned_first_print", "a single upright rectangular collectible trading card with rounded corners and a dark holographic border marked with a glowing forbidden seal"),
            ("collectible-error_inverted_holo", "a single upright rectangular collectible trading card with rounded corners and a holographic foil border, the colors inverted as a rare misprint"),
            ("collectible-mascot_card_zero", "a single upright rectangular collectible trading card with rounded corners and a holographic foil border, the card artwork depicting a cute friendly mascot creature"),
            ("collectible-beta_resource_card", "a single upright rectangular vintage trading card with rounded corners, the card artwork showing a glowing elemental energy symbol"),
            ("collectible-crystal_phoenix", "a single upright rectangular collectible trading card with rounded corners and a holographic foil border, the card artwork depicting a crystal phoenix refracting rainbow light"),
            ("collectible-full_art_secret", "a single upright rectangular secret-rare full-art collectible trading card with rounded corners and a thin holographic foil border, edge-to-edge illustration"),
            ("collectible-shadow_knight_alpha", "a single upright rectangular collectible trading card with rounded corners and a holographic foil border, the card artwork depicting a shadowy knight in dark armor"),
            ("collectible-grandmaster_deck", "a neat fanned stack of rectangular championship-winning trading cards bound with a band"),
            ("collectible-signed_artist_holo", "a single upright rectangular holographic collectible trading card with rounded corners and a foil border, a silver artist signature swoosh across its face"),
            ("collectible-sealed_starter", "a sealed shrink-wrapped glossy trading-card starter deck box, unopened"),
            ("collectible-gold_foil_promo", "a single upright rectangular gleaming gold-foil promotional trading card with rounded corners"),
            ("collectible-schoolyard_champ", "a single upright rectangular slightly worn nostalgic champion trading card with rounded corners, stamped with a star emblem"),
            # ── ai_hardware: 加速板卡 / 芯片 ──
            ("collectible-first_ai_card", "a vintage first-generation AI training accelerator board, a green circuit card with one big chip and a cooling fan, displayed on a small museum stand"),
            ("collectible-founder_signed_gpu", "a sleek dark navy AI accelerator board with a glowing teal heatsink and a bright silver hand-signed signature swoosh across its shroud, deep saturated colors, not pale, not white"),
            ("collectible-wafer_scale_relic", "a huge square dark silicon wafer chip patterned with deep blue and glowing teal circuitry, a wafer-scale mega processor, dark metallic finish, saturated colors, not mirror, not silver, not pale, not white"),
            ("collectible-first_tensor_board", "an early matrix-math accelerator, a dark navy circuit board with a glowing teal grid-patterned processor chip, deep saturated colors, not pale, not white"),
            ("collectible-lab_prototype_accel", "a hand-soldered prototype accelerator, a dark navy circuit board with a chip and a few colorful jumper wires, deep saturated colors, not pale, not white"),
            ("collectible-cluster_node_zero", "a single dark navy server blade node card with glowing blue accents, deep saturated colors, not pale, not white"),
            ("collectible-photonic_accel_proto", "an accelerator board threaded with glowing fiber-optic light strands, photonic computing"),
            ("collectible-inference_asic_v1", "a compact dedicated inference ASIC chip mounted on a small board"),
            ("collectible-analog_compute_die", "an experimental analog-compute die with wavy flowing analog circuit traces"),
            ("collectible-liquid_cooled_proto", "an accelerator board submerged in clear cooling liquid with rising bubbles"),
            ("collectible-neuromorphic_chip", "a brain-shaped neuromorphic chip with branching neuron-like circuit dendrites"),
            ("collectible-overclock_record_card", "a high-performance graphics card with a massive finned heatsink, sealed under a glass dome"),
            ("collectible-edge_chip_first", "a tiny edge-inference microchip small enough to balance on a fingertip"),
            ("collectible-data_center_busbar", "a thick polished copper power busbar segment salvaged from a data center"),
            ("collectible-retro_gamer_gpu", "a retro gaming graphics card with a chunky plastic dual-fan shroud"),
            ("collectible-retired_mining_card", "a worn dusty dark second-hand mining graphics card in deep blue tones, saturated colors, not pale, not white"),
            # ── supercar: 超跑 / 古典名车 ──
            ("collectible-le_mans_winner", "a sleek low aerodynamic endurance-race prototype race car, 3/4 view"),
            ("collectible-silver_arrow_classic", "a classic silver open-wheel early-era grand-prix racing car"),
            ("collectible-coachbuilt_one_off", "a bespoke coachbuilt luxury sports car with elegant unique flowing bodywork"),
            ("collectible-midnight_comet_le", "a dark midnight-blue limited-edition hypercar, sleek and aggressive"),
            ("collectible-founder_hyper_one", "a vintage hand-built classic hypercar with graceful curves"),
            ("collectible-last_v12_manual", "a sleek elegant grand-tourer hypercar, the last of the combustion era"),
            ("collectible-royal_limousine", "a long stately regal ceremonial limousine"),
            ("collectible-turbine_concept", "a retro-futuristic jet-age turbine-powered concept car"),
            ("collectible-gullwing_classic", "a classic sports coupe with its open gullwing doors raised upward"),
            ("collectible-electric_record_car", "a streamlined teardrop electric land-speed record car"),
            ("collectible-rally_legend", "a rugged rally race car with mud flaps and bold abstract racing livery"),
            ("collectible-track_only_extreme", "an extreme track-only race car with a huge towering rear wing"),
            ("collectible-phantom_gt", "a sleek elegant hand-built limited hypercar grand tourer"),
            ("collectible-solar_concept", "a concept roadster with a roof made of dark solar panels"),
            ("collectible-prototype_mule", "a camouflage-wrapped engineering test-mule prototype car"),
        ],
    },
    # ── 拍卖行收藏品·名画 (collectible_painting 风格: 画框名画, 允许画框内人物/风景) ──
    "collectibles_art": {
        "seed": 85002,
        "style": "collectible_painting",
        "reject_edge": False,
        "background_mode": "sampled",
        "background_tolerance": 45,
        "defringe": 0,
        "assets": [
            ("collectible-starry_vortex", "a gold-framed painting of a swirling turbulent starry night sky in thick expressive brushstrokes over a small sleeping village"),
            ("collectible-salvator_cosmos", "a gold-framed renaissance-style painting of a serene robed figure holding up a glowing crystal orb"),
            ("collectible-ink_mountains", "a long ornately framed blue-green ink-wash landscape painting of layered misty mountains and rivers"),
            ("collectible-weeping_lady", "an ornate gold-framed classical portrait painting of a poised noblewoman"),
            ("collectible-echo_scream", "a framed expressionist painting of a swirling anguished figure clutching its face under a blood-orange sky"),
            ("collectible-gilded_kiss", "an ornate framed painting of two embracing figures wrapped in shimmering gold-leaf patterns"),
            ("collectible-blue_period_boy", "a framed melancholic blue-toned portrait painting of a thin seated boy"),
            ("collectible-master_self_portrait", "a framed warm-brown old-master self-portrait painting of a bearded man"),
            ("collectible-cubist_figure", "a framed cubist painting of a figure shattered into angular geometric facets"),
            ("collectible-night_cafe", "a framed post-impressionist painting of a glowing late-night café interior in vivid yellows and greens"),
            ("collectible-abstract_red_field", "a thick ornate gold picture frame, the canvas inside the frame filled edge to edge with a deep saturated glowing crimson-red color field, the gold frame clearly separating the red from the surroundings"),
            ("collectible-dripping_chaos", "a framed abstract-expressionist canvas covered in chaotic dripped and splattered paint"),
            ("collectible-melting_clocks", "a framed surrealist painting of soft melting pocket watches draped over a bare branch in a desert"),
            ("collectible-pop_can_grid", "a framed pop-art painting of a tidy grid of colorful identical soup cans"),
            ("collectible-water_garden", "a framed impressionist painting of pink water lilies floating on a shimmering green pond"),
        ],
    },
}


def _load_token() -> str:
    tok = os.environ.get("REPLICATE_API_TOKEN")
    if tok:
        return tok.strip()
    envf = HERE / ".env"
    if envf.exists():
        for line in envf.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line.startswith("REPLICATE_API_TOKEN") and "=" in line:
                return line.split("=", 1)[1].strip().strip('"').strip("'")
    sys.exit(
        "[error] REPLICATE_API_TOKEN 未设置。\n"
        "  export REPLICATE_API_TOKEN=r8_xxx   或   "
        "echo 'REPLICATE_API_TOKEN=r8_xxx' > tools/art/.env"
    )


def _prompt_for(subject: str, style: str = "icon") -> str:
    return f"{subject}, {_STYLES.get(style, STYLE)}"


def _download(output, dest: Path) -> None:
    """Replicate 输出可能是 FileOutput / URL str / 它们的 list; 统一落盘为 PNG。"""
    if isinstance(output, list):
        if not output:
            raise RuntimeError("模型返回空输出列表")
        output = output[0]
    # FileOutput (replicate>=0.25): 有 .read() 直接拿 bytes。
    if hasattr(output, "read"):
        data = output.read()
        dest.write_bytes(data)
        return
    url = getattr(output, "url", None) or (output if isinstance(output, str) else None)
    if not url:
        raise RuntimeError(f"无法识别的模型输出类型: {type(output)!r}")
    resp = requests.get(url, timeout=120)
    resp.raise_for_status()
    dest.write_bytes(resp.content)


def _probe(model_key: str) -> None:
    import replicate

    ref = MODELS[model_key]["ref"]
    owner, name = ref.split("/", 1)
    model = replicate.models.get(f"{owner}/{name}")
    ver = model.latest_version
    schema = ver.openapi_schema if ver else {}
    inp = (
        schema.get("components", {})
        .get("schemas", {})
        .get("Input", {})
        .get("properties", {})
    )
    print(f"# {ref}  (version {getattr(ver, 'id', '?')[:12]})")
    for pname, spec in inp.items():
        enum = spec.get("enum")
        default = spec.get("default")
        line = f"  {pname}: {spec.get('type', spec.get('allOf', '?'))}"
        if default is not None:
            line += f"  default={default!r}"
        if enum:
            line += f"  enum={enum}"
        print(line)


def _generate_one(model_key: str, label: str, subject: str, seed: int | None,
                  style: str = "icon", aspect: str = "1:1") -> Path:
    import replicate

    ref = MODELS[model_key]["ref"]
    build = MODELS[model_key]["build"]
    prompt = _prompt_for(subject, style)
    out_dir = RUNS / label
    out_dir.mkdir(parents=True, exist_ok=True)

    LOGGER.info("[gen] %s via %s (seed=%s, aspect=%s)", label, ref, seed, aspect)
    t0 = time.time()
    output = replicate.run(ref, input=build(prompt, seed, aspect))
    raw = out_dir / "raw.png"
    _download(output, raw)
    dt = time.time() - t0

    (out_dir / "prompt-used.txt").write_text(
        f"# model: {ref}\n# seed: {seed}\n# generator: replicate\n\n{prompt}\n",
        encoding="utf-8",
    )
    (out_dir / "gen-meta.json").write_text(
        json.dumps(
            {"label": label, "model": ref, "seed": seed, "subject": subject,
             "prompt": prompt, "raw": str(raw), "elapsed_s": round(dt, 1)},
            indent=2, ensure_ascii=False,
        ),
        encoding="utf-8",
    )
    LOGGER.info("[ok] %s -> %s  (%.1fs)", label, raw, dt)
    return raw


def _process_one(label: str, raw: Path, threshold: int, edge_threshold: int,
                 reject_edge: bool = True, component_mode: str = "largest",
                 flood_bg: bool = False, defringe: int = 0,
                 background_mode: str = "chroma",
                 background_tolerance: int | None = None) -> int:
    """链式调用 process_asset.py single (同一 venv python)。

    阈值偏高 (默认 180/195): flux 把"magenta"渲染成粉洋红 (距纯洋红 ~135),
    而主体是冷色蓝/白 (距 ~245+), 高阈值能干净切分背景又不吃主体。
    reject_edge=False 给"主体本就铺满画面"的批次 (人物半身像 / 复杂图标): 不因触边判废,
    harness 仍裁到内容 bbox + 居中 + 缩到 82%, 结果照样有留白。
    """
    cmd = [
        sys.executable, str(HERE / "process_asset.py"), "single",
        "--input", str(raw),
        "--output-dir", str(raw.parent),
        "--name", label,
        "--size", "128", "--fit-scale", "0.82",
        "--component-mode", component_mode,
        "--threshold", str(threshold), "--edge-threshold", str(edge_threshold),
        "--background-mode", background_mode,
        "--trim-border", "6",
        "--prompt-file", str(raw.parent / "prompt-used.txt"),
    ]
    if background_tolerance is not None:
        cmd += ["--background-tolerance", str(background_tolerance)]
    if reject_edge:
        cmd.append("--reject-edge-touch")
    if flood_bg:
        cmd.append("--flood-bg")  # flux 常无视 magenta 底 → 先漫水重染再去背
    if defringe > 0:
        cmd += ["--defringe", str(defringe)]  # 削去背残留白边/混色边
    LOGGER.info("[post] %s", " ".join(cmd[2:]))
    return subprocess.run(cmd).returncode


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--list", action="store_true", help="列出批次与每档 prompt 后退出")
    ap.add_argument("--probe", action="store_true", help="打印所选模型真实入参 schema 后退出")
    ap.add_argument("--batch", default="infra_buildings", help="批次名 (见 BATCHES)")
    ap.add_argument("--only", help="只生成批次里的某个 label")
    ap.add_argument("--model", default=DEFAULT_MODEL, choices=list(MODELS), help="生成模型 preset")
    ap.add_argument("--seed", type=int, default=None, help="覆盖批次默认 seed")
    ap.add_argument("--process", action="store_true", help="生成后立刻跑 process_asset.py single")
    ap.add_argument("--threshold", type=int, default=180, help="去背洋红阈值 (flux 粉洋红需偏高)")
    ap.add_argument("--edge-threshold", type=int, default=195, help="边缘去背洋红阈值")
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args(argv)

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="[%(levelname)s] [art] %(message)s",
    )

    if args.list:
        for bname, spec in BATCHES.items():
            bstyle = spec.get("style", "icon")
            print(f"# batch {bname}  (seed={spec['seed']}, style={bstyle}, {len(spec['assets'])} assets)")
            for label, subject in spec["assets"]:
                print(f"  {label:28s} {_prompt_for(subject, bstyle)}")
        return 0

    if args.batch not in BATCHES:
        sys.exit(f"[error] 未知批次 {args.batch!r}; 可选: {', '.join(BATCHES)}")

    os.environ["REPLICATE_API_TOKEN"] = _load_token()

    if args.probe:
        _probe(args.model)
        return 0

    spec = BATCHES[args.batch]
    seed = args.seed if args.seed is not None else spec.get("seed")
    style = spec.get("style", "icon")
    aspect = spec.get("aspect", "1:1")
    reject_edge = spec.get("reject_edge", True)
    component_mode = spec.get("component_mode", "largest")
    flood_bg = spec.get("flood_bg", False)
    defringe = spec.get("defringe", 0)
    background_mode = spec.get("background_mode", "chroma")
    background_tolerance = spec.get("background_tolerance")
    assets = spec["assets"]
    if args.only:
        assets = [(l, s) for (l, s) in assets if l == args.only]
        if not assets:
            sys.exit(f"[error] 批次 {args.batch!r} 里没有 label {args.only!r}")

    failures: list[str] = []
    for label, subject in assets:
        try:
            raw = _generate_one(args.model, label, subject, seed, style, aspect)
        except Exception as exc:  # 单档失败不拖垮整批
            LOGGER.error("[fail] %s 生成失败: %s", label, exc)
            failures.append(label)
            continue
        if args.process:
            rc = _process_one(label, raw, args.threshold, args.edge_threshold,
                              reject_edge, component_mode, flood_bg, defringe,
                              background_mode, background_tolerance)
            if rc != 0:
                LOGGER.error("[fail] %s 后处理未通过 (见 pipeline-meta.json)", label)
                failures.append(label)

    done = len(assets) - len(failures)
    LOGGER.info("[done] %d/%d ok%s", done, len(assets),
                ("; 失败: " + ", ".join(failures)) if failures else "")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
