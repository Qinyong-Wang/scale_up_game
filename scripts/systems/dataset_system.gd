extends Node

## DatasetSystem v2 — owns datasets.
## Per design/数据集系统设计.md (v2).
##
## Two kinds: pretrain / posttrain. Three sources: open_source / purchased /
## collected. Templates split into two Resource classes
## (PretrainDatasetTemplate / PosttrainDatasetTemplate) and live in disjoint
## subdirectories so DatasetSystem can scan + cache them per-kind.
##
## Time-gated release: each template carries `released_at_week`; the market
## list (and acquire / purchase commands) refuse templates whose release week
## is in the future.

const PretrainTemplate := preload("res://scripts/resources/pretrain_dataset_template.gd")
const PosttrainTemplate := preload("res://scripts/resources/posttrain_dataset_template.gd")

const OWNED_SLICES: Array[StringName] = [&"datasets"]

# Authoritative {template_id: path} tables. Listed explicitly (not scanned via
# DirAccess) because exported PCK builds do not reliably enumerate res:// dirs,
# which previously left builds with only 1 pretrain + 1 posttrain template.
# When adding a new .tres under resources/data/datasets/, append it here.
const PRETRAIN_PATHS: Dictionary = {
	&"bookcorpus_v1": "res://resources/data/datasets/pretrain/open_source/bookcorpus_v1.tres",
	&"chat_logs_v1": "res://resources/data/datasets/pretrain/open_source/chat_logs_v1.tres",
	&"code_giga_v1": "res://resources/data/datasets/pretrain/open_source/code_giga_v1.tres",
	&"code_snapshot_2020": "res://resources/data/datasets/pretrain/open_source/code_snapshot_2020.tres",
	&"commoncrawl_raw_2017": "res://resources/data/datasets/pretrain/open_source/commoncrawl_raw_2017.tres",
	&"dolma_corpus_v1": "res://resources/data/datasets/pretrain/open_source/dolma_corpus_v1.tres",
	&"fineweb2_multi_v1": "res://resources/data/datasets/pretrain/open_source/fineweb2_multi_v1.tres",
	&"fineweb_15t_v1": "res://resources/data/datasets/pretrain/open_source/fineweb_15t_v1.tres",
	&"fineweb_edu_v1": "res://resources/data/datasets/pretrain/open_source/fineweb_edu_v1.tres",
	&"code_forge_dump_2019": "res://resources/data/datasets/pretrain/open_source/code_forge_dump_2019.tres",
	&"image_caption_5b": "res://resources/data/datasets/pretrain/open_source/image_caption_5b.tres",
	&"image_corpus_v1": "res://resources/data/datasets/pretrain/open_source/image_corpus_v1.tres",
	&"imdb_reviews_v1": "res://resources/data/datasets/pretrain/open_source/imdb_reviews_v1.tres",
	&"khan_academy_textbook_v1": "res://resources/data/datasets/pretrain/open_source/khan_academy_textbook_v1.tres",
	&"math_reasoning_set_v1": "res://resources/data/datasets/pretrain/open_source/math_reasoning_set_v1.tres",
	&"openwebtext_v1": "res://resources/data/datasets/pretrain/open_source/openwebtext_v1.tres",
	&"redpajama_corpus_v1": "res://resources/data/datasets/pretrain/open_source/redpajama_corpus_v1.tres",
	&"roots_corpus_v1": "res://resources/data/datasets/pretrain/open_source/roots_corpus_v1.tres",
	&"the_compendium_v1": "res://resources/data/datasets/pretrain/open_source/the_compendium_v1.tres",
	&"web_corpus_v1": "res://resources/data/datasets/pretrain/open_source/web_corpus_v1.tres",
	&"webtext_clone_v1": "res://resources/data/datasets/pretrain/open_source/webtext_clone_v1.tres",
	&"wiki_dump_2017": "res://resources/data/datasets/pretrain/open_source/wiki_dump_2017.tres",
	&"codebase_v1": "res://resources/data/datasets/pretrain/purchased/codebase_v1.tres",
	&"news_archive_2017q2": "res://resources/data/datasets/pretrain/purchased/news_archive_2017q2.tres",
	&"phi_textbook_v1": "res://resources/data/datasets/pretrain/purchased/phi_textbook_v1.tres",
	&"polyglot_code_v1": "res://resources/data/datasets/pretrain/purchased/polyglot_code_v1.tres",
	&"science_reasoning_v1": "res://resources/data/datasets/pretrain/purchased/science_reasoning_v1.tres",
}
const POSTTRAIN_PATHS: Dictionary = {
	&"alpaca_52k_v1": "res://resources/data/datasets/posttrain/open_source/alpaca_52k_v1.tres",
	&"flan_seed_v1": "res://resources/data/datasets/posttrain/open_source/flan_seed_v1.tres",
	&"supervised_chat_v1": "res://resources/data/datasets/posttrain/open_source/supervised_chat_v1.tres",
	&"task_specific_sft_v1": "res://resources/data/datasets/posttrain/open_source/task_specific_sft_v1.tres",
	&"agent_traces_v1": "res://resources/data/datasets/posttrain/purchased/agent_traces_v1.tres",
	&"code_review_pairs_v1": "res://resources/data/datasets/posttrain/purchased/code_review_pairs_v1.tres",
	&"reasoning_chains_v1": "res://resources/data/datasets/posttrain/purchased/reasoning_chains_v1.tres",
}

