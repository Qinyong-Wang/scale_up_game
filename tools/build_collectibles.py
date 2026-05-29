#!/usr/bin/env python3
"""Generate the collectible .tres files under resources/data/collectibles/.

Each of the 5 categories (crypto / trading_card / ai_hardware / supercar /
painting) gets 15-25 fictional items spanning a wide price range, with a few
1B+ "relic" grails. Names obey the 化名规范 (no real brands).

Per design/办公室与收藏系统设计.md §2/§9. Run from repo root:

    python3 tools/build_collectibles.py

The market price curve is computed from a per-category SHAPE (fractions of the
item's `peak` price at year knots) anchored at the item's debut year and capped
at 2070. Two test-fixture items (genesis_coin_7, first_ai_card) use explicit
curve OVERRIDES so tests stay deterministic.

This script ALSO merges the English translations of every item's display_name /
description into resources/i18n/content.csv (源中文串当 key, preserving all other
entries) so the i18n coverage contract holds. Rebuild .translation afterwards:

    godot --headless --path . -s tools/build_translations.gd
"""
import csv
import glob
import os

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(REPO, "resources", "data", "collectibles")
CONTENT_CSV = os.path.join(REPO, "resources", "i18n", "content.csv")
SCRIPT_PATH = "res://scripts/resources/collectible_spec.gd"

# Per-category appreciation shape: debut fraction + (year, fraction-of-peak)
# knots (ascending, last knot is 2070 @ 1.0 = the price cap).
SHAPES = {
    "crypto":       {"debut": 0.0002, "knots": [(2025, 0.06), (2035, 0.45), (2070, 1.0)]},
    "trading_card": {"debut": 0.02,   "knots": [(2025, 0.25), (2045, 0.65), (2070, 1.0)]},
    "ai_hardware":  {"debut": 0.0008, "knots": [(2035, 0.05), (2055, 0.35), (2070, 1.0)]},
    "supercar":     {"debut": 0.30,   "knots": [(2040, 0.70), (2070, 1.0)]},
    "painting":     {"debut": 0.50,   "knots": [(2040, 0.80), (2070, 1.0)]},
}

# Explicit curves for test-fixture items (years, prices). Keep in sync with
# tests/unit/collection_system_test.gd.
OVERRIDES = {
    "genesis_coin_7": ([2017, 2025, 2035, 2070], [1000, 500000, 3000000, 8000000]),
    "first_ai_card":  ([2017, 2035, 2055, 2070], [5000, 50000000, 2000000000, 8000000000]),
}

