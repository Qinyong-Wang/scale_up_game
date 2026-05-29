class_name Model
extends Resource

## A trained AI model. Lives in GameState.models. Created by TaskSystem
## (pretrain completion → research.add_model) and mutated by post-training,
## evaluation, or publishing actions. Per design/研究系统设计.md §1.

@export var id: StringName
@export var display_name: String = ""
@export var arch: StringName

# Capability axes, 0..100 each. Initial axes provided by the training task;
# missing axes default to 0.0. Hidden until evaluate runs.
@export var capability: Dictionary = {}
@export var capability_revealed: bool = false
@export var capability_stale: bool = false

# Physical / inference characteristics. Set at pretrain time, not mutated by
# posttrain. Per 研究系统设计.md §1 + 任务系统设计.md §6.6 (scaling law).
@export var size_params: float = 0.0           # total parameter count, in millions of params
# v4 (PR-B): for MoE-family archs only a fraction of params is active per token.
# Set at pretrain time (research.add_model) from ACTIVE_PARAM_RATIO_BY_ARCH.
# Drives both flops_per_token and training compute. Chinchilla optimal-tokens
# still uses TOTAL params (MoE is data-hungry per design 平衡参数.md).
@export var active_param_ratio: float = 1.0
# v5 (PR-C): PretrainDialog A/B/C/D 4-axis split. arch_id is the "family"
# (A-axis); below are B/C/D. All are set once at pretrain and frozen.
@export var attention_id: StringName = &"mha_baseline"      # B-axis
@export var loss_id: StringName = &"ce_baseline"            # C-axis
@export var context_length_tokens: int = 4096               # D-axis
## v7 PR-G: PretrainDialog E-axis — multimodal training method. `&"none"` for
## single-modality models; otherwise &"cross_train" (default) / &"diffusion_ar" /
## &"pixel_ar" / &"native_ar". Affects evaluate multimodal capability_coef +
## train_penalty. Frozen at pretrain.
@export var multimodal_method: StringName = &"none"         # E-axis (v7 PR-G)
## 预训练科学家加分倍率。在预训练完成时按 chief_scientist 的 ability×pretrain_score_bonus
## 烘焙 (= 1 + ability/100 × coef, 无加成则 1.0), evaluate 计算能力分时整体放大。
## Frozen at pretrain。Per 任务系统设计.md §6.7 + 招聘系统设计.md §5.1。
@export var pretrain_score_mult: float = 1.0
@export var flops_per_token: float = 0.0       # FLOPs cost of one inference token
                                               # = 2 × size × active_ratio × 1e6 / attention.inference_coef
@export var input_modalities: Array[StringName] = [&"text"]
@export var output_modalities: Array[StringName] = [&"text"]

@export var trained_at_turn: int = 0
@export var dataset_ids: Array[StringName] = []

# Lifecycle (4-state, per 研究系统设计.md §6.0):
#   &"pretrained" / &"posttrained" / &"evaluated" / &"published"
@export var status: StringName = &"pretrained"

# Counter of how many times posttrain_apply has run on this model. Kept for
# UI / audit (e.g. "posttrained 3 times") even after Bug B fix removed the
# (1 + 0.10 × posttrain_count) evaluate lift.
@export var posttrain_count: int = 0

# Bug B fix (2026-05): accumulated 5-axis delta from every posttrain_apply.
# research.evaluate_apply layers this on top of capability_measured so the
# axis-directional +target/-forget shifts survive re-evaluation. Per
# 研究系统设计.md §1 / §6.2 / §6.3.
@export var posttrain_delta: Dictionary = {
	&"general": 0.0, &"code": 0.0, &"reasoning": 0.0,
	&"multimodal": 0.0, &"agent": 0.0,
}

# Origin of the model.
#   &"trained"        — pretrained in-house by player.
#   &"downloaded_os"  — instantiated from an open-source template.
@export var provenance: StringName = &"trained"
@export var source_release_id: StringName = &""

# Monetization
@export var is_open_source: bool = false
@export var per_token_price: float = 0.0
@export var unpublished_at_turn: int = -1

# Old resources briefly stored "2 × size_params_M" style shorthand values
# (e.g. 7B → 14000) while the serving formula already expected raw FLOPs.
const LEGACY_SHORT_FPT_THRESHOLD: float = 1_000_000.0

# v4 (PR-B): authoritative MoE active-param-ratio table. Dense archs (anything
# not listed here) default to 1.0. Promoted from task_system._active_param_ratio
# so Model + TaskSystem + ResearchSystem all read the same table.
# Per design/平衡参数.md "模型架构激活参数比例".
const ACTIVE_PARAM_RATIO_BY_ARCH: Dictionary = {
	&"octopus_v1": 0.25,             # MoE 4 选 1 (≈ Mixtral 8×7B)
	&"octopus_v2": 0.125,            # MoE 8 选 1 (≈ Mixtral 8×22B)
	&"octopus_sparse": 0.05,         # v5 (PR-C) Sparse MoE 1/20 (≈ DeepSeek-V3)
	&"octopus_super_sparse": 0.025,  # v5 (PR-C) Super-Sparse MoE 1/40 (前沿)
}

static func active_param_ratio_for(arch_id: StringName) -> float:
	return float(ACTIVE_PARAM_RATIO_BY_ARCH.get(arch_id, 1.0))

# ---- helpers ------------------------------------------------------------

static func infer_flops_per_token(size_params_m: float, active_ratio: float = 1.0) -> float:
	if size_params_m <= 0.0:
		return 0.0
	return 2.0 * size_params_m * maxf(active_ratio, 0.0) * 1.0e6

