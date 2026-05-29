class_name ProductTypeSpec
extends Resource

## Static template for a product type (chatbot / agent / multimodal_assistant /
## coding_agent). Stored as .tres under resources/data/products/types/.
## Per design/产品系统设计.md §1.

@export var id: StringName  # &"chatbot" / &"agent" / &"multimodal_assistant" / &"coding_agent"
@export var display_name: String = ""
## Capability axis minimums. Each entry e.g. {general: 30, reasoning: 20}.
## Any published model that satisfies all axes makes this type unlockable.
@export var unlock_thresholds: Dictionary = {}
## Required input/output modalities of the bound model (currently informational).
@export var required_modalities: Array[StringName] = []
## Per-subscriber WEEKLY token consumption. UserSystem multiplies this by
## subscribers to compute token_demand contributions (see 用户系统设计.md).
## v7 PR-F (2026-05) renamed from `tokens_per_user_per_month` — value is
## unchanged because v6 already reinterpreted the old name as per-week under
## the 1 turn = 1 week convention. Legacy field retained for back-compat.
@export var tokens_per_user_per_week: int = 0
@export var tokens_per_user_per_month: int = 0  # legacy alias; preferred field above
## Default WEEKLY subscription price (¥). UI suggests this when player creates a product.
@export var default_subscription_price: int = 0
## v7 PR-F: WEEKLY guidance price (¥/week). UserSystem price elasticity uses
## `subscription_price / subscription_price_guidance` as the ratio r.
## Defaults to 0; UserSystem treats 0 as "no elasticity pressure" (rate = 0).
@export var subscription_price_guidance: int = 0
## v10 §5.2bis — capability gate. UserSystem applies a flat weekly subscriber
## penalty when the bound model's `capability_penalty_axis` value is below a
## tier threshold. `&""` axis = no gate. Each tier is {below: float, rate: float};
## the most negative applicable tier wins. E.g. chatbot:
##   axis = &"general", tiers = [{below: 50, rate: -0.05}, {below: 70, rate: -0.03}]
@export var capability_penalty_axis: StringName = &""
@export var capability_penalty_tiers: Array = []
## Lead specialty that grants the §6.2 quality bonus. Empty = no bonus.
@export var lead_specialty_bonus: StringName = &""
## Tech node prereq from the application tree. &"" means no node required.
## Checked via tech.is_unlocked(tree=&"application", node_id=...).
@export var application_node_required: StringName = &""
## Hard subscriber pool cap for products of this type. `0` = no cap (api uses
## this — its `subscribers` is a demand-pool unit, not a real-user count).
## ProductSystem clamps `Product.subscribers` to this on every write.
@export var max_subscribers: int = 0
## Hard weekly revenue ceiling for products of this type (TAM cap). `0` = no
## cap. MonetizationSystem clamps each product's weekly revenue to this (see
## design/营收系统设计.md §5.1bis). Currently only api.tres sets it (1e10), so a
## single API product can't grow its revenue without bound; total API revenue
## still scales with the number of published models (per-product granularity).
@export var revenue_cap_per_week: int = 0

func to_dict() -> Dictionary:
	var thresholds: Dictionary = {}
	for k in unlock_thresholds.keys():
		thresholds[String(k)] = float(unlock_thresholds[k])
	var mods: Array = []
	for m in required_modalities:
		mods.append(String(m))
	return {
		id = String(id),
		display_name = display_name,
		unlock_thresholds = thresholds,
		required_modalities = mods,
		tokens_per_user_per_week = tokens_per_user_per_week,
		tokens_per_user_per_month = tokens_per_user_per_month,
		default_subscription_price = default_subscription_price,
		subscription_price_guidance = subscription_price_guidance,
		capability_penalty_axis = String(capability_penalty_axis),
		capability_penalty_tiers = capability_penalty_tiers.duplicate(true),
		lead_specialty_bonus = String(lead_specialty_bonus),
		application_node_required = String(application_node_required),
		max_subscribers = max_subscribers,
		revenue_cap_per_week = revenue_cap_per_week,
	}

static func from_dict(d: Dictionary) -> ProductTypeSpec:
	var s := ProductTypeSpec.new()
	s.id = StringName(d.get("id", ""))
	s.display_name = String(d.get("display_name", ""))
	var thresholds: Dictionary = {}
	for k in (d.get("unlock_thresholds", {}) as Dictionary).keys():
		thresholds[StringName(k)] = float(d.unlock_thresholds[k])
	s.unlock_thresholds = thresholds
	var mods: Array[StringName] = []
	for m in d.get("required_modalities", []):
		mods.append(StringName(m))
	s.required_modalities = mods
	# v7 PR-F: prefer per_week; fall back to legacy per_month (same value, just rename).
	s.tokens_per_user_per_week = int(d.get("tokens_per_user_per_week",
			d.get("tokens_per_user_per_month", 0)))
	s.tokens_per_user_per_month = int(d.get("tokens_per_user_per_month", s.tokens_per_user_per_week))
	s.default_subscription_price = int(d.get("default_subscription_price", 0))
	s.subscription_price_guidance = int(d.get("subscription_price_guidance", 0))
	s.capability_penalty_axis = StringName(d.get("capability_penalty_axis", ""))
	var tiers_in = d.get("capability_penalty_tiers", [])
	s.capability_penalty_tiers = (tiers_in as Array).duplicate(true) if tiers_in is Array else []
	s.lead_specialty_bonus = StringName(d.get("lead_specialty_bonus", ""))
	s.application_node_required = StringName(d.get("application_node_required", ""))
	s.max_subscribers = int(d.get("max_subscribers", 0))
	s.revenue_cap_per_week = int(d.get("revenue_cap_per_week", 0))
	return s

## Resolves the effective per-week token consumption. Prefers the new field;
## falls back to the legacy `_per_month` value (which v6 already reinterpreted
## as weekly under "1 turn = 1 week").
func tokens_per_week() -> int:
	if tokens_per_user_per_week > 0:
		return tokens_per_user_per_week
	return tokens_per_user_per_month