# Lazy caches of {template_id: path}, seeded from PRETRAIN_PATHS / POSTTRAIN_PATHS
# on first access.
var _pretrain_cache: Dictionary = {}
var _posttrain_cache: Dictionary = {}
var _caches_built: bool = false

var _next_dataset_seq: int = 1
var _last_market_signal_turn: int = -1

func _ready() -> void:
	CommandBus.register(&"dataset.acquire_open", _on_acquire_open)
	CommandBus.register(&"dataset.purchase", _on_purchase)
	CommandBus.register(&"dataset.add", _on_add)
	CommandBus.register(&"dataset.delete", _on_delete)
	CommandBus.register(&"dataset.lock", _on_lock)
	CommandBus.register(&"dataset.release", _on_release)
	CommandBus.register(&"dataset.list_market", _on_list_market)
	EventBus.phase_started.connect(_on_phase)
	EventBus.save_loaded.connect(_on_save_loaded)

# ---- acquire / purchase / add -------------------------------------------

func _on_acquire_open(p: Dictionary) -> Dictionary:
	var template_id: StringName = p.get(&"template_id", &"")
	var entry := _load_template_any(template_id)
	if entry.is_empty():
		return {ok = false, error = &"unknown_template"}
	var template = entry.template
	var kind: StringName = entry.kind
	if template.source != &"open_source":
		return {ok = false, error = &"unknown_template"}
	if template.released_at_week > GameState.turn:
		return {ok = false, error = &"not_released_yet"}
	if _already_owned(template.id):
		return {ok = false, error = &"already_owned"}
	var ds := _instantiate(template, kind, &"open_source")
	GameState.datasets.append(ds)
	Log.info(&"dataset", "acquired_open", {dataset_id = ds.id, template = template.id, kind = kind})
	EventBus.dataset_added.emit(ds.id, &"open_source")
	return {ok = true, dataset_id = ds.id}

func _on_purchase(p: Dictionary) -> Dictionary:
	var template_id: StringName = p.get(&"template_id", &"")
	var entry := _load_template_any(template_id)
	if entry.is_empty():
		return {ok = false, error = &"unknown_template"}
	var template = entry.template
	var kind: StringName = entry.kind
	if template.source != &"purchased":
		return {ok = false, error = &"unknown_template"}
	if template.released_at_week > GameState.turn:
		return {ok = false, error = &"not_released_yet"}
	if _already_owned(template.id):
		return {ok = false, error = &"already_owned"}
	CommandBus.send(&"economy.spend", {
		cost = {&"cash": template.price},
		reason = &"dataset_purchase",
	})
	var ds := _instantiate(template, kind, &"purchased")
	GameState.datasets.append(ds)
	Log.info(&"dataset", "purchased", {dataset_id = ds.id, template = template.id, kind = kind})
	EventBus.dataset_added.emit(ds.id, &"purchased")
	return {ok = true, dataset_id = ds.id}

