class_name PersonName
extends RefCounted

## 按族裔 + 性别生成人名的纯静态工具。见 design/招聘系统设计.md §1.3。
##
## lead 的头像是多元肖像池 (东亚 / 白人 / 黑人 / 南亚 / 西语裔 / 中东 / 东南亚),
## 名字必须跟头像一致, 否则一张白人的脸配 "王美丽" → 出戏。调用方 (HiringSystem)
## 先用 IconRegistry.lead_demographics(lead.id) 拿到 {region, gender}, 再来这里取名。
##
## 用法:
##   var demo := IconRegistry.lead_demographics(lead.id)   # {region, gender}
##   var name := PersonName.generate(demo.region, demo.gender, GameState.rng())
##
## 设计要点:
## - east_asian 出中文姓+名 (字与 NameRomanizer._PINYIN 同一批, en locale 下转拼音)。
## - 其余 region 出拉丁字母 "Given Surname", **纯 ASCII** (无 é/ñ/ư 等变音), 避免
##   字体缺字露豆腐块; 任一 locale 都原样显示 (走 NameRomanizer passthrough)。
## - 姓名各为单 token (姓不含空格), 调用方/测试可安全按单空格切分。
## - gender ∈ {&"male", &"female"} 选男/女名池; 姓氏池性别共用。
## - region 粗粒度: western 一个池覆盖所有 Anglophone 头像 (白人/黑人/…), 不按肤色
##   再细分名字。未知 region / gender → 回退 east_asian / female, 保证总有名字。

const REGIONS: Array[StringName] = [
	&"east_asian", &"western", &"south_asian",
	&"hispanic", &"middle_eastern", &"southeast_asian",
]

# ── East Asian (中文) ──────────────────────────────────────────────
# 字全部取自 NameRomanizer._PINYIN 覆盖的那批 (45 姓 + 60 名), 不引入新字,
# 否则 en locale 下会露中文。name_romanizer_test 守护这条。
const EAST_ASIAN_SURNAMES: Array[String] = [
	"王", "李", "张", "刘", "陈", "杨", "黄", "赵", "吴", "周",
	"徐", "孙", "马", "朱", "胡", "郭", "何", "高", "林", "罗",
	"郑", "梁", "谢", "宋", "唐", "许", "韩", "冯", "邓", "曹",
	"彭", "曾", "肖", "田", "董", "袁", "潘", "蒋", "蔡", "余",
	"沈", "魏", "钟", "姚", "苏",
]
const EAST_ASIAN_GIVEN_MALE: Array[String] = [
	"伟", "强", "磊", "杰", "涛", "明", "超", "军", "辉", "鹏",
	"宇", "浩", "凯", "睿", "博", "翔", "晨",
	"宇轩", "子墨", "思远", "皓然", "天宇", "嘉伟", "文博", "俊熙",
	"智渊", "知行", "承泽", "辰逸", "锦程", "怀远", "立诚",
]
const EAST_ASIAN_GIVEN_FEMALE: Array[String] = [
	"敏", "静", "丽", "雪", "婷", "娜", "倩", "璐", "瑶", "妍",
	"悦", "瑾", "琳",
	"婉清", "佳怡", "梓涵", "嘉欣", "诗涵", "若曦", "雨桐", "雅婷",
	"可昕", "晨曦", "卓尔", "怀瑾", "清韵", "栩然", "听澜",
]

