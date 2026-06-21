#!/usr/bin/env python3
"""One-shot generator for resources/data/npcs/*.tres (v8 PR-H).

Usage:
    python3 tools/build_npc_timelines.py

Writes 23 NpcCompany .tres files, each containing an inline `model_releases`
array of NpcModelRelease sub-resources spanning 2018-2042+. Per
design/竞争对手系统设计.md §1 + design/NPC配置.md §2.

Release tuple format (one row per release):
    (id_suffix, display_name, turn, [g, c, r, m, a],
     kind, gpu_id, gpu_count, weeks, params_b, active_b, tokens_b, arch)

- turn 0 = 2017-06-12; turn 52 ≈ 1 year. The timeline cluster size cadence
  follows 设计文档 §2.1 (early → mid → high-end → frontier → future).
- Sub-board NPCs use one tier smaller clusters than the main-board frontier of
  the same year; they specialize in one axis.
- Open-source NPCs lag ~25-35 weeks behind closed-source same-gen models.
- NPC release total capability is capped at 1100 by proportional scaling before
  writing .tres, keeping competitors in the player-reachable 1000-1100 band.

Run after editing this file. The script is idempotent (overwrites .tres).
"""

import os
from pathlib import Path
from typing import List, Tuple

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "resources" / "data" / "npcs"
NPC_TOTAL_CAP = 1100.0

Release = Tuple[
    str,           # id_suffix
    str,           # display_name
    int,           # release_turn
    List[float],   # capability [g, c, r, m, a]
    str,           # release_kind
    str,           # cluster_gpu_id
    int,           # cluster_gpu_count
    int,           # training_weeks
    float,         # params_b
    float,         # active_params_b
    float,         # dataset_tokens_b
    str,           # arch_codename
]

# ============================================================================
# MAIN BOARD (5 NPCs) — frontier labs with full 2018→2042 timelines.
# ============================================================================

ORCA_LAB: List[Release] = [
    ("orca_1",      "Orca-1",      70,   [6, 2, 3, 0, 0],     "pretrain",            "cypress_t0", 500,    16, 0.117, 0.117, 8,      "ant_v1"),
    ("orca_1_5",    "Orca-1.5",    100,  [8, 3, 4, 0, 0],     "pretrain",            "cypress_t0", 800,    18, 0.350, 0.350, 15,     "ant_v1"),
    ("orca_2",      "Orca-2",      130,  [12, 4, 6, 0, 0],    "pretrain",            "cypress_t0", 2000,   20, 1.5,   1.5,   40,     "ant_v2"),
    ("orca_2_5",    "Orca-2.5",    155,  [17, 6, 9, 0, 0],    "pretrain",            "cypress_t0", 2500,   22, 6.0,   6.0,   60,     "ant_v2"),
    ("orca_3",      "Orca-3",      175,  [28, 14, 18, 0, 0],  "pretrain",            "cypress_t1", 6000,   28, 175,   175,   300,    "ant_v3"),
    ("orca_3_1",    "Orca-3.1",    210,  [32, 17, 22, 2, 0],  "rlhf",                "",           0,      0,  0,     0,     0,      ""),
    ("orca_3_5",    "Orca-3.5",    240,  [42, 26, 32, 8, 3],  "rlhf",                "",           0,      0,  0,     0,     0,      ""),
    ("orca_3_7",    "Orca-3.7",    270,  [46, 30, 38, 12, 8], "tool_use_posttrain",  "",           0,      0,  0,     0,     0,      ""),
    ("orca_3_9",    "Orca-3.9",    290,  [52, 38, 46, 18, 12], "rlhf",               "",           0,      0,  0,     0,     0,      ""),
    ("orca_4",      "Orca-4",      300,  [78, 65, 70, 30, 15], "pretrain",           "cypress_t2", 16000,  25, 1500,  220,   13000,  "octopus_v2"),
    ("orca_4_1",    "Orca-4.1",    325,  [80, 67, 72, 32, 18], "rlhf",               "",           0,      0,  0,     0,     0,      ""),
    ("orca_4_5",    "Orca-4.5",    348,  [84, 72, 76, 55, 25], "pretrain",           "cypress_t2", 24000,  22, 1800,  260,   18000,  "octopus_v2"),
    ("orca_4o",     "Orca-4o",     365,  [86, 70, 74, 85, 28], "multimodal_posttrain", "",         0,      0,  0,     0,     0,      ""),
    ("orca_o1",     "Orca-o1",     380,  [83, 72, 95, 72, 40], "reasoning_rl",       "",           0,      0,  0,     0,     0,      ""),
    ("orca_o1_5",   "Orca-o1.5",   395,  [88, 78, 108, 78, 52], "reasoning_rl",      "",           0,      0,  0,     0,     0,      ""),
    ("orca_4_7",    "Orca-4.7",    415,  [95, 86, 95, 88, 55], "pretrain",           "cypress_t3", 50000,  24, 2500,  360,   25000,  "octopus_v2"),
    ("orca_5",      "Orca-5",      425,  [108, 92, 118, 95, 68], "pretrain",         "cypress_t3", 80000,  28, 3000,  420,   30000,  "octopus_sparse"),
    ("orca_5_1",    "Orca-5.1",    445,  [110, 95, 122, 98, 72], "rlhf",             "",           0,      0,  0,     0,     0,      ""),
    ("orca_5_5",    "Orca-5.5",    465,  [115, 100, 130, 102, 78], "reasoning_rl",   "",           0,      0,  0,     0,     0,      ""),
    ("orca_6",      "Orca-6",      480,  [125, 115, 138, 115, 92], "pretrain",       "cypress_t3", 150000, 26, 6000,  800,   50000,  "octopus_sparse"),
    ("orca_6_5",    "Orca-6.5",    505,  [133, 123, 148, 122, 103], "rlhf",          "",           0,      0,  0,     0,     0,      ""),
    ("orca_7",      "Orca-7",      530,  [148, 138, 162, 132, 118], "pretrain",      "cypress_t3", 300000, 28, 10000, 1300,  75000,  "octopus_sparse"),
    ("orca_7_5",    "Orca-7.5",    555,  [156, 146, 172, 140, 130], "rlhf",          "",           0,      0,  0,     0,     0,      ""),
    ("orca_8",      "Orca-8",      605,  [175, 166, 198, 162, 155], "pretrain",      "cypress_t3", 600000, 28, 15000, 1900,  100000, "octopus_super_sparse"),
    ("orca_8_5",    "Orca-8.5",    635,  [185, 178, 210, 172, 168], "reasoning_rl",  "",           0,      0,  0,     0,     0,      ""),
    ("orca_9",      "Orca-9",      665,  [200, 194, 228, 188, 188], "pretrain",      "cypress_t3", 1000000, 28, 22000, 2700, 140000, "octopus_super_sparse"),
    ("orca_10",     "Orca-10",     725,  [225, 222, 258, 214, 220], "pretrain",      "cypress_t3", 1700000, 28, 32000, 3800, 200000, "octopus_super_sparse"),
    ("orca_11",     "Orca-11",     790,  [252, 250, 288, 240, 250], "pretrain",      "cypress_t3", 2500000, 28, 45000, 5200, 280000, "octopus_super_sparse"),
    ("orca_12",     "Orca-12",     860,  [280, 278, 318, 268, 280], "pretrain",      "cypress_t3", 3500000, 28, 60000, 6800, 360000, "octopus_super_sparse"),
    ("orca_13",     "Orca-13",     930,  [310, 308, 350, 298, 312], "pretrain",      "cypress_t3", 5000000, 28, 80000, 8800, 460000, "octopus_super_sparse"),
    ("orca_14",     "Orca-14",     1000, [340, 342, 385, 328, 345], "pretrain",      "cypress_t3", 6000000, 28, 100000, 11000, 580000, "octopus_super_sparse"),
    ("orca_15",     "Orca-15",     1080, [372, 378, 420, 360, 380], "pretrain",      "cypress_t3", 7000000, 28, 130000, 14000, 720000, "octopus_super_sparse"),
    ("orca_16",     "Orca-16",     1170, [405, 415, 458, 395, 418], "pretrain",      "cypress_t3", 8000000, 28, 170000, 18000, 880000, "octopus_super_sparse"),
    ("orca_17",     "Orca-17",     1260, [440, 452, 498, 432, 458], "pretrain",      "cypress_t3", 9000000, 28, 220000, 23000, 1100000, "octopus_super_sparse"),
]

