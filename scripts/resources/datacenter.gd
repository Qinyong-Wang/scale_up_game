class_name Datacenter
extends Resource

## Compute asset (facility + installed GPUs).
## Lives in InfraSystem.datacenters.
## Three-state machine: idle / training / serving.
## Per design/基础设施系统设计.md §1 (v2).
##
## v3 schema (2026-05): the old 7B-baseline `inference_tokens_per_sec` is split
## into two real-world fields:
##   - inference_tflops          → device-only inference compute (model-agnostic)
##   - serving_tokens_per_sec    → t/s after deploying the current model
##                                 (= inference_tflops × 1e12 / model.flops_per_token);
##                                 set by infra.deploy_model, cleared by undeploy.
## MonetizationSystem now reads `serving_tokens_per_sec` directly and no longer
## scales by model.flops_per_token.
##
## v2 schema split:
##   - facility_spec_id  → 机房档位 (capacity + land cost)
##   - power_supply       → 供电方式 (efficiency + electricity)
##   - gpu_id + gpu_count + gpu_purchase_history → installed cards (single brand)
##   - train_tflops / inference_tflops → derived, recomputed on buy/sell
##
## from_dict still tolerates the legacy field names (spec_id /
## train_throughput / inference_throughput / inference_tokens_per_sec /
## facility_monthly_cost / monthly_cost) so old saves load cleanly. New code
## must use the canonical names listed above.

const GPUBatchClass := preload("res://scripts/resources/gpu_batch.gd")

@export var id: StringName
@export var display_name: String = ""

# === Facility / power configuration (set at rent/build time) ===
@export var facility_spec_id: StringName
@export var ownership: StringName = &"rented"  # &"rented" / &"owned"
@export var power_supply: StringName = &"grid"
@export var max_gpu_count: int = 1

# === Installed GPU asset (single-brand constraint) ===
@export var gpu_id: StringName = &""
@export var gpu_count: int = 0
@export var gpu_purchase_history: Array = []  # Array[GPUBatch]

# === Derived compute (recomputed every buy/sell) ===
@export var train_tflops: float = 0.0
@export var inference_tflops: float = 0.0     # v3: physical sustained inference TFLOPs (model-agnostic)
@export var cluster_efficiency: float = 0.0
@export var facility_weekly_cost: int = 0    # land + GPU maint + electricity (cached, ¥/week)

# === Derived from currently-deployed model (cached at deploy time) ===
# v3: t/s capacity for whatever model is currently bound on this dc; 0 when idle.
# = inference_tflops × 1e12 / max(model.flops_per_token, 1).
# MonetizationSystem reads this directly to compute weekly capacity.
@export var serving_tokens_per_sec: float = 0.0

# === State machine ===
@export var status: StringName = &"idle"  # &"idle" / &"training" / &"serving"
@export var serving_target_kind: StringName = &""  # &"owned_model" / &"open_source_model"
@export var serving_target_id: StringName = &""
@export var deployed_model_id: StringName = &""
@export var busy_with_task_id: StringName = &""

# === 出租到算力平台 (2026-05) ===
# 玩家 opt-in: 开启后, 此 dc 在 idle 时把已装 GPU 出租到算力平台 (见 §4.4)。
# 默认关; cloud dc 不可出租。serving/training 时自动不出租 (算力自用)。
@export var rent_out_enabled: bool = false

## locale 感知的玩家可见名 (见 design/国际化设计.md §6ter)。所有显示 DC 名的地方都该
## 调它, 不要直接读 display_name:
##   - 云租 DC: display_name 不存中文, 按 ownership+卡数实时拼 INFRA_CLOUD_DC % count
##     (不把本地化结果烤进存档, 切语言即时生效)。
##   - 自建/自有 DC: display_name 存设施名 (content.csv 的中文 key), tr 成当前语言。
##   - 旧存档名尾部带 " [dc_NNNN]" 内部 id, 这里裁掉。
func display_label() -> String:
	var raw := String(display_name)
	var br: int = raw.rfind(" [dc_")
	if br != -1 and raw.ends_with("]"):
		raw = raw.substr(0, br)
	if ownership == &"cloud" or raw == "":
		return TranslationServer.translate("INFRA_CLOUD_DC") % max_gpu_count
	return TranslationServer.translate(raw)