func _on_add(p: Dictionary) -> Dictionary:
	var ds := Dataset.new()
	ds.id = _gen_id()
	ds.display_name = p.get(&"display_name", "Collected #%d" % _next_dataset_seq)
	ds.kind = StringName(p.get(&"kind", &"pretrain"))
	ds.source = p.get(&"source", &"collected")
	# v7 PR-G: modality (text/image/audio/video). Legacy code values are read
	# as a text subset by TaskSystem. Defaults to text for legacy callers.
	ds.modality = StringName(p.get(&"modality", &"text"))
	ds.size = float(p.get(&"size", 0.0))
	ds.quality = float(p.get(&"quality", 0.0))
	var tags: Array = p.get(&"coverage_tags", [])
	var typed: Array[StringName] = []
	for t in tags:
		typed.append(StringName(t))
	ds.coverage_tags = typed
	ds.target_capability = StringName(p.get(&"target_capability", &""))
	GameState.datasets.append(ds)
	Log.info(&"dataset", "added", {dataset_id = ds.id, kind = ds.kind, source = ds.source, modality = ds.modality})
	EventBus.dataset_added.emit(ds.id, ds.source)
	return {ok = true, dataset_id = ds.id}

# ---- delete / lock / release --------------------------------------------

func _on_delete(p: Dictionary) -> Dictionary:
	var ds := find_dataset(p.get(&"dataset_id", &""))
	if ds == null:
		return {ok = false, error = &"unknown_dataset"}
	if ds.locked_by_task_id != &"":
		return {ok = false, error = &"locked"}
	GameState.datasets.erase(ds)
	EventBus.dataset_removed.emit(ds.id)
	return {ok = true}

func _on_lock(p: Dictionary) -> Dictionary:
	var ds := find_dataset(p.get(&"dataset_id", &""))
	if ds == null:
		return {ok = false, error = &"unknown_dataset"}
	if ds.locked_by_task_id != &"":
		return {ok = false, error = &"already_locked"}
	ds.locked_by_task_id = p.get(&"task_id", &"")
	EventBus.dataset_locked.emit(ds.id, ds.locked_by_task_id)
	return {ok = true}

func _on_release(p: Dictionary) -> Dictionary:
	var ds := find_dataset(p.get(&"dataset_id", &""))
	if ds == null:
		return {ok = false, error = &"unknown_dataset"}
	var task_id: StringName = p.get(&"task_id", &"")
	if ds.locked_by_task_id != task_id:
		return {ok = false, error = &"not_locked_by_this_task"}
	ds.locked_by_task_id = &""
	EventBus.dataset_released.emit(ds.id)
	return {ok = true}

# ---- market listing -----------------------------------------------------

## Lists templates that are released by current turn and not already owned.
## Filters by optional {kind, source}. Returns lightweight dicts for UI.
func _on_list_market(p: Dictionary) -> Dictionary:
	var kind_filter: StringName = StringName(p.get(&"kind", &""))
	var source_filter: StringName = StringName(p.get(&"source", &""))
	var items: Array = []
	for entry in _iter_all_templates():
		var tmpl = entry.template
		var kind: StringName = entry.kind
		if kind_filter != &"" and kind != kind_filter:
			continue
		if source_filter != &"" and tmpl.source != source_filter:
			continue
		if tmpl.released_at_week > GameState.turn:
			continue
		if _already_owned(tmpl.id):
			continue
		var tags_out: Array = []
		for t in tmpl.coverage_tags:
			tags_out.append(String(t))
		var tmpl_modality: StringName = &"text"
		if "modality" in tmpl and StringName(tmpl.modality) != &"":
			tmpl_modality = StringName(tmpl.modality)
		var d := {
			id = tmpl.id,
			display_name = tmpl.display_name,
			kind = kind,
			source = tmpl.source,
			modality = tmpl_modality,
			size = tmpl.size,
			quality = tmpl.quality,
			coverage_tags = tags_out,
			price = tmpl.price,
			released_at_week = tmpl.released_at_week,
		}
		if kind == &"posttrain":
			d[&"target_capability"] = tmpl.target_capability
		items.append(d)
	return {ok = true, items = items}

# ---- helpers ------------------------------------------------------------

func find_dataset(dataset_id: StringName) -> Dataset:
	for ds in GameState.datasets:
		if ds.id == dataset_id:
			return ds
	return null

func _on_phase(phase: StringName, _turn: int) -> void:
	# Fire market-updated signal once per ~half-year boundary (turn % 26 == 0).
	# UI uses this to highlight "new arrivals". Per design §6.4.
	if phase != &"action":
		return
	var t: int = GameState.turn
	if t > 0 and t % 26 == 0 and t != _last_market_signal_turn:
		_last_market_signal_turn = t
		EventBus.dataset_market_updated.emit(&"pretrain")
		EventBus.dataset_market_updated.emit(&"posttrain")

