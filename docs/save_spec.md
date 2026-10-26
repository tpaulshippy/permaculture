# Save spec — single-slot local JSON autosave (issue #7)

Spec-only. No Godot save/load implementation in this PR (stub API sketch below is
comments-only and MUST NOT be added as a `.gd` file in this change).

## Slot

- Single slot, single file. Canonical Godot path: `user://save.json`.
- No slots UI, no cloud (accounts deferred per issue; Q2 out of scope).
- File content is exactly one JSON object conforming to `data/save_schema.json`
  (`version` = 1). Example: `data/save_example.json`.

## Contents

| Field | Meaning |
|---|---|
| `version` | Schema version (`1`). Loader rejects anything else → fresh seed. |
| `seed` | World-gen seed (non-negative int). Regenerates terrain deterministically. |
| `biome_id` | Biome string (e.g. `sonoran`). Free-form so content packs don't need schema bumps. |
| `month_index` | Turns elapsed (0-based). Autosave increments on every **Next** press. Calendar month = `month_index % 12`. |
| `resources` | `{ money (>=0), water_table (0..100), manhours (>=0) }`. |
| `hexes` | Sparse axial `(q, r)` overrides: `structure_id`, `plant_id`, `growth_stage` 0..5, `condition` (healthy/stressed/dead). Empty terrain is regenerated from `seed`; only placed/mutated hexes need entries. No duplicate `(q, r)`. |
| `saved_at` | Optional informational timestamp. Never used for logic. |

## Behavior

- **Autosave on Next:** after month resolution, write the full object atomically
  (write temp + rename) to `user://save.json`.
- **Load on boot:** if the file exists, parse + validate; on success restore
  seed → terrain, hex states, month, resources.
- **Corrupt-file rule (required):** missing file, unparseable JSON, schema
  violation, or unknown `version` → **discard, log a warning, start a fresh
  seed. Never crash, never half-load.** `tools/validate_save.py` includes a
  self-test proving a garbage payload is rejected.
- **Versioning:** bump `version` on breaking changes; loader keeps only a
  `const SAVE_VERSION := 1` check (strict equality) for v1. Future versions MAY
  add migration, but v1 behavior is reject-and-fresh-seed.

## Validation

```sh
python3 tools/validate_save.py data/save_example.json data/save_schema.json
```

## Stub loader/saver API (comments only — do not implement in this PR)

```gdscript
# const SAVE_PATH := "user://save.json"
# const SAVE_VERSION := 1
# func save_game(month_index, resources, hexes) -> void:  # atomic write tmp+rename
# func load_game() -> Dictionary:  # missing/corrupt/version-mismatch -> {"fresh_seed": true}
```