# ── Western / Anglophone (白人 + 黑人头像共用) ──────────────────────
const WESTERN_SURNAMES: Array[String] = [
	"Smith", "Johnson", "Williams", "Brown", "Jones", "Miller", "Davis",
	"Wilson", "Anderson", "Thomas", "Taylor", "Moore", "Jackson", "Martin",
	"Walker", "Hall", "Allen", "Young", "King", "Wright", "Scott", "Green",
	"Baker", "Adams", "Nelson", "Carter", "Mitchell", "Roberts", "Turner",
	"Phillips", "Campbell", "Parker", "Evans", "Collins", "Stewart", "Murphy",
	"Cooper", "Richardson", "Howard", "Brooks", "Bennett", "Bell", "Coleman",
]
const WESTERN_GIVEN_MALE: Array[String] = [
	"James", "Michael", "David", "Daniel", "Christopher", "Marcus", "Andre",
	"Ethan", "Liam", "Noah", "Benjamin", "Samuel", "Nathan", "Adrian",
	"Gabriel", "Oliver", "Henry", "Lucas", "Isaiah", "Malik", "Darius",
	"Jordan", "Eric", "Brandon", "Kevin", "Sean", "Patrick", "Theo",
]
const WESTERN_GIVEN_FEMALE: Array[String] = [
	"Emily", "Sarah", "Jessica", "Ashley", "Olivia", "Emma", "Sophia",
	"Hannah", "Grace", "Chloe", "Madison", "Aaliyah", "Imani", "Jasmine",
	"Nicole", "Rachel", "Megan", "Lauren", "Victoria", "Natalie", "Rebecca",
	"Maya", "Zoe", "Claire", "Alexis", "Naomi", "Vanessa", "Brianna",
]

# ── South Asian ────────────────────────────────────────────────────
const SOUTH_ASIAN_SURNAMES: Array[String] = [
	"Sharma", "Patel", "Singh", "Kumar", "Gupta", "Reddy", "Nair", "Rao",
	"Iyer", "Desai", "Mehta", "Chopra", "Joshi", "Verma", "Bose", "Agarwal",
	"Kapoor", "Banerjee", "Malhotra", "Pillai",
]
const SOUTH_ASIAN_GIVEN_MALE: Array[String] = [
	"Arjun", "Rohan", "Vikram", "Aditya", "Rahul", "Karan", "Sanjay", "Anil",
	"Deepak", "Nikhil", "Amit", "Ravi", "Suresh", "Vivek", "Ishaan", "Aryan",
	"Kabir", "Varun",
]
const SOUTH_ASIAN_GIVEN_FEMALE: Array[String] = [
	"Priya", "Anjali", "Kavya", "Neha", "Pooja", "Divya", "Sneha", "Meera",
	"Riya", "Ananya", "Shreya", "Deepika", "Nisha", "Ishita", "Sana", "Tara",
	"Lakshmi", "Aditi",
]

# ── Hispanic / Latino (西语裔 + 拉丁裔头像共用) ─────────────────────
const HISPANIC_SURNAMES: Array[String] = [
	"Garcia", "Martinez", "Rodriguez", "Lopez", "Gonzalez", "Hernandez",
	"Perez", "Sanchez", "Ramirez", "Torres", "Flores", "Rivera", "Gomez",
	"Diaz", "Cruz", "Morales", "Ortiz", "Castillo", "Vargas", "Romero",
]
const HISPANIC_GIVEN_MALE: Array[String] = [
	"Carlos", "Miguel", "Jose", "Luis", "Juan", "Diego", "Javier", "Antonio",
	"Fernando", "Ricardo", "Alejandro", "Eduardo", "Pablo", "Mateo", "Andres",
	"Rafael", "Sergio", "Emilio",
]
const HISPANIC_GIVEN_FEMALE: Array[String] = [
	"Maria", "Sofia", "Valentina", "Camila", "Lucia", "Isabella", "Gabriela",
	"Daniela", "Carmen", "Elena", "Paula", "Adriana", "Natalia", "Ximena",
	"Rosa", "Mariana", "Lorena", "Victoria",
]

# ── Middle Eastern ─────────────────────────────────────────────────
const MIDDLE_EASTERN_SURNAMES: Array[String] = [
	"Haddad", "Khalil", "Mansour", "Nasser", "Saleh", "Aziz", "Karam",
	"Najjar", "Darwish", "Sayed", "Bishara", "Fares", "Hamdan", "Ibrahim",
	"Younes", "Saab", "Hariri", "Toma",
]
const MIDDLE_EASTERN_GIVEN_MALE: Array[String] = [
	"Omar", "Khaled", "Hassan", "Ali", "Yusuf", "Tariq", "Karim", "Samir",
	"Bilal", "Rami", "Nabil", "Faisal", "Ahmad", "Ziad", "Hadi", "Amir",
	"Walid", "Mahmoud",
]
const MIDDLE_EASTERN_GIVEN_FEMALE: Array[String] = [
	"Layla", "Yasmin", "Noor", "Fatima", "Amira", "Salma", "Rania", "Dalia",
	"Mariam", "Huda", "Leila", "Nadia", "Zaina", "Hana", "Farah", "Lina",
	"Reem", "Sara",
]

