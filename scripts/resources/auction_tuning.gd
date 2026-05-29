class_name AuctionTuning
extends Resource

## 拍卖行轮换上架调参。Stored at resources/data/collectibles/auction_tuning.tres,
## loaded by CollectionSystem at _ready. Per design/办公室与收藏系统设计.md §8.3.
##
## 注意: 此文件与收藏品 spec 同放 collectibles/ 目录, 但 build_collectibles.py 的
## 清空步骤会跳过它 (按文件名保护), CollectionSystem 目录扫描也按文件名跳过它。

## 拍卖行同时上架的槽位数 (库存足够时正好这么多, 不足则显示剩余全部)。
@export var slots: int = 8
## 每隔多少周 (action 相位) 重 roll 一次 lineup。
@export var refresh_weeks: int = 4