RAVEN_AI: List[Release] = [
    ("raven_1",     "Raven-1",     195,  [18, 12, 22, 0, 0],   "pretrain",           "cypress_t1", 4000,   24, 50,   50,   400,    "ant_v3"),
    ("raven_1_5",   "Raven-1.5",   235,  [25, 16, 30, 0, 0],   "rlhf",               "",           0,      0,  0,    0,    0,      ""),
    ("raven_2",     "Raven-2",     280,  [45, 30, 52, 12, 8],  "pretrain",           "cypress_t1", 6000,   26, 175,  175,  1500,   "ant_v4"),
    ("raven_2_5",   "Raven-2.5",   305,  [55, 38, 68, 22, 12], "rlhf",               "",           0,      0,  0,    0,    0,      ""),
    ("raven_3",     "Raven-3",     320,  [72, 55, 82, 38, 18], "pretrain",           "cypress_t2", 12000,  26, 1000, 150,  10000,  "octopus_v2"),
    ("raven_3_3",   "Raven-3.3",   355,  [76, 59, 86, 40, 25], "rlhf",               "",           0,      0,  0,    0,    0,      ""),
    ("raven_3_5",   "Raven-3.5",   380,  [80, 62, 90, 42, 30], "reasoning_rl",       "",           0,      0,  0,    0,    0,      ""),
    ("raven_4",     "Raven-4",     430,  [98, 82, 118, 72, 55], "pretrain",          "cypress_t3", 50000,  28, 2000, 280,  22000,  "octopus_sparse"),
    ("raven_4_5",   "Raven-4.5",   465,  [104, 88, 128, 80, 65], "reasoning_rl",     "",           0,      0,  0,    0,    0,      ""),
    ("raven_5",     "Raven-5",     500,  [112, 100, 142, 95, 85], "pretrain",        "cypress_t3", 120000, 28, 4000, 520,  38000,  "octopus_sparse"),
    ("raven_5_5",   "Raven-5.5",   545,  [122, 110, 152, 105, 100], "reasoning_rl",  "",           0,      0,  0,    0,    0,      ""),
    ("raven_6",     "Raven-6",     620,  [132, 120, 162, 120, 115], "pretrain",      "cypress_t3", 350000, 28, 9000, 1100, 70000,  "octopus_super_sparse"),
    ("raven_6_5",   "Raven-6.5",   670,  [142, 130, 175, 130, 128], "reasoning_rl",  "",           0,      0,  0,    0,    0,      ""),
    ("raven_7",     "Raven-7",     760,  [155, 142, 188, 142, 142], "pretrain",      "cypress_t3", 900000, 30, 18000, 2200, 120000, "octopus_super_sparse"),
    ("raven_7_5",   "Raven-7.5",   820,  [168, 156, 205, 156, 158], "reasoning_rl",  "",           0,      0,  0,    0,    0,      ""),
    ("raven_8",     "Raven-8",     900,  [185, 175, 225, 175, 178], "pretrain",      "cypress_t3", 1800000, 30, 30000, 3400, 200000, "octopus_super_sparse"),
    ("raven_9",     "Raven-9",     1010, [210, 202, 252, 200, 205], "pretrain",      "cypress_t3", 3000000, 30, 48000, 5400, 320000, "octopus_super_sparse"),
    ("raven_10",    "Raven-10",    1110, [240, 235, 285, 230, 238], "pretrain",      "cypress_t3", 4500000, 30, 70000, 7800, 450000, "octopus_super_sparse"),
    ("raven_11",    "Raven-11",    1210, [275, 272, 322, 265, 275], "pretrain",      "cypress_t3", 6500000, 30, 100000, 11000, 620000, "octopus_super_sparse"),
    ("raven_12",    "Raven-12",    1290, [310, 310, 365, 300, 312], "pretrain",      "cypress_t3", 8500000, 30, 140000, 15000, 820000, "octopus_super_sparse"),
]

TIGER_STUDIO: List[Release] = [
    ("tiger_1",     "Tiger-1",     100,  [8, 3, 4, 2, 0],     "pretrain",            "bamboo_t1",  2048,   22, 1,     1,     50,     "ant_v1"),
    ("tiger_1_5",   "Tiger-1.5",   145,  [14, 6, 8, 5, 0],    "pretrain",            "bamboo_t1",  3072,   22, 10,    10,    180,    "ant_v2"),
    ("tiger_2",     "Tiger-2",     200,  [32, 22, 26, 15, 0], "pretrain",            "bamboo_t2",  6144,   28, 540,   540,   800,    "ant_v3"),
    ("tiger_2_3",   "Tiger-2.3",   240,  [38, 28, 32, 22, 0], "rlhf",                "",           0,      0,  0,     0,     0,      ""),
    ("tiger_2_5",   "Tiger-2.5",   265,  [45, 35, 40, 32, 5], "multimodal_posttrain", "",          0,      0,  0,     0,     0,      ""),
    ("tiger_3",     "Tiger-3",     305,  [72, 62, 68, 55, 15], "pretrain",           "bamboo_t2",  16384,  26, 1500,  220,   15000,  "octopus_v2"),
    ("tiger_3_3",   "Tiger-3.3",   335,  [76, 65, 71, 65, 22], "rlhf",               "",           0,      0,  0,     0,     0,      ""),
    ("tiger_3_5",   "Tiger-3.5",   360,  [78, 66, 74, 88, 28], "multimodal_posttrain", "",         0,      0,  0,     0,     0,      ""),
    ("tiger_3_7",   "Tiger-3.7",   400,  [86, 76, 82, 96, 38], "reasoning_rl",       "",           0,      0,  0,     0,     0,      ""),
    ("tiger_4",     "Tiger-4",     420,  [95, 85, 96, 108, 55], "pretrain",          "bamboo_t4",  70000,  26, 2400,  340,   28000,  "octopus_sparse"),
    ("tiger_4_5",   "Tiger-4.5",   460,  [102, 92, 105, 118, 68], "multimodal_posttrain", "",      0,      0,  0,     0,     0,      ""),
    ("tiger_5",     "Tiger-5",     490,  [112, 102, 118, 130, 82], "pretrain",       "bamboo_t4",  180000, 28, 5500,  720,   46000,  "octopus_sparse"),
    ("tiger_5_5",   "Tiger-5.5",   540,  [122, 112, 128, 142, 95], "reasoning_rl",   "",           0,      0,  0,     0,     0,      ""),
    ("tiger_6",     "Tiger-6",     600,  [132, 122, 138, 152, 112], "pretrain",      "bamboo_t4",  450000, 28, 12000, 1500, 80000,  "octopus_super_sparse"),
    ("tiger_6_5",   "Tiger-6.5",   660,  [142, 132, 150, 165, 124], "multimodal_posttrain", "",    0,      0,  0,     0,     0,      ""),
    ("tiger_7",     "Tiger-7",     740,  [155, 145, 162, 178, 138], "pretrain",      "bamboo_t4",  1000000, 28, 20000, 2400, 130000, "octopus_super_sparse"),
    ("tiger_8",     "Tiger-8",     870,  [185, 175, 195, 215, 175], "pretrain",      "bamboo_t4",  2200000, 30, 35000, 4000, 230000, "octopus_super_sparse"),
    ("tiger_9",     "Tiger-9",     1000, [220, 212, 232, 252, 215], "pretrain",      "bamboo_t4",  3800000, 30, 58000, 6500, 380000, "octopus_super_sparse"),
    ("tiger_10",    "Tiger-10",    1130, [258, 252, 272, 295, 258], "pretrain",      "bamboo_t4",  5500000, 30, 85000, 9300, 540000, "octopus_super_sparse"),
    ("tiger_11",    "Tiger-11",    1250, [298, 295, 315, 340, 302], "pretrain",      "bamboo_t4",  8000000, 30, 125000, 13500, 740000, "octopus_super_sparse"),
]

