class_name StaffRoleSpec
extends Resource

## Static template for an aggregate staff role.
## Stored under resources/data/hiring/staff_salaries/*.tres.
## Per design/招聘系统设计.md §7 + design/平衡参数.md §HiringSystem.
## Assembled into HiringSystem.SALARY_PER_ROLE at _ready.

@export var id: StringName              # &"ml_eng" / &"infra_eng" / &"data_eng" / &"marketing" / &"ops"
@export var display_name: String = ""
@export var weekly_salary: int = 0       # ¥/week (1 turn = 1 week)
