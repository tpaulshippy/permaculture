class_name Tutorial
extends RefCounted
## Step-by-step first-time walkthrough (issue: in-app tutorial).
##
## Pure logic, no UI dependency so it stays headless-testable
## (tests/test_tutorial.gd). The driver (scripts/main.gd) renders the panel,
## feeds live counts from hex_grid/turn_sim, and advances on gameplay.
##
## Language rule, enforced by test: every step body is plain words a kid can
## follow (<= 200 chars, no jargon from JARGON list).

const JARGON := ["groundwater", "irrigation", "erosion", "topography",
	"permaculture", "manhours", "upkeep", "hydration", "desalination"]

# require: "continue" (tap the tutorial Next button), "house", "well_l1",
# "ditch_berm", "mesquite", "month" (advance at least one month from tutorial
# start), "finish" (tap Play).
const STEPS := [
	{
		"id": "land",
		"title": "Your desert land",
		"body": "This is your land. When rain falls, water runs downhill. Low spots stay wet. High spots stay dry.",
		"require": "continue",
	},
	{
		"id": "house",
		"title": "Build a house",
		"body": "First, build a house. A house gives you worker hours. Every farm job spends hours. Tap House, then tap flat dry ground.",
		"require": "house",
	},
	{
		"id": "well",
		"title": "Dig a well",
		"body": "Next, dig a well. A well drinks hidden water under the ground. Tap Well, then tap a low wet spot.",
		"require": "well_l1",
	},
	{
		"id": "ditch",
		"title": "Dig a ditch",
		"body": "Now dig a ditch. A ditch catches rain and saves it in the ground. Tap Ditch, then tap a slope.",
		"require": "ditch_berm",
	},
	{
		"id": "tree",
		"title": "Plant a tree",
		"body": "Now plant a tree. Trees drink lots of water, but grown trees pay you money each month. Tap Mesquite, then tap free ground.",
		"require": "mesquite",
	},
	{
		"id": "month",
		"title": "Grow a month",
		"body": "Time moves when you press Next Turn. Each press is one month. Watch your water, money, and hours move.",
		"require": "month",
	},
	{
		"id": "warn",
		"title": "Red notes are tips",
		"body": "Red notes are tips, not game over. If water runs low, add ditches or plant less. Keep water in the ground and you win.",
		"require": "finish",
	},
]


static func step_count() -> int:
	return STEPS.size()


static func step_at(i: int) -> Dictionary:
	return STEPS[clampi(i, 0, STEPS.size() - 1)]


## state: {"house": int, "well_l1": int, "ditch_berm": int, "mesquite": int,
##          "months": int} — counts from hex_grid, months advanced since start.
static func is_satisfied(require: String, state: Dictionary) -> bool:
	match require:
		"continue":
			return true
		"finish":
			return true
		"house":
			return int(state.get("house", 0)) >= 1
		"well_l1":
			return int(state.get("well_l1", 0)) >= 1
		"ditch_berm":
			return int(state.get("ditch_berm", 0)) >= 1
		"mesquite":
			return int(state.get("mesquite", 0)) >= 1
		"month":
			return int(state.get("months", 0)) >= 1
	return false
