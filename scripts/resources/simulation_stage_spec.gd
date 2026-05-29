class_name SimulationStageSpec
extends Resource

## One stage of the universe-simulation capstone ladder (慈善三期). Stored at
## resources/data/simulation/<id>.tres, loaded by SimulationSystem.
## Per design/宇宙模拟工程设计.md §2.
##
## Stages unlock in `order`; each raises three gates: the donated datacenter's
## training compute (min_train_tflops), computation time (weeks), and donated
## funding (cost).

@export var id: StringName
## Ladder position (0 = first / 气象, 4 = last / 宇宙).
@export var order: int = 0
@export var display_name: String = ""
@export var description: String = ""

## One-shot funding donated to start this stage (tax-deductible).
@export var cost: int = 0
## Weeks the simulation task runs.
@export var weeks: int = 1
## Start gate: the single self-owned, idle datacenter the player donates must have
## train_tflops ≥ this (real derived training compute — see 基础设施系统设计.md §1.5).
## Calibrated so each stage needs a datacenter of the matching facility tier filled
## with the best GPU; the universe stage needs the 100M-card planet datacenter.
@export var min_train_tflops: float = 0.0