FALCON_INC: List[Release] = [
    ("falcon_1",    "Falcon-1",    230,  [15, 22, 14, 0, 0],  "pretrain",            "cypress_t1", 5000,   24, 70,   70,   500,    "ant_v3"),
    ("falcon_1_5",  "Falcon-1.5",  275,  [22, 35, 20, 3, 2],  "rlhf",                "",           0,      0,  0,    0,    0,      ""),
    ("falcon_2",    "Falcon-2",    310,  [62, 82, 55, 18, 15], "pretrain",           "cypress_t2", 14000,  24, 800,  120,  8000,   "octopus_v2"),
    ("falcon_2_5",  "Falcon-2.5",  355,  [72, 92, 65, 28, 28], "tool_use_posttrain", "",           0,      0,  0,    0,    0,      ""),
    ("falcon_3",    "Falcon-3",    385,  [88, 108, 82, 52, 40], "pretrain",          "cypress_t2", 100000, 28, 2500, 350,  25000,  "octopus_sparse"),
    ("falcon_3_5",  "Falcon-3.5",  430,  [95, 118, 92, 62, 55], "reasoning_rl",      "",           0,      0,  0,    0,    0,      ""),
    ("falcon_4",    "Falcon-4",    470,  [102, 128, 95, 72, 72], "pretrain",         "cypress_t3", 250000, 28, 5000, 680,  42000,  "octopus_sparse"),
    ("falcon_4_5",  "Falcon-4.5",  525,  [112, 142, 108, 85, 92], "tool_use_posttrain", "",        0,      0,  0,    0,    0,      ""),
    ("falcon_5",    "Falcon-5",    590,  [122, 152, 115, 95, 108], "pretrain",       "cypress_t3", 500000, 26, 10000, 1300, 72000, "octopus_super_sparse"),
    ("falcon_5_5",  "Falcon-5.5",  655,  [132, 165, 125, 108, 122], "reasoning_rl",  "",           0,      0,  0,    0,    0,      ""),
    ("falcon_6",    "Falcon-6",    730,  [142, 178, 138, 118, 138], "pretrain",      "cypress_t3", 1200000, 28, 20000, 2500, 140000, "octopus_super_sparse"),
    ("falcon_6_5",  "Falcon-6.5",  800,  [155, 192, 152, 130, 152], "tool_use_posttrain", "",      0,      0,  0,    0,    0,      ""),
    ("falcon_7",    "Falcon-7",    870,  [168, 208, 165, 142, 168], "pretrain",      "cypress_t3", 2000000, 28, 32000, 3700, 200000, "octopus_super_sparse"),
    ("falcon_8",    "Falcon-8",    990,  [195, 240, 192, 168, 198], "pretrain",      "cypress_t3", 3500000, 30, 50000, 5600, 310000, "octopus_super_sparse"),
    ("falcon_9",    "Falcon-9",    1110, [225, 275, 222, 198, 232], "pretrain",      "cypress_t3", 5500000, 30, 75000, 8200, 460000, "octopus_super_sparse"),
    ("falcon_10",   "Falcon-10",   1230, [258, 312, 254, 230, 268], "pretrain",      "cypress_t3", 8000000, 30, 110000, 12000, 660000, "octopus_super_sparse"),
]

WOLF_RESEARCH: List[Release] = [  # open source; lags ~25-35 weeks behind frontier closed-source.
    ("wolf_1",      "Wolf-1",      215,  [12, 8, 8, 0, 0],    "pretrain",            "cypress_t1", 2000,   22, 13,   13,   200,    "ant_v2"),
    ("wolf_1_5",    "Wolf-1.5",    250,  [18, 12, 14, 0, 0],  "rlhf",                "",           0,      0,  0,    0,    0,      ""),
    ("wolf_2",      "Wolf-2",      285,  [30, 18, 22, 8, 5],  "pretrain",            "cypress_t1", 5000,   24, 70,   70,   1500,   "ant_v3"),
    ("wolf_2_3",    "Wolf-2.3",    310,  [35, 22, 28, 10, 8], "rlhf",                "",           0,      0,  0,    0,    0,      ""),
    ("wolf_3",      "Wolf-3",      330,  [65, 52, 55, 35, 15], "pretrain",           "cypress_t2", 16000,  25, 405,  405,  11000,  "ant_v4"),
    ("wolf_3_5",    "Wolf-3.5",    380,  [72, 58, 62, 42, 22], "rlhf",               "",           0,      0,  0,    0,    0,      ""),
    ("wolf_4",      "Wolf-4",      410,  [85, 72, 82, 72, 40], "pretrain",           "cypress_t2", 32000,  26, 1000, 150,  20000,  "octopus_v2"),
    ("wolf_4_5",    "Wolf-4.5",    460,  [92, 78, 88, 80, 52], "reasoning_rl",       "",           0,      0,  0,    0,    0,      ""),
    ("wolf_5",      "Wolf-5",      510,  [105, 92, 102, 95, 72], "pretrain",         "cypress_t3", 200000, 28, 2000, 280,  28000,  "octopus_sparse"),
    ("wolf_5_5",    "Wolf-5.5",    580,  [118, 105, 115, 108, 92], "rlhf",           "",           0,      0,  0,    0,    0,      ""),
    ("wolf_6",      "Wolf-6",      640,  [128, 115, 125, 118, 108], "pretrain",      "cypress_t3", 500000, 28, 5000, 680,  60000,  "octopus_sparse"),
    ("wolf_6_5",    "Wolf-6.5",    720,  [138, 128, 138, 130, 122], "reasoning_rl",  "",           0,      0,  0,    0,    0,      ""),
    ("wolf_7",      "Wolf-7",      800,  [150, 140, 148, 142, 138], "pretrain",      "cypress_t3", 1000000, 28, 10000, 1300, 110000, "octopus_super_sparse"),
    ("wolf_8",      "Wolf-8",      940,  [180, 172, 182, 175, 172], "pretrain",      "cypress_t3", 2000000, 28, 22000, 2700, 200000, "octopus_super_sparse"),
    ("wolf_9",      "Wolf-9",      1080, [215, 208, 220, 210, 208], "pretrain",      "cypress_t3", 3500000, 30, 38000, 4500, 320000, "octopus_super_sparse"),
    ("wolf_10",     "Wolf-10",     1220, [255, 250, 262, 250, 252], "pretrain",      "cypress_t3", 5500000, 30, 60000, 6800, 460000, "octopus_super_sparse"),
]


# ============================================================================
# SUB-BOARDS (18 NPCs) — specialists, one tier smaller clusters, focused axis.
# ============================================================================

# sub_general (3) -----------------------------------------------------------
SPARROW_CHAT: List[Release] = [
    ("sparrow_1",   "Sparrow-1",   230,  [15, 5, 6, 0, 0],    "pretrain",            "cypress_t1", 2000,   22, 30,   30,   300,    "ant_v3"),
    ("sparrow_2",   "Sparrow-2",   305,  [55, 25, 28, 12, 6], "pretrain",            "cypress_t2", 8000,   24, 400,  400,  4000,   "ant_v4"),
    ("sparrow_3",   "Sparrow-3",   385,  [78, 48, 52, 28, 18], "pretrain",           "cypress_t2", 20000,  24, 800,  120,  10000,  "octopus_v2"),
    ("sparrow_3_5", "Sparrow-3.5", 425,  [82, 52, 58, 35, 25], "rlhf",               "",           0,      0,  0,    0,    0,      ""),
    ("sparrow_4",   "Sparrow-4",   470,  [95, 65, 72, 52, 38], "pretrain",           "cypress_t3", 60000,  26, 1800, 250,  18000,  "octopus_sparse"),
    ("sparrow_4_5", "Sparrow-4.5", 540,  [108, 78, 88, 68, 55], "reasoning_rl",      "",           0,      0,  0,    0,    0,      ""),
    ("sparrow_5",   "Sparrow-5",   620,  [122, 95, 105, 88, 78], "pretrain",         "cypress_t3", 200000, 28, 4500, 600,  42000,  "octopus_sparse"),
    ("sparrow_6",   "Sparrow-6",   760,  [148, 122, 132, 115, 110], "pretrain",      "cypress_t3", 600000, 28, 10000, 1300, 80000, "octopus_super_sparse"),
    ("sparrow_7",   "Sparrow-7",   900,  [175, 152, 162, 145, 140], "pretrain",      "cypress_t3", 1400000, 28, 22000, 2600, 160000, "octopus_super_sparse"),
    ("sparrow_8",   "Sparrow-8",   1080, [212, 188, 200, 180, 178], "pretrain",      "cypress_t3", 2800000, 28, 40000, 4500, 270000, "octopus_super_sparse"),
    ("sparrow_9",   "Sparrow-9",   1260, [248, 228, 240, 218, 218], "pretrain",      "cypress_t3", 5000000, 28, 70000, 7800, 440000, "octopus_super_sparse"),
]

HARE_EXPRESS: List[Release] = [
    ("hare_1",      "Hare-1",      270,  [25, 8, 10, 3, 0],   "pretrain",            "cypress_t1", 1000,   18, 30,   30,   400,    "ant_v3"),
    ("hare_2",      "Hare-2",      340,  [58, 28, 32, 15, 5], "pretrain",            "cypress_t2", 4000,   20, 250,  250,  3500,   "ant_v4"),
    ("hare_2_5",    "Hare-2.5",    375,  [62, 32, 38, 18, 8], "rlhf",                "",           0,      0,  0,    0,    0,      ""),
    ("hare_3",      "Hare-3",      410,  [78, 48, 55, 32, 18], "pretrain",           "cypress_t2", 12000,  22, 600,  90,   8000,   "octopus_v2"),
    ("hare_3_5",    "Hare-3.5",    455,  [85, 55, 62, 42, 28], "rlhf",               "",           0,      0,  0,    0,    0,      ""),
    ("hare_4",      "Hare-4",      490,  [95, 68, 78, 58, 42], "pretrain",           "cypress_t3", 30000,  22, 1500, 220,  14000,  "octopus_sparse"),
    ("hare_4_5",    "Hare-4.5",    560,  [108, 82, 95, 75, 60], "reasoning_rl",      "",           0,      0,  0,    0,    0,      ""),
    ("hare_5",      "Hare-5",      640,  [125, 100, 115, 92, 82], "pretrain",        "cypress_t3", 100000, 26, 3200, 450,  32000,  "octopus_sparse"),
    ("hare_6",      "Hare-6",      790,  [152, 130, 142, 122, 115], "pretrain",      "cypress_t3", 350000, 26, 7500, 1000, 65000,  "octopus_super_sparse"),
    ("hare_7",      "Hare-7",      950,  [182, 162, 175, 152, 148], "pretrain",      "cypress_t3", 800000, 28, 15000, 1900, 120000, "octopus_super_sparse"),
    ("hare_8",      "Hare-8",      1120, [218, 198, 212, 188, 185], "pretrain",      "cypress_t3", 1800000, 28, 28000, 3300, 220000, "octopus_super_sparse"),
    ("hare_9",      "Hare-9",      1280, [255, 235, 250, 225, 222], "pretrain",      "cypress_t3", 3500000, 28, 50000, 5800, 340000, "octopus_super_sparse"),
]

