extends Object

## DcCard helper — 把 Datacenter resource 翻译成 Card.set_data 字典。
##
## 调用方传入 facility/gpu/power 三套 display label (来自 InfraSystem 的
## display_name 表), card 内不再访问任何 system。

# 值为 i18n key (const 不能调 tr); 取用处 _t()。
const _STATUS_LABELS: Dictionary = {
	&"idle":     "INFRA_STATUS_IDLE",
	&"training": "INFRA_STATUS_TRAINING",
	&"serving":  "INFRA_STATUS_SERVING",
}

const _OWNERSHIP_LABELS: Dictionary = {
	&"owned":  "INFRA_OWN_OWNED",
	&"rented": "INFRA_OWN_RENTED",
	&"cloud":  "DC_OWN_CLOUD",
}

# static 上下文没有 self, 不能调 tr(); 走 TranslationServer (同样含 fallback)。
static func _t(key: String) -> String:
	return TranslationServer.translate(key)

static func populate(card: Control, dc, facility_label: String, gpu_label: String, power_label: String, serving_target_label: String = "", icon: Texture2D = null, train_bonus: float = 0.0, rental_net: int = 0) -> void:
	card.set_data(_build(dc, facility_label, gpu_label, power_label, serving_target_label, icon, train_bonus, rental_net))

static func _build(dc, facility_label: String, gpu_label: String, power_label: String, serving_target_label: String = "", icon: Texture2D = null, train_bonus: float = 0.0, rental_net: int = 0) -> Dictionary:
	var status: StringName = StringName(dc.status)
	var ownership_label: String = _t(_OWNERSHIP_LABELS.get(StringName(dc.ownership), "INFRA_OWN_RENTED"))
	# 副标题只放短信息 (机房档位 · 租用/自建/云租用), GPU / 供电等长字段进字段区,
	# 避免被卡片省略号截断 (见 design/UI视觉系统设计.md §8.1)。
	# cloud DC 无 facility, 只显示 ownership。
	var subtitle_parts: Array = []
	if facility_label != "":
		subtitle_parts.append(facility_label)
	subtitle_parts.append(ownership_label)
	return {
		"title": dc.display_label(),
		"subtitle": " · ".join(subtitle_parts),
		"avatar": {
			"texture": icon,
			# 缺图 (云租用 DC 无 facility, facility_spec_id == "") 时回退到 datacenter
			# glyph "▣", 而不是机房名首字母 — 字母圈看着像人物头像, 不像数据中心。
			# facility 租用/自建有 icon, fallback_text 不会被用到。
			"fallback_text": dc.display_label() if icon != null else "",
			"seed_id": StringName(dc.id),
			"kind": &"datacenter",
		},
		"status": {
			"label": _t(_STATUS_LABELS.get(status, String(status))),
			"kind": _status_badge_kind(status),
		},
		"fields": _fields(dc, gpu_label, power_label, serving_target_label, train_bonus, rental_net),
		"actions": _actions(dc),
	}

static func _status_badge_kind(status: StringName) -> StringName:
	match status:
		&"serving":  return &"published"   # 绿 — 在产
		&"training": return &"training"    # 蓝 — 进行中
		_:           return &"neutral"

static func _fields(dc, gpu_label: String, power_label: String, serving_target_label: String = "", train_bonus: float = 0.0, rental_net: int = 0) -> Array:
	var rows: Array = []
	# GPU 型号 × 卡数 (无 GPU 时只显示 "无 GPU")。
	if String(dc.gpu_id) != "":
		rows.append({"label": "GPU", "value": "%s × %d" % [gpu_label, int(dc.gpu_count)]})
	else:
		rows.append({"label": "GPU", "value": _t("INFRA_NO_GPU")})
	rows.append({"label": _t("DC_POWER"), "value": power_label})
	rows.append({"label": _t("DC_CAPACITY"), "value": "%d / %d GPU" % [int(dc.gpu_count), int(dc.max_gpu_count)]})
	rows.append({"label": _t("DC_TRAIN"), "value": UITheme.format_compute(float(dc.train_tflops))})
	# 太空数据中心训练加速 — 仅太空档 (train_bonus > 0) 显示, 标明 train_tflops 已含的加成。
	if train_bonus > 0.0:
		rows.append({"label": _t("DC_TRAIN_BONUS"), "value": "+%d%%" % int(round(train_bonus * 100.0))})
	# serving 时显示真实 t/s 容量, idle / training 时显示物理 inference TFLOPs。
	if StringName(dc.status) == &"serving" and float(dc.serving_tokens_per_sec) > 0.0:
		rows.append({"label": _t("DC_INFER"), "value": "%.0f tok/s" % float(dc.serving_tokens_per_sec)})
	else:
		rows.append({"label": _t("DC_INFER"), "value": UITheme.format_compute(float(dc.inference_tflops))})
	rows.append({"label": _t("DC_WEEKLY_COST"), "value": "$%s" % _money(int(dc.facility_weekly_cost))})
	# 闲置 owned dc 出租到算力平台的每周净收益 (扣 22% 平台费后)。idle 才显示。
	if rental_net > 0:
		rows.append({"label": _t("DC_RENTAL"), "value": "+$%s" % _money(rental_net)})
	# 部署目标 (如果有)
	if StringName(dc.status) == &"serving":
		var target := serving_target_label
		if target == "":
			target = String(dc.serving_target_id) if String(dc.serving_target_id) != "" else String(dc.deployed_model_id)
		if target != "":
			rows.append({"label": _t("DC_RUNNING"), "value": target})
	elif String(dc.deployed_model_id) != "":
		rows.append({"label": _t("DC_RUNNING"), "value": serving_target_label if serving_target_label != "" else String(dc.deployed_model_id)})
	return rows

static func _actions(dc) -> Array:
	match StringName(dc.status):
		&"idle":
			var acts: Array = [{"id": &"deploy", "label": _t("DC_DEPLOY")}]
			# 出租到算力平台 (opt-in): 仅 idle 非 cloud 且有卡时给出开关按钮。
			if StringName(dc.ownership) != &"cloud" and int(dc.gpu_count) > 0:
				if bool(dc.rent_out_enabled):
					acts.append({"id": &"stop_rent_out", "label": _t("DC_STOP_RENT_OUT")})
				else:
					acts.append({"id": &"rent_out", "label": _t("DC_RENT_OUT")})
			acts.append({"id": &"terminate", "label": _t("DC_TERMINATE")})
			return acts
		&"serving":
			return [{"id": &"undeploy", "label": _t("DC_UNDEPLOY")}]
		_:
			# training: 无操作 (任务占用中)
			return []

# 旧存档 display_name 尾部 " [dc_NNNN]" 内部 id 的裁剪现已并入 Datacenter.display_label()。

static func _money(n: int) -> String:
	var s := str(abs(n))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	if n < 0:
		out = "-" + out
	return out