## Returns {template, kind} or {} if not found. Searches both caches.
func _load_template_any(template_id: StringName) -> Dictionary:
	_ensure_caches()
	if _pretrain_cache.has(template_id):
		var tmpl := _load_from_path(_pretrain_cache[template_id])
		if tmpl != null:
			return {template = tmpl, kind = &"pretrain"}
	if _posttrain_cache.has(template_id):
		var tmpl2 := _load_from_path(_posttrain_cache[template_id])
		if tmpl2 != null:
			return {template = tmpl2, kind = &"posttrain"}
	return {}

func _load_from_path(path: String) -> Resource:
	var res := load(path)
	if res is PretrainTemplate or res is PosttrainTemplate:
		return res
	return null

func _iter_all_templates() -> Array:
	_ensure_caches()
	var out: Array = []
	for id in _pretrain_cache.keys():
		var t := _load_from_path(_pretrain_cache[id])
		if t != null:
			out.append({template = t, kind = &"pretrain"})
	for id in _posttrain_cache.keys():
		var t := _load_from_path(_posttrain_cache[id])
		if t != null:
			out.append({template = t, kind = &"posttrain"})
	return out

func _ensure_caches() -> void:
	if _caches_built:
		return
	_pretrain_cache = PRETRAIN_PATHS.duplicate()
	_posttrain_cache = POSTTRAIN_PATHS.duplicate()
	_caches_built = true
	Log.info(&"dataset", "templates_loaded", {
		pretrain = _pretrain_cache.size(),
		posttrain = _posttrain_cache.size(),
	})

func _already_owned(template_id: StringName) -> bool:
	for ds in GameState.datasets:
		if ds.id == template_id:
			return true
	return false

func _instantiate(template: Resource, kind: StringName, source: StringName) -> Dataset:
	var ds := Dataset.new()
	ds.id = template.id
	ds.display_name = template.display_name
	ds.kind = kind
	ds.source = source
	# v7 PR-G: copy modality from template; default text if template was made
	# before the field existed (e.g. test fixtures).
	var mod: StringName = StringName("text")
	if "modality" in template and StringName(template.modality) != &"":
		mod = StringName(template.modality)
	ds.modality = mod
	ds.size = template.size
	ds.quality = template.quality
	ds.coverage_tags = template.coverage_tags.duplicate()
	if kind == &"posttrain":
		ds.target_capability = template.target_capability
	return ds

func _gen_id() -> StringName:
	var seq := _next_dataset_seq
	_next_dataset_seq += 1
	return StringName("ds_collected_%04d" % seq)

# ---- save_loaded ID 一致性 ----------------------------------------------

## _next_dataset_seq 是会话内计数器, 不入存档 (与 InfraSystem 的 _next_dc_seq
## 同病): 读档后它停在旧值, 不会跳过档内已用的 ds_collected_NNNN。新采集的
## 数据集就会和档里的撞 ID; find_dataset 只返回首个匹配, 训练时 dataset.lock
## 锁到错的副本 → 报 already_locked。
## 顺序: 先 restore (让 repair 重发的 ID 不再撞), 再 repair 修旧档已有的重复。
func _on_save_loaded() -> void:
	_restore_dataset_seq()
	_repair_dataset_ids()

## 把 _next_dataset_seq 跳到档内现存 ds_collected_NNNN 最大编号之后。
func _restore_dataset_seq() -> void:
	var max_seq: int = 0
	for ds in GameState.datasets:
		var s: String = String(ds.id)
		if s.begins_with("ds_collected_"):
			max_seq = maxi(max_seq, s.trim_prefix("ds_collected_").to_int())
	_next_dataset_seq = maxi(_next_dataset_seq, max_seq + 1)

## 修复已含重复 dataset ID 的旧档。find_dataset 只返回首个匹配, 重复 ID 会
## 静默解析到错的数据集。保留首个出现 (已有 task 锁都解析到它), 其余重发 ID;
## 被重发 ID 的副本上的锁是死锁 (从没被真正驱动过), 一并清掉。
func _repair_dataset_ids() -> void:
	var seen: Dictionary = {}
	for ds in GameState.datasets:
		if not seen.has(ds.id):
			seen[ds.id] = true
			continue
		var old_id: StringName = ds.id
		var new_id: StringName = _gen_id()
		ds.id = new_id
		seen[new_id] = true
		if ds.locked_by_task_id != &"":
			ds.locked_by_task_id = &""
		Log.warn(&"dataset", "save_loaded_duplicate_dataset_id_repaired",
				{old_id = old_id, new_id = new_id})