FINCH_OPEN: List[Release] = [  # open; lags ~30 weeks behind sub-general closed peers.
    ("finch_1",     "Finch-1",     295,  [22, 8, 10, 0, 0],   "pretrain",            "cypress_t1", 2000,   22, 30,   30,   400,    "ant_v3"),
    ("finch_2",     "Finch-2",     360,  [55, 25, 28, 12, 5], "pretrain",            "cypress_t2", 8000,   22, 200,  200,  3000,   "ant_v4"),
    ("finch_3",     "Finch-3",     440,  [78, 48, 52, 30, 18], "pretrain",           "cypress_t2", 24000,  24, 800,  120,  12000,  "octopus_v2"),
    ("finch_3_5",   "Finch-3.5",   495,  [85, 55, 62, 38, 28], "rlhf",               "",           0,      0,  0,    0,    0,      ""),
    ("finch_4",     "Finch-4",     520,  [96, 68, 78, 55, 42], "pretrain",           "cypress_t3", 80000,  26, 2000, 280,  20000,  "octopus_sparse"),
    ("finch_4_5",   "Finch-4.5",   600,  [108, 85, 95, 72, 62], "reasoning_rl",      "",           0,      0,  0,    0,    0,      ""),
    ("finch_5",     "Finch-5",     680,  [122, 102, 115, 92, 82], "pretrain",        "cypress_t3", 250000, 28, 4500, 620,  44000,  "octopus_sparse"),
    ("finch_6",     "Finch-6",     830,  [148, 128, 140, 118, 110], "pretrain",      "cypress_t3", 700000, 28, 9000, 1200, 80000,  "octopus_super_sparse"),
    ("finch_7",     "Finch-7",     980,  [175, 155, 168, 145, 140], "pretrain",      "cypress_t3", 1500000, 28, 18000, 2300, 150000, "octopus_super_sparse"),
    ("finch_8",     "Finch-8",     1150, [205, 188, 200, 175, 170], "pretrain",      "cypress_t3", 2800000, 28, 32000, 3800, 240000, "octopus_super_sparse"),
    ("finch_9",     "Finch-9",     1290, [240, 222, 235, 210, 208], "pretrain",      "cypress_t3", 4800000, 28, 55000, 6300, 380000, "octopus_super_sparse"),
]

# sub_code (4) --------------------------------------------------------------
ANT_QUICKCODE: List[Release] = [  # open.
    ("antcode_1",   "AntCode-1",   290,  [12, 32, 14, 0, 0],  "pretrain",            "cypress_t1", 3000,   22, 50,   50,   500,    "ant_v3"),
    ("antcode_1_5", "AntCode-1.5", 330,  [16, 42, 18, 0, 0],  "rlhf",                "",           0,      0,  0,    0,    0,      ""),
    ("antcode_2",   "AntCode-2",   360,  [42, 72, 48, 12, 8], "pretrain",            "cypress_t2", 10000,  24, 500,  75,   8000,   "octopus_v2"),
    ("antcode_2_5", "AntCode-2.5", 405,  [48, 82, 55, 18, 18], "tool_use_posttrain", "",           0,      0,  0,    0,    0,      ""),
    ("antcode_3",   "AntCode-3",   440,  [62, 92, 68, 32, 32], "pretrain",           "cypress_t2", 25000,  24, 900,  140,  13000,  "octopus_sparse"),
    ("antcode_3_5", "AntCode-3.5", 510,  [72, 105, 80, 42, 48], "reasoning_rl",      "",           0,      0,  0,    0,    0,      ""),
    ("antcode_4",   "AntCode-4",   540,  [82, 115, 92, 52, 60], "pretrain",          "cypress_t3", 80000,  26, 2200, 320,  22000,  "octopus_sparse"),
    ("antcode_5",   "AntCode-5",   660,  [100, 138, 112, 75, 82], "pretrain",        "cypress_t3", 250000, 28, 5500, 750,  50000,  "octopus_super_sparse"),
    ("antcode_6",   "AntCode-6",   820,  [125, 168, 138, 102, 110], "pretrain",      "cypress_t3", 700000, 28, 11000, 1400, 90000, "octopus_super_sparse"),
    ("antcode_7",   "AntCode-7",   980,  [152, 200, 165, 130, 140], "pretrain",      "cypress_t3", 1500000, 28, 20000, 2400, 160000, "octopus_super_sparse"),
    ("antcode_8",   "AntCode-8",   1150, [182, 232, 195, 158, 172], "pretrain",      "cypress_t3", 2800000, 28, 35000, 4000, 250000, "octopus_super_sparse"),
    ("antcode_9",   "AntCode-9",   1290, [215, 268, 228, 188, 205], "pretrain",      "cypress_t3", 4800000, 28, 58000, 6500, 400000, "octopus_super_sparse"),
]

LYNX_DEVNET: List[Release] = [  # open; repository agents and CI repair.
    ("lynx_1",      "Lynx-1",      345,  [18, 45, 20, 0, 6],    "pretrain",           "cypress_t2", 4000,   22, 90,   90,   1200,   "ant_v4"),
    ("lynx_1_5",    "Lynx-1.5",    390,  [22, 58, 28, 6, 18],   "tool_use_posttrain", "",           0,      0,  0,    0,    0,      ""),
    ("lynx_2",      "Lynx-2",      430,  [45, 86, 52, 18, 30],  "pretrain",           "cypress_t2", 14000,  24, 600,  90,   9000,   "octopus_v2"),
    ("lynx_2_5",    "Lynx-2.5",    500,  [55, 98, 65, 28, 48],  "reasoning_rl",       "",           0,      0,  0,    0,    0,      ""),
    ("lynx_3",      "Lynx-3",      560,  [78, 118, 88, 55, 75], "pretrain",           "cypress_t3", 70000,  26, 2500, 360,  24000,  "octopus_sparse"),
    ("lynx_3_5",    "Lynx-3.5",    640,  [88, 132, 98, 65, 92], "tool_use_posttrain", "",           0,      0,  0,    0,    0,      ""),
    ("lynx_4",      "Lynx-4",      710,  [105, 152, 120, 88, 120], "pretrain",        "cypress_t3", 280000, 28, 6000, 850,  60000,  "octopus_super_sparse"),
    ("lynx_5",      "Lynx-5",      870,  [135, 185, 150, 115, 150], "pretrain",       "cypress_t3", 850000, 28, 13000, 1700, 115000, "octopus_super_sparse"),
    ("lynx_6",      "Lynx-6",      1030, [165, 218, 180, 145, 185], "pretrain",       "cypress_t3", 1700000, 28, 26000, 3100, 215000, "octopus_super_sparse"),
    ("lynx_7",      "Lynx-7",      1190, [198, 252, 215, 178, 225], "pretrain",       "cypress_t3", 3200000, 28, 42000, 4800, 330000, "octopus_super_sparse"),
    ("lynx_8",      "Lynx-8",      1320, [232, 290, 250, 210, 262], "pretrain",       "cypress_t3", 5200000, 28, 62000, 7000, 460000, "octopus_super_sparse"),
]