# Item: (id, name_zh, name_en, desc_zh, desc_en, peak, debut)
ITEMS = {
    "crypto": [
        ("genesis_coin_7", "创世矿工·第 7 枚金币", "Genesis Miner — Coin No. 7",
         "去中心化货币最早挖出的几枚之一，编号 7。早期近乎一文不值，后来涨成天文数字。",
         "One of the very first coins ever mined on a decentralized currency, numbered 7. Nearly worthless early on, later astronomically valuable.",
         8_000_000_000, 2017),
        ("zero_block_relic", "零号区块·铭牌", "Block Zero Plaque",
         "链上第一个区块铸成的实体铭牌，万链之始。", "A physical plaque of the very first block on chain — the origin of every ledger.",
         12_000_000_000, 2017),
        ("cypherpunk_mail", "密码朋克·创始邮件 NFT", "Cypherpunk Founding Email NFT",
         "那封点燃加密革命的原始邮件，铸成唯一 NFT。", "The original email that lit the crypto revolution, minted as a one-of-one NFT.",
         3_000_000_000, 2018),
        ("first_smart_contract", "首个智能合约·铭文", "First Smart-Contract Inscription",
         "链上第一份可执行合约的铭文拓本。", "A rubbing of the first executable contract ever deployed on chain.",
         2_000_000_000, 2019),
        ("lost_wallet_fragment", "遗失钱包·私钥残片", "Lost-Wallet Key Fragment",
         "传说中天价钱包流出的私钥残片。", "A fragment of the private key leaked from a legendary fortune wallet.",
         1_500_000_000, 2018),
        ("pixel_ape_0001", "像素猿 #0001", "Pixel Ape #0001",
         "头像 NFT 浪潮的开山之作，编号 0001。", "The founding ape of the avatar-NFT craze, #0001.",
         900_000_000, 2021),
        ("quantum_resist_coin", "抗量子链·创世币", "Quantum-Resistant Genesis Coin",
         "第一条声称能抗量子破解的链的创世币。", "Genesis coin of the first chain claiming quantum resistance.",
         600_000_000, 2024),
        ("meme_shiba_genesis", "柴犬梗币·创世空投", "Meme-Dog Genesis Drop",
         "一场玩笑造出的梗币，创世空投钱包。", "A joke that became a coin — the genesis airdrop wallet.",
         500_000_000, 2020),
        ("cold_titanium_plate", "冷存储·钛金助记板", "Cold-Storage Titanium Plate",
         "刻着十二个助记词的钛板，沉睡多年的财富。", "A titanium plate engraved with twelve seed words — wealth that slept for years.",
         450_000_000, 2018),
        ("dark_market_ghost", "暗网时代·幽灵币", "Dark-Era Ghost Coin",
         "早期暗网交易里流通过的匿名币，来历成谜。", "An anonymous coin that circulated on the early dark web; its history a mystery.",
         350_000_000, 2019),
        ("fork_war_snapshot", "分叉之战·共识快照", "Fork-War Consensus Snapshot",
         "社区大分裂时刻的链上共识快照。", "The on-chain consensus snapshot from the great community split.",
         300_000_000, 2021),
        ("dao_constitution_nft", "首个 DAO·章程 NFT", "First DAO Charter NFT",
         "第一个去中心化自治组织的章程铸成的 NFT。", "The charter of the first DAO, minted as an NFT.",
         300_000_000, 2022),
        ("defi_genesis_lp", "DeFi 创世流动性凭证", "DeFi Genesis LP Token",
         "自动做市商时代的第一张流动性凭证。", "The first liquidity token from the dawn of automated market makers.",
         250_000_000, 2020),
        ("halving_relic", "减半之夜·纪念铭牌", "Halving-Night Relic",
         "产量减半那一夜铸下的纪念铭牌。", "A relic minted on the night the block reward halved.",
         200_000_000, 2020),
        ("stablecoin_proto", "稳定币原型·测试网币", "Stablecoin Prototype Coin",
         "第一版稳定币在测试网发行的纪念币。", "The first stablecoin's commemorative testnet issue.",
         120_000_000, 2019),
        ("miner_signed_board", "矿工主板·签名版", "Miner's Signed Mainboard",
         "早期矿工亲笔签名的二手矿机主板。", "A used mining mainboard signed by an early miner.",
         80_000_000, 2017),
    ],
    "trading_card": [
        ("holy_dragon_gem", "圣龙·满分鉴定卡", "Holy Dragon, Gem-Mint",
         "鉴定满分的圣龙稀有卡，藏家终极目标。", "A gem-mint graded Holy Dragon — a collector's ultimate grail.",
         2_000_000_000, 1999),
        ("illustrator_award", "插画师·特别赏卡", "Illustrator Special-Award Card",
         "颁给插画大赛优胜者的极少量奖卡。", "An ultra-rare card awarded to the winner of an illustration contest.",
         1_500_000_000, 2000),
        ("flame_beast_card", "初版·炎兽闪卡", "First-Edition Flame-Beast Holo Card",
         "一代人童年的怪兽对战卡，初版闪卡存世稀少。怀旧情绪推着它在收藏市场一路走高。",
         "The monster-battle card of a generation's childhood; first-edition holos are vanishingly rare. Nostalgia keeps pushing its price ever higher.",
         1_200_000_000, 2017),
        ("tournament_champion", "世界赛·冠军限定卡", "World-Championship Winner Card",
         "只发给世界冠军的限定奖励卡。", "A trophy card handed only to a world champion.",
         900_000_000, 2005),
        ("banned_first_print", "禁卡·初版", "Banned Card, First Print",
         "因太强被禁、初版存世稀少的卡。", "Banned for being too strong; first prints barely survive.",
         700_000_000, 2003),
        ("error_inverted_holo", "错印·倒置闪卡", "Inverted Misprint Holo",
         "印刷错误造就的孤品倒置闪卡。", "A one-off inverted holo born of a printing error.",
         600_000_000, 2001),
        ("mascot_card_zero", "吉祥物·零号卡", "Mascot Card No.0",
         "系列吉祥物的编号 0 测试卡。", "The No.0 test card of a series mascot.",
         550_000_000, 2007),
        ("beta_resource_card", "内测·基础资源卡", "Beta Basic Resource Card",
         "集换卡鼻祖游戏的内测基础卡。", "A beta basic card from the game that founded the trading-card genre.",
         500_000_000, 1993),
        ("crystal_phoenix", "水晶凤凰·全息卡", "Crystal Phoenix Foil",
         "折射七彩的水晶凤凰全息卡。", "A crystal phoenix foil that refracts every color.",
         300_000_000, 2012),
        ("full_art_secret", "隐藏稀有·全图卡", "Secret-Rare Full-Art",
         "拆包率极低的隐藏稀有全图卡。", "A secret-rare full-art with a vanishing pull rate.",
         200_000_000, 2015),
        ("shadow_knight_alpha", "暗影骑士·内测卡", "Shadow Knight Alpha Card",
         "某卡牌游戏内测时发出的限量卡。", "A limited card handed out during a game's alpha test.",
         400_000_000, 2010),
        ("grandmaster_deck", "大师赛·夺冠卡组", "Grandmaster Winning Deck",
         "某届大师赛夺冠的完整卡组。", "The complete deck that won a grandmaster championship.",
         600_000_000, 2011),
        ("signed_artist_holo", "画师亲签·闪卡", "Artist-Signed Holo",
         "原画师亲笔签名的闪卡。", "A holo signed by its original illustrator.",
         120_000_000, 2006),
        ("sealed_starter", "初版·未拆起始包", "Sealed First-Print Starter",
         "从未拆封的初版起始套牌。", "A never-opened first-print starter deck.",
         150_000_000, 2002),
        ("gold_foil_promo", "黄金箔·活动促销卡", "Gold-Foil Promo Card",
         "限定活动发放的黄金箔促销卡。", "A gold-foil promo handed out at a limited event.",
         80_000_000, 2008),
        ("schoolyard_champ", "校园赛·纪念卡", "Schoolyard-Champ Card",
         "一代人校园对战的纪念冠军卡。", "A champ card from a generation's schoolyard battles.",
         40_000_000, 2004),
    ],
    "ai_hardware": [
        ("first_ai_card", "第一台 AI 训练卡", "The First AI Training Card",
         "点燃整个智能时代的那块初代训练加速卡。随着 AI 写进历史，它从一块旧硬件变成博物馆级藏品。",
         "The first-gen training accelerator that ignited the whole age of intelligence. As AI is written into history, it turns from old hardware into a museum-grade artifact.",
         8_000_000_000, 2017),
        ("founder_signed_gpu", "创始团队·签名加速卡", "Founder-Signed Accelerator",
         "某 AI 巨头创始团队签名的元老加速卡。", "A veteran accelerator signed by an AI giant's founding team.",
         6_000_000_000, 2018),
        ("wafer_scale_relic", "晶圆级·巨芯样片", "Wafer-Scale Mega-Chip",
         "整片晶圆做成的一颗巨型芯片样片。", "A mega-chip sample built from an entire silicon wafer.",
         5_000_000_000, 2019),
        ("first_tensor_board", "初代张量板卡", "First Tensor Board",
         "第一块为矩阵运算专门设计的板卡。", "The first board designed purpose-built for matrix math.",
         4_000_000_000, 2016),
        ("lab_prototype_accel", "实验室·定制加速原型", "Lab Custom Accelerator Prototype",
         "高校实验室手工焊出的早期训练加速原型。", "An early training-accelerator prototype hand-soldered in a university lab.",
         3_000_000_000, 2016),
        ("cluster_node_zero", "集群·零号节点卡", "Cluster Node No.0",
         "第一座大规模训练集群的零号节点卡。", "Node No.0 from the first large-scale training cluster.",
         2_000_000_000, 2019),
        ("photonic_accel_proto", "光子加速·原型", "Photonic Accelerator Prototype",
         "用光而非电跑运算的加速原型。", "A prototype that computes with light instead of electricity.",
         1_500_000_000, 2025),
        ("inference_asic_v1", "初代推理 ASIC", "First-Gen Inference ASIC",
         "第一代专用推理芯片的工程样片。", "An engineering sample of the first dedicated inference chip.",
         1_200_000_000, 2018),
        ("analog_compute_die", "模拟计算·实验芯", "Analog-Compute Experimental Die",
         "用模拟电路做矩阵乘法的实验芯片。", "An experimental die that does matrix multiply with analog circuits.",
         900_000_000, 2023),
        ("liquid_cooled_proto", "液冷·训练卡原型", "Liquid-Cooled Training Prototype",
         "第一块整卡浸没液冷的训练原型。", "The first fully immersion-cooled training prototype.",
         700_000_000, 2020),
        ("neuromorphic_chip", "类脑·神经形态芯", "Neuromorphic Chip",
         "模仿神经元脉冲的早期类脑芯片。", "An early brain-like chip that mimics neuron spikes.",
         600_000_000, 2021),
        ("overclock_record_card", "超频纪录·封存卡", "Overclock-Record Card",
         "创下超频世界纪录后封存的那块卡。", "The very card sealed away after setting an overclocking world record.",
         400_000_000, 2015),
        ("edge_chip_first", "初代·端侧推理芯片", "First Edge Inference Chip",
         "第一颗能塞进手机的推理芯片。", "The first inference chip small enough to fit in a phone.",
         300_000_000, 2017),
        ("data_center_busbar", "初代训练机房·铜排", "First Training-Cluster Busbar",
         "第一座超大训练机房拆下的供电铜排。", "A power busbar salvaged from the first hyperscale training cluster.",
         20_000_000, 2018),
        ("retro_gamer_gpu", "复古·玩家显卡", "Retro Gamer GPU",
         "被科学家拿去跑神经网络的老游戏显卡。", "An old gaming GPU that scientists repurposed to run neural nets.",
         5_000_000, 2012),
        ("retired_mining_card", "退役·矿卡", "Retired Mining Card",
         "矿潮退去后流落的二手矿卡。", "A second-hand mining card cast off after the boom faded.",
         800_000, 2017),
    ],
    "supercar": [
        ("le_mans_winner", "勒芒级·夺冠原型", "Endurance-Race Winning Prototype",
         "夺得耐力赛冠军的原厂原型车。", "A works prototype that won an endurance race.",
         600_000_000, 1970),
        ("silver_arrow_classic", "银箭·古典赛车", "Silver Arrow Classic Racer",
         "上世纪传奇的银色古典赛车。", "A legendary silver classic racer from the last century.",
         500_000_000, 1955),
        ("coachbuilt_one_off", "定制车身·孤品", "Coachbuilt One-Off",
         "富豪定制、全球唯一车身的孤品。", "A one-off with bodywork built for a single tycoon.",
         450_000_000, 2008),
        ("midnight_comet_le", "午夜彗星·限量版", "Midnight Comet, Limited",
         "全球仅造数台的午夜彗星限量超跑。", "A Midnight Comet hypercar built in mere single digits.",
         400_000_000, 2014),
        ("founder_hyper_one", "创始人·一号超跑", "Founder's Hypercar No.1",
         "某车厂创始人亲驾的一号车。", "Car No.1, driven by a marque's own founder.",
         350_000_000, 1990),
        ("last_v12_manual", "末代·V12 手动超跑", "Last V12 Manual",
         "内燃机时代末代 V12 手动挡超跑。", "The last V12 manual hypercar of the combustion era.",
         300_000_000, 2019),
        ("royal_limousine", "御用·定制礼车", "Royal Custom Limousine",
         "为王室定制的一台礼宾车。", "A ceremonial limousine custom-built for royalty.",
         300_000_000, 1965),
        ("turbine_concept", "概念·燃气轮机车", "Turbine Concept Car",
         "用燃气轮机驱动的传奇概念车。", "A legendary concept car driven by a gas turbine.",
         250_000_000, 1963),
        ("gullwing_classic", "鸥翼·古典跑车", "Gullwing Classic",
         "鸥翼车门的古典名跑。", "A classic with iconic gullwing doors.",
         220_000_000, 1958),
        ("electric_record_car", "电动·极速纪录车", "Electric Top-Speed Record Car",
         "刷新电动极速纪录的那台车。", "The car that broke the electric top-speed record.",
         200_000_000, 2022),
        ("rally_legend", "拉力传奇·夺冠车", "Rally Legend Winner",
         "称霸一个时代的拉力赛冠军车。", "A rally winner that dominated an entire era.",
         180_000_000, 1985),
        ("track_only_extreme", "赛道专属·极限版", "Track-Only Extreme",
         "不能上路、只为赛道而生的极限版。", "A track-only extreme, never road-legal.",
         160_000_000, 2016),
        ("phantom_gt", "极速幻影 GT", "Velocity Phantom GT",
         "全球限量的手工超跑，引擎绝唱之作。经典名车稳健增值，是车库里的硬通货。",
         "A globally limited, hand-built hypercar — the swan song of the combustion engine. Classic cars appreciate steadily; hard currency for the garage.",
         150_000_000, 2017),
        ("solar_concept", "太阳能·概念跑车", "Solar Concept Roadster",
         "车顶铺满太阳能板的概念跑车。", "A concept roadster roofed in solar panels.",
         140_000_000, 2021),
        ("prototype_mule", "工程·试验骡车", "Engineering Mule",
         "量产前唯一存世的工程试验车。", "The sole surviving engineering test mule from before production.",
         120_000_000, 2011),
    ],
    "painting": [
        ("starry_vortex", "《星夜旋涡》", "\"Starry Vortex\"",
         "一代大师笔下旋转的星空，蓝筹艺术品的代名词。后期资金溢出时最大的吸金口。",
         "A master's swirling night sky, synonymous with blue-chip art. The biggest cash sink once money overflows in the late game.",
         1_500_000_000, 1889),
        ("salvator_cosmos", "《救世·寰宇》", "\"Salvator of the Cosmos\"",
         "真伪争议不断却屡破纪录的旷世名作。", "A contested masterpiece that keeps breaking records.",
         1_500_000_000, 1500),
        ("ink_mountains", "《千里江山·墨卷》", "\"Ten-Thousand-Li Ink Scroll\"",
         "千年传世的青绿山水长卷。", "A thousand-year-old blue-green landscape handscroll.",
         1_300_000_000, 1113),
        ("weeping_lady", "《垂泪贵妇》", "\"The Weeping Lady\"",
         "神秘微笑之外，另一幅传世贵妇像。", "Beyond the famous smile — another timeless portrait of a lady.",
         1_200_000_000, 1505),
        ("echo_scream", "《回声尖叫》", "\"Echo of the Scream\"",
         "表现主义的焦虑呐喊。", "Expressionism's cry of anxiety.",
         1_100_000_000, 1893),
        ("gilded_kiss", "《镀金之吻》", "\"The Gilded Kiss\"",
         "金箔满布、世人皆识的拥吻名画。", "A gold-leafed embrace everyone recognizes.",
         900_000_000, 1908),
        ("blue_period_boy", "《蓝色时期·少年》", "\"Blue-Period Boy\"",
         "巨匠蓝色时期的忧郁少年像。", "A melancholy boy from a master's blue period.",
         800_000_000, 1903),
        ("master_self_portrait", "《巨匠·自画像》", "\"Master's Self-Portrait\"",
         "巨匠晚年凝视自我的自画像。", "A master gazing at himself in old age.",
         700_000_000, 1660),
        ("cubist_figure", "《立体女像》", "\"Cubist Figure\"",
         "把人脸拆成几何块面的立体派名作。", "A cubist masterpiece that shatters a face into facets.",
         600_000_000, 1910),
        ("night_cafe", "《夜咖啡馆》", "\"The Night Café\"",
         "浓烈黄绿、令人不安的夜咖啡馆。", "A night café in unsettling yellows and greens.",
         500_000_000, 1888),
        ("abstract_red_field", "《赤色场域》", "\"Red Field\"",
         "一整块红色震撼拍场的抽象巨作。", "A vast field of red that stuns the auction floor.",
         500_000_000, 1961),
        ("dripping_chaos", "《滴流混沌》", "\"Dripping Chaos\"",
         "颜料滴洒而成的抽象表现巨幅。", "A huge abstract-expressionist canvas of dripped paint.",
         450_000_000, 1950),
        ("melting_clocks", "《融化的钟》", "\"Melting Clocks\"",
         "超现实主义的软塌时钟。", "Surrealism's limp, melting clocks.",
         350_000_000, 1931),
        ("pop_can_grid", "《罐头方阵》", "\"Cans in a Grid\"",
         "波普艺术的标志性罐头方阵。", "Pop art's iconic grid of cans.",
         300_000_000, 1962),
        ("water_garden", "《水园睡莲》", "\"Lilies of the Water Garden\"",
         "大师晚年光影斑斓的睡莲组画之一。", "One of a master's late, shimmering water-lily canvases.",
         400_000_000, 1916),
    ],
}