static func normalize_flops_per_token(raw_fpt: float, size_params_m: float, active_ratio: float = 1.0) -> float:
	var inferred: float = infer_flops_per_token(size_params_m, active_ratio)
	if inferred > 0.0 and raw_fpt < LEGACY_SHORT_FPT_THRESHOLD:
		return inferred
	return maxf(raw_fpt, 0.0)

## §1: capability is hidden until evaluate sets capability_revealed.
## UI calls this to decide whether to show numbers or "??" placeholders.
func displayable_capability() -> Dictionary:
	if capability_revealed:
		return capability.duplicate()
	return {}

## §6.4: only evaluated models with fresh capability may be published.
func is_publishable() -> bool:
	return status == &"evaluated" and not capability_stale

# ---- save / load --------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		id = String(id),
		display_name = display_name,
		arch = String(arch),
		capability = capability.duplicate(),
		capability_revealed = capability_revealed,
		capability_stale = capability_stale,
		size_params = size_params,
		active_param_ratio = active_param_ratio,
		attention_id = String(attention_id),
		loss_id = String(loss_id),
		context_length_tokens = context_length_tokens,
		multimodal_method = String(multimodal_method),
		pretrain_score_mult = pretrain_score_mult,
		flops_per_token = flops_per_token,
		input_modalities = _sn_array_to_strings(input_modalities),
		output_modalities = _sn_array_to_strings(output_modalities),
		trained_at_turn = trained_at_turn,
		dataset_ids = _sn_array_to_strings(dataset_ids),
		status = String(status),
		posttrain_count = posttrain_count,
		posttrain_delta = posttrain_delta.duplicate(),
		provenance = String(provenance),
		source_release_id = String(source_release_id),
		is_open_source = is_open_source,
		per_token_price = per_token_price,
		unpublished_at_turn = unpublished_at_turn,
	}

static func from_dict(d: Dictionary) -> Model:
	var m := Model.new()
	m.id = StringName(d.get("id", ""))
	m.display_name = String(d.get("display_name", ""))
	m.arch = StringName(d.get("arch", ""))
	m.capability = (d.get("capability", {}) as Dictionary).duplicate()
	m.capability_revealed = bool(d.get("capability_revealed", false))
	m.capability_stale = bool(d.get("capability_stale", false))
	m.size_params = float(d.get("size_params", 0.0))
	# v4 (PR-B): legacy saves don't carry active_param_ratio; reconstruct it
	# from arch so MoE models loaded from old saves still have correct fpt.
	m.active_param_ratio = float(d.get("active_param_ratio",
			active_param_ratio_for(m.arch)))
	# v5 (PR-C): A/B/C/D axes — default to baselines for legacy saves.
	m.attention_id = StringName(d.get("attention_id", "mha_baseline"))
	m.loss_id = StringName(d.get("loss_id", "ce_baseline"))
	m.context_length_tokens = int(d.get("context_length_tokens", 4096))
	# v7 PR-G: legacy saves default multimodal_method to none.
	m.multimodal_method = StringName(d.get("multimodal_method", "none"))
	# 旧存档无此字段 → 1.0 (无加成), 不影响既有模型能力分。
	m.pretrain_score_mult = float(d.get("pretrain_score_mult", 1.0))
	m.flops_per_token = normalize_flops_per_token(
			float(d.get("flops_per_token", 0.0)), m.size_params, m.active_param_ratio)
	m.input_modalities = _strings_to_sn_array(d.get("input_modalities", []))
	m.output_modalities = _strings_to_sn_array(d.get("output_modalities", []))
	m.trained_at_turn = int(d.get("trained_at_turn", 0))
	m.dataset_ids = _strings_to_sn_array(d.get("dataset_ids", []))
	# Backward compat: old saves used the 2-state &"internal" / &"published" alphabet.
	# Map &"internal" → &"pretrained" so legacy saves still load (per task spec).
	var raw_status: StringName = StringName(d.get("status", "pretrained"))
	if raw_status == &"internal":
		raw_status = &"pretrained"
	m.status = raw_status
	m.posttrain_count = int(d.get("posttrain_count", 0))
	# Legacy saves predate Bug B fix → posttrain_delta absent; default to zeros.
	var raw_pt_delta = d.get("posttrain_delta", null)
	if raw_pt_delta == null:
		m.posttrain_delta = {
			&"general": 0.0, &"code": 0.0, &"reasoning": 0.0,
			&"multimodal": 0.0, &"agent": 0.0,
		}
	else:
		var pt: Dictionary = {}
		for ax in [&"general", &"code", &"reasoning", &"multimodal", &"agent"]:
			pt[ax] = float((raw_pt_delta as Dictionary).get(String(ax),
					(raw_pt_delta as Dictionary).get(ax, 0.0)))
		m.posttrain_delta = pt
	m.provenance = StringName(d.get("provenance", "trained"))
	m.source_release_id = StringName(d.get("source_release_id", ""))
	m.is_open_source = bool(d.get("is_open_source", false))
	m.per_token_price = float(d.get("per_token_price", 0.0))
	m.unpublished_at_turn = int(d.get("unpublished_at_turn", -1))
	# v7 PR-F: demand_multiplier field deleted; v6 saves' value is dropped.
	return m

static func _sn_array_to_strings(arr) -> Array:
	var out: Array = []
	for v in arr: out.append(String(v))
	return out

static func _strings_to_sn_array(arr) -> Array[StringName]:
	var out: Array[StringName] = []
	for v in arr: out.append(StringName(v))
	return out