TERMITE_DEVKIT: List[Release] = [
    ("termite_1",   "Termite-1",   310,  [12, 38, 14, 2, 12], "pretrain",            "cypress_t2", 4000,   24, 80,   80,   1500,   "ant_v4"),
    ("termite_2",   "Termite-2",   390,  [42, 78, 48, 18, 38], "pretrain",           "cypress_t2", 12000,  24, 600,  90,   8500,   "octopus_v2"),
    ("termite_2_5", "Termite-2.5", 440,  [50, 88, 55, 25, 50], "tool_use_posttrain", "",           0,      0,  0,    0,    0,      ""),
    ("termite_3",   "Termite-3",   470,  [62, 102, 68, 38, 72], "pretrain",          "cypress_t3", 40000,  26, 1800, 250,  18000,  "octopus_sparse"),
    ("termite_3_5", "Termite-3.5", 540,  [72, 115, 82, 50, 92], "tool_use_posttrain", "",          0,      0,  0,    0,    0,      ""),
    ("termite_4",   "Termite-4",   580,  [85, 128, 95, 62, 105], "pretrain",         "cypress_t3", 150000, 28, 4200, 580,  36000,  "octopus_sparse"),
    ("termite_5",   "Termite-5",   720,  [108, 158, 122, 88, 132], "pretrain",       "cypress_t3", 500000, 28, 8500, 1100, 70000,  "octopus_super_sparse"),
    ("termite_6",   "Termite-6",   870,  [132, 188, 148, 115, 162], "pretrain",      "cypress_t3", 1200000, 28, 16000, 2000, 130000, "octopus_super_sparse"),
    ("termite_7",   "Termite-7",   1030, [160, 220, 178, 145, 192], "pretrain",      "cypress_t3", 2500000, 28, 28000, 3300, 220000, "octopus_super_sparse"),
    ("termite_8",   "Termite-8",   1200, [195, 258, 215, 178, 228], "pretrain",      "cypress_t3", 4500000, 28, 48000, 5500, 350000, "octopus_super_sparse"),
]

BAMBOO_COMPILER: List[Release] = [  # uses bamboo accelerator family for code+reasoning.
    ("bamboo_1",    "Bamboo-1",    330,  [22, 55, 48, 8, 5],  "pretrain",            "bamboo_t2",  8000,   24, 350,  350,  5000,   "ant_v4"),
    ("bamboo_1_5",  "Bamboo-1.5",  370,  [28, 65, 58, 12, 12], "rlhf",               "",           0,      0,  0,    0,    0,      ""),
    ("bamboo_2",    "Bamboo-2",    410,  [55, 88, 82, 32, 28], "pretrain",           "bamboo_t3",  24000,  26, 1200, 180,  14000,  "octopus_v2"),
    ("bamboo_2_5",  "Bamboo-2.5",  470,  [65, 100, 95, 42, 42], "reasoning_rl",      "",           0,      0,  0,    0,    0,      ""),
    ("bamboo_3",    "Bamboo-3",    500,  [78, 118, 108, 58, 62], "pretrain",         "bamboo_t4",  80000,  26, 3000, 420,  30000,  "octopus_sparse"),
    ("bamboo_3_5",  "Bamboo-3.5",  580,  [92, 138, 128, 75, 82], "tool_use_posttrain", "",         0,      0,  0,    0,    0,      ""),
    ("bamboo_4",    "Bamboo-4",    620,  [105, 152, 142, 92, 105], "pretrain",       "bamboo_t4",  200000, 28, 7000, 950,  65000,  "octopus_super_sparse"),
    ("bamboo_5",    "Bamboo-5",    790,  [132, 188, 175, 122, 138], "pretrain",      "bamboo_t4",  600000, 28, 14000, 1700, 120000, "octopus_super_sparse"),
    ("bamboo_6",    "Bamboo-6",    950,  [162, 222, 210, 152, 172], "pretrain",      "bamboo_t4",  1300000, 28, 24000, 2900, 200000, "octopus_super_sparse"),
    ("bamboo_7",    "Bamboo-7",    1110, [195, 258, 248, 182, 208], "pretrain",      "bamboo_t4",  2600000, 28, 40000, 4600, 300000, "octopus_super_sparse"),
    ("bamboo_8",    "Bamboo-8",    1280, [228, 295, 285, 215, 245], "pretrain",      "bamboo_t4",  4500000, 28, 65000, 7300, 460000, "octopus_super_sparse"),
]

# sub_reasoning (3) ---------------------------------------------------------
BEE_LOGIC: List[Release] = [  # open; reasoning + RL.
    ("bee_1",       "Bee-1",       380,  [25, 18, 55, 8, 12], "pretrain",            "cypress_t2", 6000,   25, 200,  200,  4000,   "ant_v4"),
    ("bee_1_5",     "Bee-1.5",     420,  [30, 22, 68, 12, 22], "reasoning_rl",       "",           0,      0,  0,    0,    0,      ""),
    ("bee_2",       "Bee-2",       440,  [48, 38, 92, 25, 42], "pretrain",           "cypress_t2", 16000,  26, 800,  120,  10000,  "octopus_v2"),
    ("bee_2_5",     "Bee-2.5",     510,  [58, 48, 108, 35, 58], "reasoning_rl",      "",           0,      0,  0,    0,    0,      ""),
    ("bee_3",       "Bee-3",       530,  [72, 62, 122, 50, 78], "pretrain",          "cypress_t3", 50000,  26, 2200, 320,  22000,  "octopus_sparse"),
    ("bee_3_5",     "Bee-3.5",     615,  [85, 75, 138, 65, 95], "reasoning_rl",      "",           0,      0,  0,    0,    0,      ""),
    ("bee_4",       "Bee-4",       650,  [98, 88, 152, 80, 115], "pretrain",         "cypress_t3", 200000, 28, 5500, 750,  50000,  "octopus_super_sparse"),
    ("bee_5",       "Bee-5",       820,  [125, 115, 188, 110, 148], "pretrain",      "cypress_t3", 600000, 28, 11000, 1400, 95000, "octopus_super_sparse"),
    ("bee_6",       "Bee-6",       980,  [152, 142, 222, 138, 180], "pretrain",      "cypress_t3", 1400000, 28, 20000, 2400, 165000, "octopus_super_sparse"),
    ("bee_7",       "Bee-7",       1150, [182, 172, 260, 170, 215], "pretrain",      "cypress_t3", 2800000, 28, 36000, 4100, 260000, "octopus_super_sparse"),
    ("bee_8",       "Bee-8",       1290, [215, 205, 298, 202, 252], "pretrain",      "cypress_t3", 4800000, 28, 58000, 6500, 400000, "octopus_super_sparse"),
]

OCTOPUS_THINK: List[Release] = [
    ("octopus_1",   "Octopus-1",   340,  [22, 18, 62, 5, 15], "pretrain",            "cypress_t2", 8000,   26, 320,  48,   6000,   "octopus_v2"),
    ("octopus_1_5", "Octopus-1.5", 395,  [32, 28, 78, 12, 28], "reasoning_rl",       "",           0,      0,  0,    0,    0,      ""),
    ("octopus_2",   "Octopus-2",   415,  [55, 48, 95, 28, 48], "pretrain",           "cypress_t2", 22000,  26, 1100, 165,  12000,  "octopus_sparse"),
    ("octopus_2_5", "Octopus-2.5", 480,  [68, 60, 115, 40, 65], "reasoning_rl",      "",           0,      0,  0,    0,    0,      ""),
    ("octopus_3",   "Octopus-3",   495,  [78, 72, 128, 52, 82], "pretrain",          "cypress_t3", 70000,  28, 3000, 420,  28000,  "octopus_super_sparse"),
    ("octopus_3_5", "Octopus-3.5", 570,  [90, 85, 142, 65, 100], "reasoning_rl",     "",           0,      0,  0,    0,    0,      ""),
    ("octopus_4",   "Octopus-4",   615,  [105, 100, 158, 82, 122], "pretrain",       "cypress_t3", 250000, 28, 6500, 880,  58000,  "octopus_super_sparse"),
    ("octopus_5",   "Octopus-5",   780,  [132, 128, 192, 112, 158], "pretrain",      "cypress_t3", 700000, 28, 12500, 1500, 105000, "octopus_super_sparse"),
    ("octopus_6",   "Octopus-6",   940,  [160, 158, 225, 142, 192], "pretrain",      "cypress_t3", 1500000, 28, 22000, 2600, 185000, "octopus_super_sparse"),
    ("octopus_7",   "Octopus-7",   1100, [190, 188, 258, 172, 225], "pretrain",      "cypress_t3", 3000000, 28, 38000, 4400, 290000, "octopus_super_sparse"),
    ("octopus_8",   "Octopus-8",   1270, [225, 222, 295, 205, 260], "pretrain",      "cypress_t3", 5500000, 28, 65000, 7300, 450000, "octopus_super_sparse"),
]