def esc(s):
    return s.replace("\\", "\\\\").replace('"', '\\"')


def weight_for(peak):
    # Rarity = auction appearance weight, inverse to price tier. Per design §8.3.
    if peak >= 2_000_000_000:
        return 0.08   # relic-tier grail — rare
    if peak >= 500_000_000:
        return 0.2
    if peak >= 50_000_000:
        return 0.5
    return 1.0        # cheap — common


def compute_curve(category, peak, debut):
    shape = SHAPES[category]
    years = [debut]
    prices = [max(1, round(peak * shape["debut"]))]
    for y, f in shape["knots"]:
        if y > debut:
            years.append(y)
            prices.append(round(peak * f))
    # Guarantee a 2070 cap keyframe.
    if years[-1] != 2070:
        years.append(2070)
        prices.append(peak)
    return years, prices


def write_tres(item):
    cid, zh, _en, dzh, _den, peak, debut, cat = item
    if cid in OVERRIDES:
        years, prices = OVERRIDES[cid]
    else:
        years, prices = compute_curve(cat, peak, debut)
    years_s = ", ".join(str(y) for y in years)
    prices_s = ", ".join(str(p) for p in prices)
    body = (
        '[gd_resource type="Resource" script_class="CollectibleSpec" load_steps=2 format=3]\n\n'
        f'[ext_resource type="Script" path="{SCRIPT_PATH}" id="1_col"]\n\n'
        '[resource]\n'
        'script = ExtResource("1_col")\n'
        f'id = &"{cid}"\n'
        f'category = &"{cat}"\n'
        f'display_name = "{esc(zh)}"\n'
        f'description = "{esc(dzh)}"\n'
        f'curve_years = Array[int]([{years_s}])\n'
        f'curve_prices = Array[int]([{prices_s}])\n'
        f'appear_weight = {weight_for(peak)}\n'
    )
    with open(os.path.join(OUT_DIR, cid + ".tres"), "w", encoding="utf-8") as f:
        f.write(body)