# ── Southeast Asian (越/泰/印尼/菲混合) ────────────────────────────
const SOUTHEAST_ASIAN_SURNAMES: Array[String] = [
	"Nguyen", "Tran", "Le", "Pham", "Wijaya", "Santoso", "Hidayat", "Halim",
	"Reyes", "Santos", "Bautista", "Tanaka", "Wong", "Lim", "Tan", "Suharto",
	"Prasetyo", "Chai",
]
const SOUTHEAST_ASIAN_GIVEN_MALE: Array[String] = [
	"Bao", "Minh", "Tuan", "Hieu", "Kiet", "Rizal", "Bayu", "Adi", "Surya",
	"Somchai", "Wira", "Eko", "Dharma", "Ade", "Reza", "Anucha",
]
const SOUTHEAST_ASIAN_GIVEN_FEMALE: Array[String] = [
	"Mai", "Linh", "Lan", "Huong", "Thuy", "Sari", "Putri", "Dewi", "Ratih",
	"Intan", "Mali", "Kanya", "Achara", "Citra", "Wati", "Dahlia",
]

# region -> { &"surnames": Array, &"male": Array, &"female": Array }
const _POOLS: Dictionary = {
	&"east_asian": {
		&"surnames": EAST_ASIAN_SURNAMES,
		&"male": EAST_ASIAN_GIVEN_MALE,
		&"female": EAST_ASIAN_GIVEN_FEMALE,
	},
	&"western": {
		&"surnames": WESTERN_SURNAMES,
		&"male": WESTERN_GIVEN_MALE,
		&"female": WESTERN_GIVEN_FEMALE,
	},
	&"south_asian": {
		&"surnames": SOUTH_ASIAN_SURNAMES,
		&"male": SOUTH_ASIAN_GIVEN_MALE,
		&"female": SOUTH_ASIAN_GIVEN_FEMALE,
	},
	&"hispanic": {
		&"surnames": HISPANIC_SURNAMES,
		&"male": HISPANIC_GIVEN_MALE,
		&"female": HISPANIC_GIVEN_FEMALE,
	},
	&"middle_eastern": {
		&"surnames": MIDDLE_EASTERN_SURNAMES,
		&"male": MIDDLE_EASTERN_GIVEN_MALE,
		&"female": MIDDLE_EASTERN_GIVEN_FEMALE,
	},
	&"southeast_asian": {
		&"surnames": SOUTHEAST_ASIAN_SURNAMES,
		&"male": SOUTHEAST_ASIAN_GIVEN_MALE,
		&"female": SOUTHEAST_ASIAN_GIVEN_FEMALE,
	},
}

## 取一个名字。east_asian → "姓名" (无空格); 其余 → "Given Surname" (单空格)。
## rng 必传 (用 GameState.rng() 保证同 seed 可重现)。未知 region/gender → 回退。
static func generate(region: StringName, gender: StringName, rng: RandomNumberGenerator) -> String:
	var surnames := surnames_for(region)
	var given := given_for(region, gender)
	if surnames.is_empty() or given.is_empty():
		return ""
	var s: String = surnames[rng.randi_range(0, surnames.size() - 1)]
	var g: String = given[rng.randi_range(0, given.size() - 1)]
	if _resolve_region(region) == &"east_asian":
		return s + g
	return g + " " + s

## 该 region 的姓氏池 (性别共用)。未知 region → east_asian。
static func surnames_for(region: StringName) -> Array:
	return _POOLS[_resolve_region(region)][&"surnames"]

## 该 region + gender 的名池。未知 gender → female。未知 region → east_asian。
static func given_for(region: StringName, gender: StringName) -> Array:
	var key: StringName = &"male" if gender == &"male" else &"female"
	return _POOLS[_resolve_region(region)][key]

static func _resolve_region(region: StringName) -> StringName:
	return region if _POOLS.has(region) else &"east_asian"