OWL_OPEN: List[Release] = [  # open; academic-paper-driven reasoning.
    ("owl_1",       "Owl-1",       310,  [25, 16, 38, 0, 8],  "pretrain",            "cypress_t1", 1500,   22, 25,   25,   400,    "ant_v3"),
    ("owl_1_5",     "Owl-1.5",     365,  [32, 22, 50, 0, 18], "rlhf",                "",           0,      0,  0,    0,    0,      ""),
    ("owl_2",       "Owl-2",       395,  [50, 38, 78, 22, 38], "pretrain",           "cypress_t2", 8000,   24, 350,  50,   5000,   "octopus_v2"),
    ("owl_2_5",     "Owl-2.5",     460,  [58, 45, 92, 28, 52], "reasoning_rl",       "",           0,      0,  0,    0,    0,      ""),
    ("owl_3",       "Owl-3",       480,  [68, 58, 105, 38, 65], "pretrain",          "cypress_t2", 24000,  25, 900,  140,  12000,  "octopus_sparse"),
    ("owl_3_5",     "Owl-3.5",     570,  [80, 72, 122, 52, 82], "reasoning_rl",      "",           0,      0,  0,    0,    0,      ""),
    ("owl_4",       "Owl-4",       600,  [92, 85, 135, 65, 98], "pretrain",          "cypress_t3", 100000, 28, 3000, 420,  30000,  "octopus_super_sparse"),
    ("owl_5",       "Owl-5",       780,  [118, 115, 170, 95, 132], "pretrain",       "cypress_t3", 350000, 28, 7000, 950,  68000,  "octopus_super_sparse"),
    ("owl_6",       "Owl-6",       960,  [148, 148, 202, 125, 168], "pretrain",      "cypress_t3", 900000, 28, 14000, 1700, 130000, "octopus_super_sparse"),
    ("owl_7",       "Owl-7",       1140, [180, 182, 238, 158, 205], "pretrain",      "cypress_t3", 2000000, 28, 25000, 3000, 210000, "octopus_super_sparse"),
    ("owl_8",       "Owl-8",       1290, [212, 215, 272, 188, 238], "pretrain",      "cypress_t3", 3500000, 28, 42000, 4800, 320000, "octopus_super_sparse"),
]

# sub_multimodal (4) --------------------------------------------------------
DOLPHIN_VISION: List[Release] = [  # video / image, not text.
    ("dolphin_1",   "Dolphin-1",   260,  [10, 5, 12, 38, 0],  "pretrain",            "cypress_t1", 3000,   24, 90,   90,   2500,   "ant_v3"),
    ("dolphin_1_5", "Dolphin-1.5", 305,  [14, 8, 16, 52, 0],  "multimodal_posttrain", "",          0,      0,  0,    0,    0,      ""),
    ("dolphin_2",   "Dolphin-2",   340,  [32, 22, 35, 78, 12], "pretrain",           "cypress_t2", 12000,  26, 600,  90,   7500,   "octopus_v2"),
    ("dolphin_2_5", "Dolphin-2.5", 390,  [40, 28, 42, 92, 22], "multimodal_posttrain", "",         0,      0,  0,    0,    0,      ""),
    ("dolphin_3",   "Dolphin-3",   425,  [58, 42, 60, 108, 42], "pretrain",          "cypress_t2", 35000,  26, 1800, 250,  20000,  "octopus_sparse"),
    ("dolphin_3_5", "Dolphin-3.5", 490,  [68, 50, 70, 122, 55], "multimodal_posttrain", "",        0,      0,  0,    0,    0,      ""),
    ("dolphin_4",   "Dolphin-4",   530,  [82, 65, 85, 138, 72], "pretrain",          "cypress_t3", 120000, 28, 4500, 620,  42000,  "octopus_super_sparse"),
    ("dolphin_5",   "Dolphin-5",   700,  [108, 92, 115, 172, 105], "pretrain",       "cypress_t3", 400000, 28, 9500, 1300, 90000,  "octopus_super_sparse"),
    ("dolphin_6",   "Dolphin-6",   870,  [138, 122, 145, 208, 142], "pretrain",      "cypress_t3", 1000000, 28, 18000, 2200, 170000, "octopus_super_sparse"),
    ("dolphin_7",   "Dolphin-7",   1050, [170, 155, 178, 245, 180], "pretrain",      "cypress_t3", 2200000, 28, 32000, 3700, 280000, "octopus_super_sparse"),
    ("dolphin_8",   "Dolphin-8",   1230, [202, 188, 212, 282, 218], "pretrain",      "cypress_t3", 4200000, 28, 52000, 5900, 420000, "octopus_super_sparse"),
]

WHALE_AUDIO: List[Release] = [
    ("whale_1",     "Whale-1",     280,  [12, 5, 12, 42, 0],  "pretrain",            "cypress_t1", 4000,   24, 110,  110,  3000,   "ant_v3"),
    ("whale_2",     "Whale-2",     370,  [38, 22, 38, 82, 18], "pretrain",           "cypress_t2", 12000,  26, 650,  100,  8000,   "octopus_v2"),
    ("whale_2_5",   "Whale-2.5",   415,  [45, 28, 44, 95, 28], "multimodal_posttrain", "",         0,      0,  0,    0,    0,      ""),
    ("whale_3",     "Whale-3",     450,  [62, 45, 62, 112, 48], "pretrain",          "cypress_t2", 32000,  26, 1700, 240,  19000,  "octopus_sparse"),
    ("whale_3_5",   "Whale-3.5",   510,  [72, 55, 72, 125, 62], "multimodal_posttrain", "",        0,      0,  0,    0,    0,      ""),
    ("whale_4",     "Whale-4",     560,  [85, 68, 88, 142, 78], "pretrain",          "cypress_t3", 100000, 28, 4000, 550,  38000,  "octopus_super_sparse"),
    ("whale_5",     "Whale-5",     730,  [110, 95, 115, 175, 108], "pretrain",       "cypress_t3", 350000, 28, 8500, 1100, 80000,  "octopus_super_sparse"),
    ("whale_6",     "Whale-6",     900,  [138, 125, 145, 210, 142], "pretrain",      "cypress_t3", 900000, 28, 16000, 2000, 150000, "octopus_super_sparse"),
    ("whale_7",     "Whale-7",     1080, [170, 158, 178, 248, 178], "pretrain",      "cypress_t3", 1900000, 28, 28000, 3300, 240000, "octopus_super_sparse"),
    ("whale_8",     "Whale-8",     1260, [202, 192, 212, 285, 215], "pretrain",      "cypress_t3", 3800000, 28, 48000, 5500, 380000, "octopus_super_sparse"),
]

BEAVER_NETWORK: List[Release] = [  # open multimodal.
    ("beaver_1",    "Beaver-1",    330,  [10, 5, 12, 35, 0],  "pretrain",            "cypress_t1", 3000,   24, 80,   80,   2200,   "ant_v3"),
    ("beaver_2",    "Beaver-2",    415,  [32, 18, 35, 78, 15], "pretrain",           "cypress_t2", 12000,  26, 550,  85,   7500,   "octopus_v2"),
    ("beaver_2_5",  "Beaver-2.5",  470,  [40, 25, 42, 92, 25], "multimodal_posttrain", "",         0,      0,  0,    0,    0,      ""),
    ("beaver_3",    "Beaver-3",    510,  [58, 42, 60, 108, 45], "pretrain",          "cypress_t3", 30000,  26, 1500, 220,  18000,  "octopus_sparse"),
    ("beaver_3_5",  "Beaver-3.5",  580,  [68, 52, 70, 122, 58], "multimodal_posttrain", "",        0,      0,  0,    0,    0,      ""),
    ("beaver_4",    "Beaver-4",    630,  [82, 65, 85, 138, 75], "pretrain",          "cypress_t3", 100000, 28, 4200, 580,  40000,  "octopus_super_sparse"),
    ("beaver_5",    "Beaver-5",    800,  [108, 92, 115, 170, 108], "pretrain",       "cypress_t3", 380000, 28, 9000, 1200, 85000,  "octopus_super_sparse"),
    ("beaver_6",    "Beaver-6",    970,  [138, 122, 145, 205, 142], "pretrain",      "cypress_t3", 950000, 28, 17000, 2100, 160000, "octopus_super_sparse"),
    ("beaver_7",    "Beaver-7",    1150, [170, 155, 178, 240, 178], "pretrain",      "cypress_t3", 2100000, 28, 30000, 3500, 260000, "octopus_super_sparse"),
    ("beaver_8",    "Beaver-8",    1290, [200, 188, 210, 275, 212], "pretrain",      "cypress_t3", 3800000, 28, 48000, 5500, 380000, "octopus_super_sparse"),
]