def merge_content_csv(pairs):
    existing = {}
    if os.path.exists(CONTENT_CSV):
        with open(CONTENT_CSV, encoding="utf-8", newline="") as f:
            reader = csv.reader(f)
            next(reader, None)
            for row in reader:
                if row and row[0]:
                    existing[row[0]] = row[1] if len(row) > 1 else ""
    for zh, en in pairs.items():
        existing[zh] = en
    with open(CONTENT_CSV, "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(["keys", "en"])
        for key in sorted(existing):
            w.writerow([key, existing[key]])


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    # Clear stale collectible .tres so removed items don't linger. Keep
    # auction_tuning.tres (lives here but isn't a collectible spec).
    for old in glob.glob(os.path.join(OUT_DIR, "*.tres")):
        if os.path.basename(old) == "auction_tuning.tres":
            continue
        os.remove(old)

    pairs = {}
    total = 0
    for cat, items in ITEMS.items():
        for it in items:
            cid, zh, en, dzh, den, peak, debut = it
            write_tres((cid, zh, en, dzh, den, peak, debut, cat))
            pairs[zh] = en
            pairs[dzh] = den
            total += 1
        print(f"  {cat}: {len(items)} items")
    merge_content_csv(pairs)
    print(f"collectibles: wrote {total} .tres; merged {len(pairs)} en strings into content.csv")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