func to_dict() -> Dictionary:
	var batches: Array = []
	for b in gpu_purchase_history:
		batches.append(b.to_dict())
	return {
		id = String(id),
		display_name = display_name,
		facility_spec_id = String(facility_spec_id),
		ownership = String(ownership),
		power_supply = String(power_supply),
		max_gpu_count = max_gpu_count,
		gpu_id = String(gpu_id),
		gpu_count = gpu_count,
		gpu_purchase_history = batches,
		train_tflops = train_tflops,
		inference_tflops = inference_tflops,
		serving_tokens_per_sec = serving_tokens_per_sec,
		cluster_efficiency = cluster_efficiency,
		facility_weekly_cost = facility_weekly_cost,
		status = String(status),
		serving_target_kind = String(serving_target_kind),
		serving_target_id = String(serving_target_id),
		deployed_model_id = String(deployed_model_id),
		busy_with_task_id = String(busy_with_task_id),
		rent_out_enabled = rent_out_enabled,
	}

static func from_dict(d: Dictionary) -> Datacenter:
	var dc := Datacenter.new()
	dc.id = StringName(d.get("id", ""))
	dc.display_name = String(d.get("display_name", ""))
	# tolerate old `spec_id` field
	var fid: String = String(d.get("facility_spec_id", d.get("spec_id", "")))
	dc.facility_spec_id = StringName(fid)
	dc.ownership = StringName(d.get("ownership", "rented"))
	dc.power_supply = StringName(d.get("power_supply", "grid"))
	dc.max_gpu_count = int(d.get("max_gpu_count", 0))
	dc.gpu_id = StringName(d.get("gpu_id", ""))
	dc.gpu_count = int(d.get("gpu_count", 0))
	var batches_raw = d.get("gpu_purchase_history", [])
	var batches: Array = []
	if batches_raw is Array:
		for raw in batches_raw:
			batches.append(GPUBatchClass.from_dict(raw))
	dc.gpu_purchase_history = batches
	# tolerate either new (train_tflops) or legacy (train_throughput) field
	dc.train_tflops = float(d.get("train_tflops", d.get("train_throughput", 0.0)))
	# v3: prefer inference_tflops; fall back to legacy inference_throughput (v2 alias).
	dc.inference_tflops = float(d.get("inference_tflops",
		d.get("inference_throughput", 0.0)))
	# v3: serving_tokens_per_sec is fresh — pre-v3 saves had no equivalent
	# (the legacy `inference_tokens_per_sec` field was the same value, but it
	# represented "if you deployed a 7B model"). For correctness the next deploy
	# call will recompute. For readability we still tolerate the legacy field
	# under its old name on save load (it's idle on load anyway).
	dc.serving_tokens_per_sec = float(d.get("serving_tokens_per_sec",
		d.get("inference_tokens_per_sec", 0.0)))
	dc.cluster_efficiency = float(d.get("cluster_efficiency", 0.0))
	# v7 PR-F: fame_modifier field deleted; legacy save's value is dropped.
	# Accept legacy facility_monthly_cost / monthly_cost; value is now per-week.
	dc.facility_weekly_cost = int(d.get("facility_weekly_cost",
		d.get("facility_monthly_cost", d.get("monthly_cost", 0))))
	dc.status = StringName(d.get("status", "idle"))
	dc.deployed_model_id = StringName(d.get("deployed_model_id", ""))
	var legacy_target_id := String(d.get("deployed_model_id", ""))
	dc.serving_target_kind = StringName(d.get("serving_target_kind",
			"owned_model" if legacy_target_id != "" else ""))
	dc.serving_target_id = StringName(d.get("serving_target_id", legacy_target_id))
	dc.busy_with_task_id = StringName(d.get("busy_with_task_id", ""))
	dc.rent_out_enabled = bool(d.get("rent_out_enabled", false))
	return dc