HERON_VISION: List[Release] = [  # open multimodal and lightweight video.
    ("heron_1",     "Heron-1",     365,  [14, 8, 14, 48, 2],   "pretrain",           "cypress_t2", 4000,   24, 100,  100,  2500,   "ant_v4"),
    ("heron_1_5",   "Heron-1.5",   420,  [18, 12, 20, 60, 10], "multimodal_posttrain", "",         0,      0,  0,    0,    0,      ""),
    ("heron_2",     "Heron-2",     455,  [38, 25, 40, 86, 20], "pretrain",           "cypress_t2", 15000,  26, 700,  105,  9000,   "octopus_v2"),
    ("heron_2_5",   "Heron-2.5",   515,  [48, 35, 52, 105, 36], "multimodal_posttrain", "",        0,      0,  0,    0,    0,      ""),
    ("heron_3",     "Heron-3",     585,  [65, 50, 72, 125, 60], "pretrain",          "cypress_t3", 60000,  26, 2200, 320,  24000,  "octopus_sparse"),
    ("heron_3_5",   "Heron-3.5",   665,  [75, 62, 85, 142, 76], "multimodal_posttrain", "",        0,      0,  0,    0,    0,      ""),
    ("heron_4",     "Heron-4",     740,  [92, 80, 105, 160, 100], "pretrain",        "cypress_t3", 250000, 28, 6000, 850,  60000,  "octopus_super_sparse"),
    ("heron_5",     "Heron-5",     900,  [122, 110, 138, 195, 135], "pretrain",      "cypress_t3", 780000, 28, 13000, 1700, 115000, "octopus_super_sparse"),
    ("heron_6",     "Heron-6",     1060, [152, 140, 170, 230, 170], "pretrain",      "cypress_t3", 1600000, 28, 25000, 3000, 210000, "octopus_super_sparse"),
    ("heron_7",     "Heron-7",     1220, [185, 175, 205, 265, 205], "pretrain",      "cypress_t3", 3100000, 28, 42000, 4800, 330000, "octopus_super_sparse"),
    ("heron_8",     "Heron-8",     1350, [220, 212, 240, 305, 245], "pretrain",      "cypress_t3", 5000000, 28, 62000, 7000, 460000, "octopus_super_sparse"),
]

# sub_agent (4) — agent specialists launch post paradigm_reasoning_rl (turn 414).
RACCOON_OPS: List[Release] = [  # tool use / browser automation.
    ("raccoon_1",   "Raccoon-1",   395,  [18, 15, 22, 5, 25], "pretrain",            "cypress_t2", 10000,  24, 350,  50,   5500,   "octopus_v2"),
    ("raccoon_1_5", "Raccoon-1.5", 430,  [22, 18, 28, 8, 38], "tool_use_posttrain",  "",           0,      0,  0,    0,    0,      ""),
    ("raccoon_2",   "Raccoon-2",   460,  [42, 38, 52, 22, 62], "pretrain",           "cypress_t2", 32000,  26, 1200, 180,  14000,  "octopus_sparse"),
    ("raccoon_2_5", "Raccoon-2.5", 510,  [48, 45, 58, 28, 78], "reasoning_rl",       "",           0,      0,  0,    0,    0,      ""),
    ("raccoon_3",   "Raccoon-3",   540,  [62, 58, 72, 42, 105], "pretrain",          "cypress_t3", 100000, 28, 3500, 480,  32000,  "octopus_super_sparse"),
    ("raccoon_3_5", "Raccoon-3.5", 615,  [72, 70, 85, 52, 122], "tool_use_posttrain", "",          0,      0,  0,    0,    0,      ""),
    ("raccoon_4",   "Raccoon-4",   660,  [85, 82, 100, 65, 142], "pretrain",         "cypress_t3", 350000, 28, 8000, 1050, 72000,  "octopus_super_sparse"),
    ("raccoon_5",   "Raccoon-5",   830,  [110, 110, 130, 92, 175], "pretrain",       "cypress_t3", 900000, 28, 15000, 1900, 130000, "octopus_super_sparse"),
    ("raccoon_6",   "Raccoon-6",   1000, [138, 140, 162, 122, 210], "pretrain",      "cypress_t3", 1900000, 28, 26000, 3100, 215000, "octopus_super_sparse"),
    ("raccoon_7",   "Raccoon-7",   1180, [168, 172, 195, 152, 248], "pretrain",      "cypress_t3", 3500000, 28, 42000, 4800, 330000, "octopus_super_sparse"),
    ("raccoon_8",   "Raccoon-8",   1290, [195, 202, 225, 178, 282], "pretrain",      "cypress_t3", 5000000, 28, 60000, 6800, 450000, "octopus_super_sparse"),
]

ANT_SWARM: List[Release] = [
    ("swarm_1",     "Swarm-1",     415,  [22, 22, 65, 8, 32], "pretrain",            "cypress_t2", 12000,  26, 450,  70,   6500,   "octopus_v2"),
    ("swarm_1_5",   "Swarm-1.5",   460,  [28, 28, 78, 12, 48], "reasoning_rl",       "",           0,      0,  0,    0,    0,      ""),
    ("swarm_2",     "Swarm-2",     480,  [50, 48, 92, 28, 75], "pretrain",           "cypress_t3", 40000,  28, 1800, 250,  18000,  "octopus_sparse"),
    ("swarm_2_5",   "Swarm-2.5",   555,  [60, 58, 108, 38, 92], "tool_use_posttrain", "",          0,      0,  0,    0,    0,      ""),
    ("swarm_3",     "Swarm-3",     580,  [72, 72, 122, 50, 118], "pretrain",         "cypress_t3", 180000, 28, 5000, 680,  45000,  "octopus_super_sparse"),
    ("swarm_4",     "Swarm-4",     740,  [98, 100, 152, 78, 158], "pretrain",        "cypress_t3", 600000, 28, 11000, 1400, 95000, "octopus_super_sparse"),
    ("swarm_5",     "Swarm-5",     900,  [125, 130, 182, 108, 195], "pretrain",      "cypress_t3", 1300000, 28, 20000, 2400, 165000, "octopus_super_sparse"),
    ("swarm_6",     "Swarm-6",     1080, [155, 162, 215, 138, 232], "pretrain",      "cypress_t3", 2500000, 28, 32000, 3700, 250000, "octopus_super_sparse"),
    ("swarm_7",     "Swarm-7",     1260, [185, 195, 248, 168, 268], "pretrain",      "cypress_t3", 4500000, 28, 50000, 5700, 380000, "octopus_super_sparse"),
]

CROW_LABS: List[Release] = [  # open; agent specialist, lags ~35 weeks.
    ("crow_1",      "Crow-1",      430,  [18, 18, 25, 5, 22], "pretrain",            "cypress_t2", 8000,   24, 300,  45,   5000,   "octopus_v2"),
    ("crow_1_5",    "Crow-1.5",    485,  [22, 22, 32, 8, 35], "tool_use_posttrain",  "",           0,      0,  0,    0,    0,      ""),
    ("crow_2",      "Crow-2",      510,  [42, 42, 52, 22, 65], "pretrain",           "cypress_t3", 30000,  26, 1200, 180,  13500,  "octopus_sparse"),
    ("crow_2_5",    "Crow-2.5",    575,  [50, 52, 62, 28, 82], "reasoning_rl",       "",           0,      0,  0,    0,    0,      ""),
    ("crow_3",      "Crow-3",      600,  [62, 65, 78, 42, 102], "pretrain",          "cypress_t3", 120000, 28, 3500, 480,  32000,  "octopus_super_sparse"),
    ("crow_3_5",    "Crow-3.5",    690,  [72, 78, 92, 52, 122], "tool_use_posttrain", "",          0,      0,  0,    0,    0,      ""),
    ("crow_4",      "Crow-4",      730,  [85, 92, 108, 65, 138], "pretrain",         "cypress_t3", 400000, 28, 8000, 1050, 72000,  "octopus_super_sparse"),
    ("crow_5",      "Crow-5",      900,  [110, 122, 138, 92, 170], "pretrain",       "cypress_t3", 950000, 28, 15000, 1900, 130000, "octopus_super_sparse"),
    ("crow_6",      "Crow-6",      1080, [138, 152, 168, 122, 205], "pretrain",      "cypress_t3", 1900000, 28, 25000, 3000, 200000, "octopus_super_sparse"),
    ("crow_7",      "Crow-7",      1260, [168, 182, 198, 152, 240], "pretrain",      "cypress_t3", 3500000, 28, 42000, 4800, 320000, "octopus_super_sparse"),
]

