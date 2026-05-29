class_name NameRomanizer
extends RefCounted

## 中文真名 → 拼音 的纯静态工具。见 design/国际化设计.md §12。
##
## 东亚 lead 的 `display_name` 存中文 (PersonName 按肖像族裔生成的中文名), 显示时按
## locale 转拼音 — 不改存档, 老档与切换 locale 都自然生效。非东亚 lead 的 display_name
## 本就是拉丁字母名 (如 "James Smith"), 首字不在 _PINYIN → 整串 passthrough, 原样显示。
##
## 用法 (显示处一律走 localized, 别直接用 lead.display_name):
##   var shown := NameRomanizer.localized(lead.display_name)

## 姓池 / 名池里出现的字 → 小写拼音。只覆盖 PersonName 东亚池 (EAST_ASIAN_SURNAMES +
## EAST_ASIAN_GIVEN_MALE + EAST_ASIAN_GIVEN_FEMALE) 用到的字; 表外字触发整串 passthrough
## (见 romanize)。name_romanizer_test.gd 守护「每个东亚池字都在此有映射」, 加字别忘了补这里。
const _PINYIN: Dictionary = {
	# ── 姓 (PersonName.EAST_ASIAN_SURNAMES) ──
	"王": "wang", "李": "li", "张": "zhang", "刘": "liu", "陈": "chen",
	"杨": "yang", "黄": "huang", "赵": "zhao", "吴": "wu", "周": "zhou",
	"徐": "xu", "孙": "sun", "马": "ma", "朱": "zhu", "胡": "hu",
	"郭": "guo", "何": "he", "高": "gao", "林": "lin", "罗": "luo",
	"郑": "zheng", "梁": "liang", "谢": "xie", "宋": "song", "唐": "tang",
	"许": "xu", "韩": "han", "冯": "feng", "邓": "deng", "曹": "cao",
	"彭": "peng", "曾": "zeng", "肖": "xiao", "田": "tian", "董": "dong",
	"袁": "yuan", "潘": "pan", "蒋": "jiang", "蔡": "cai", "余": "yu",
	"沈": "shen", "魏": "wei", "钟": "zhong", "姚": "yao", "苏": "su",
	# ── 名: 单字 (PersonName 东亚名池, 单字部分) ──
	"伟": "wei", "强": "qiang", "磊": "lei", "敏": "min", "静": "jing",
	"丽": "li", "杰": "jie", "涛": "tao", "明": "ming", "超": "chao",
	"军": "jun", "辉": "hui", "鹏": "peng", "宇": "yu", "浩": "hao",
	"凯": "kai", "晨": "chen", "睿": "rui", "博": "bo", "翔": "xiang",
	"雪": "xue", "婷": "ting", "娜": "na", "倩": "qian", "璐": "lu",
	"瑶": "yao", "妍": "yan", "悦": "yue", "瑾": "jin", "琳": "lin",
	# ── 名: 双字所含字 (PersonName 东亚名池, 双字部分, 去重) ──
	"婉": "wan", "清": "qing", "轩": "xuan", "佳": "jia", "怡": "yi",
	"子": "zi", "墨": "mo", "梓": "zi", "涵": "han", "嘉": "jia",
	"欣": "xin", "思": "si", "远": "yuan", "诗": "shi", "若": "ruo",
	"曦": "xi", "雨": "yu", "桐": "tong", "皓": "hao", "然": "ran",
	"天": "tian", "雅": "ya", "可": "ke", "昕": "xin", "文": "wen",
	"俊": "jun", "熙": "xi", "智": "zhi", "渊": "yuan", "知": "zhi",
	"行": "xing", "承": "cheng", "泽": "ze", "辰": "chen", "逸": "yi",
	"锦": "jin", "程": "cheng", "卓": "zhuo", "尔": "er", "韵": "yun",
	"栩": "xu", "听": "ting", "澜": "lan", "立": "li", "诚": "cheng",
	"怀": "huai",
}

## 中文真名 → 首字母大写拼音。首字当姓, 其余当名:
## 姓与名各自首字母大写, 名内多字相连。"李婉清" → "Li Wanqing"。
## 任一字不在 _PINYIN (玩家自取名 / 默认 "创始人" / 英文名) → 整串原样返回。
static func romanize(cn_name: String) -> String:
	if cn_name.length() < 1:
		return cn_name
	var surname: String = _PINYIN.get(cn_name[0], "")
	if surname.is_empty():
		return cn_name  # 表外姓 → passthrough
	var given := ""
	for i in range(1, cn_name.length()):
		var py: String = _PINYIN.get(cn_name[i], "")
		if py.is_empty():
			return cn_name  # 表外名字 → passthrough (不半翻)
		given += py
	if given.is_empty():
		return _cap(surname)  # 单字名 (无名), 罕见
	return _cap(surname) + " " + _cap(given)

## locale 感知显示: zh* locale 原样中文, 否则转拼音。显示处一律走它。
static func localized(cn_name: String) -> String:
	if TranslationServer.get_locale().begins_with("zh"):
		return cn_name
	return romanize(cn_name)

static func _cap(s: String) -> String:
	if s.is_empty():
		return s
	return s.substr(0, 1).to_upper() + s.substr(1)