OTTER_TOOLS: List[Release] = [  # open; workflow automation community.
    ("otter_1",     "Otter-1",     455,  [18, 20, 24, 6, 35],  "pretrain",           "cypress_t2", 6000,   24, 250,  40,   4500,   "octopus_v2"),
    ("otter_1_5",   "Otter-1.5",   500,  [24, 30, 35, 12, 52], "tool_use_posttrain", "",           0,      0,  0,    0,    0,      ""),
    ("otter_2",     "Otter-2",     535,  [38, 45, 56, 25, 78], "pretrain",           "cypress_t3", 30000,  26, 1200, 180,  14000,  "octopus_sparse"),
    ("otter_2_5",   "Otter-2.5",   600,  [46, 55, 66, 32, 95], "reasoning_rl",       "",           0,      0,  0,    0,    0,      ""),
    ("otter_3",     "Otter-3",     650,  [62, 75, 88, 52, 120], "pretrain",          "cypress_t3", 120000, 28, 3500, 480,  32000,  "octopus_super_sparse"),
    ("otter_3_5",   "Otter-3.5",   730,  [72, 88, 105, 64, 138], "tool_use_posttrain", "",         0,      0,  0,    0,    0,      ""),
    ("otter_4",     "Otter-4",     780,  [86, 108, 128, 82, 158], "pretrain",        "cypress_t3", 350000, 28, 8000, 1050, 72000,  "octopus_super_sparse"),
    ("otter_5",     "Otter-5",     940,  [115, 140, 165, 115, 195], "pretrain",      "cypress_t3", 900000, 28, 15000, 1900, 130000, "octopus_super_sparse"),
    ("otter_6",     "Otter-6",     1100, [145, 175, 200, 148, 235], "pretrain",      "cypress_t3", 1900000, 28, 26000, 3100, 215000, "octopus_super_sparse"),
    ("otter_7",     "Otter-7",     1260, [178, 212, 238, 182, 275], "pretrain",      "cypress_t3", 3500000, 28, 42000, 4800, 330000, "octopus_super_sparse"),
    ("otter_8",     "Otter-8",     1390, [210, 250, 275, 218, 318], "pretrain",      "cypress_t3", 5200000, 28, 62000, 7000, 460000, "octopus_super_sparse"),
]


# ============================================================================
# Manifest (id → display_name, open/closed, boards, releases).
# ============================================================================

NPCS = [
    # Main board (5)
    ("npc_orca_lab",        "OrcaLab",          False, ["closed_source", "sub_general", "sub_reasoning", "sub_agent"], ORCA_LAB),
    ("npc_raven_ai",        "RavenAI",          False, ["closed_source", "sub_reasoning"], RAVEN_AI),
    ("npc_tiger_studio",    "Tiger Studio",     False, ["closed_source", "sub_multimodal"], TIGER_STUDIO),
    ("npc_falcon_inc",      "Falcon Inc",       False, ["closed_source", "sub_code", "sub_agent"], FALCON_INC),
    ("npc_wolf_research",   "Wolf Research",    True,  ["open_source", "sub_general"], WOLF_RESEARCH),

    # sub_general (3)
    ("npc_sparrow_chat",    "Sparrow Chat",     False, ["sub_general"], SPARROW_CHAT),
    ("npc_hare_express",    "Hare Express",     False, ["sub_general"], HARE_EXPRESS),
    ("npc_finch_open",      "Finch Open",       True,  ["sub_general"], FINCH_OPEN),

    # sub_code (4)
    ("npc_ant_quickcode",   "Ant QuickCode",    True,  ["sub_code"], ANT_QUICKCODE),
    ("npc_lynx_devnet",     "Lynx Devnet",      True,  ["sub_code"], LYNX_DEVNET),
    ("npc_termite_devkit",  "Termite Devkit",   False, ["sub_code"], TERMITE_DEVKIT),
    ("npc_bamboo_compiler", "Bamboo Compiler",  False, ["sub_code"], BAMBOO_COMPILER),

    # sub_reasoning (3)
    ("npc_bee_logic",       "Bee Logic",        True,  ["sub_reasoning"], BEE_LOGIC),
    ("npc_octopus_think",   "Octopus Think",    False, ["sub_reasoning"], OCTOPUS_THINK),
    ("npc_owl_open",        "Owl Open",         True,  ["sub_reasoning"], OWL_OPEN),

    # sub_multimodal (4)
    ("npc_dolphin_vision",  "Dolphin Vision",   False, ["sub_multimodal"], DOLPHIN_VISION),
    ("npc_whale_audio",     "Whale Audio",      False, ["sub_multimodal"], WHALE_AUDIO),
    ("npc_beaver_network",  "Beaver Network",   True,  ["sub_multimodal"], BEAVER_NETWORK),
    ("npc_heron_vision",    "Heron Vision",     True,  ["sub_multimodal"], HERON_VISION),

    # sub_agent (4)
    ("npc_raccoon_ops",     "Raccoon Ops",      False, ["sub_agent"], RACCOON_OPS),
    ("npc_ant_swarm",       "Ant Swarm",        False, ["sub_agent"], ANT_SWARM),
    ("npc_crow_labs",       "Crow Labs",        True,  ["sub_agent"], CROW_LABS),
    ("npc_otter_tools",     "Otter Tools",      True,  ["sub_agent"], OTTER_TOOLS),
]


# ============================================================================
# .tres writer.
# ============================================================================

NPC_SCRIPT_PATH = "res://scripts/resources/npc_company.gd"
REL_SCRIPT_PATH = "res://scripts/resources/npc_model_release.gd"


def _fmt_float(x: float) -> str:
    """Match Godot's .tres serialization for floats. Whole numbers get .0."""
    if isinstance(x, int) or x == int(x):
        return f"{int(x)}.0"
    return repr(float(x))


def _cap_dict(caps: List[float]) -> str:
    g, c, r, m, a = caps
    return ('{"general": ' + _fmt_float(g) +
            ', "code": ' + _fmt_float(c) +
            ', "reasoning": ' + _fmt_float(r) +
            ', "multimodal": ' + _fmt_float(m) +
            ', "agent": ' + _fmt_float(a) + '}')


def _cap_total(caps: List[float]) -> List[float]:
    total = sum(caps)
    if total <= NPC_TOTAL_CAP:
        return caps
    scale = NPC_TOTAL_CAP / total
    scaled = [round(v * scale, 3) for v in caps]
    # Rounding can push the sum a hair over the cap. Pull the excess from the
    # largest axis so the visible total remains <= cap without changing flavor.
    excess = round(sum(scaled) - NPC_TOTAL_CAP, 6)
    if excess > 0:
        idx = max(range(len(scaled)), key=lambda i: scaled[i])
        scaled[idx] = round(max(0.0, scaled[idx] - excess), 3)
    return scaled


def _release_block(npc_id: str, rel: Release) -> str:
    (id_suffix, name, turn, caps, kind, gpu_id, gpu_count, weeks,
     params_b, active_b, tokens_b, arch) = rel
    caps = _cap_total(caps)
    sub_id = f"release_{id_suffix}"
    lines = [
        f'[sub_resource type="Resource" id="{sub_id}"]',
        'script = ExtResource("2_rel")',
        f'id = &"{sub_id}"',
        f'display_name = "{name}"',
        f"release_turn = {turn}",
        f"capability = {_cap_dict(caps)}",
        f'release_kind = &"{kind}"',
        f'cluster_gpu_id = &"{gpu_id}"',
        f"cluster_gpu_count = {gpu_count}",
        f"training_weeks = {weeks}",
        f"params_b = {_fmt_float(params_b)}",
        f"active_params_b = {_fmt_float(active_b if active_b > 0 else params_b)}",
        f"dataset_tokens_b = {_fmt_float(tokens_b)}",
        f'arch_codename = &"{arch}"',
        '',
    ]
    return "\n".join(lines)


def _npc_tres(npc_id: str, display_name: str, is_open_source: bool,
              boards: List[str], releases: List[Release]) -> str:
    load_steps = 2 + len(releases) + 1   # 2 ext_resources + N sub_resources + 1 [resource]
    out: List[str] = [
        f'[gd_resource type="Resource" script_class="NpcCompany" '
        f'load_steps={load_steps} format=3]',
        '',
        f'[ext_resource type="Script" path="{NPC_SCRIPT_PATH}" id="1_npc"]',
        f'[ext_resource type="Script" path="{REL_SCRIPT_PATH}" id="2_rel"]',
        '',
    ]
    for rel in releases:
        out.append(_release_block(npc_id, rel))

    boards_str = ", ".join(f'&"{b}"' for b in boards)
    sub_refs = ", ".join(f'SubResource("release_{r[0]}")' for r in releases)
    out += [
        '[resource]',
        'script = ExtResource("1_npc")',
        f'id = &"{npc_id}"',
        f'display_name = "{display_name}"',
        f"is_open_source = {'true' if is_open_source else 'false'}",
        f"board_membership = [{boards_str}]",
        f"model_releases = [{sub_refs}]",
        '',
    ]
    return "\n".join(out)


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    total_releases = 0
    for npc_id, display_name, is_open, boards, releases in NPCS:
        # Sanity: release_turn strictly ascending
        for i in range(1, len(releases)):
            assert releases[i][2] > releases[i - 1][2], (
                f"{npc_id} release order broken at {releases[i][1]}")
        path = OUT_DIR / f"{npc_id}.tres"
        path.write_text(_npc_tres(npc_id, display_name, is_open, boards, releases))
        total_releases += len(releases)
        print(f"wrote {path.relative_to(ROOT)}  ({len(releases)} releases)")
    print(f"\n{len(NPCS)} NPCs, {total_releases} releases total")


if __name__ == "__main__":
    main()
