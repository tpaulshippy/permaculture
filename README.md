# Permaculture

A 3D desert-garden strategy game in **Godot 4**. You shape a 2-acre Sonoran plot where **water flows downhill** — place a house, a well, and plants, then advance month by month, balancing water, money, and labor against the desert's rainfall year.

> MVP status: single Sonoran garden, local play. Accounts, win/lose screens, and extra biomes are future work (see issue #1).

## Demo

Watch a full turn play out — placement, Next gating, live bars, and the water warning path. Real in-engine footage (Godot 4.7.2, 1280x720):

[![Full turn: placement, Next gating, live bars, water warnings — click to play full video](docs/evidence/5/demo_preview.gif)](https://github.com/user-attachments/assets/a7f2fd39-cd22-4732-bfb0-75f5eb41e1c8)

*(Tap the preview to play the full-quality video. Same file in-repo: [docs/evidence/5/demo.mp4](docs/evidence/5/demo.mp4). Stills: [locked](docs/evidence/5/demo_frame_locked.png) · [unlocked](docs/evidence/5/demo_frame_unlocked.png) · [warning](docs/evidence/5/demo_frame_warned.png).)*

[![Placement close-up: orbit while house, well, ditch, mesquite go down — click to play](docs/evidence/3/demo_preview.gif)](https://github.com/user-attachments/assets/eea0cbd7-5e29-4d59-a1da-40c31b4a6025)

What the demo shows: the camera orbits the seeded Sonoran terrain while house → well L1 → ditch-berm → mesquite are placed (the HUD gate flips `Next LOCKED` → `Next UNLOCKED` once house + well + plant exist). Pressing **Next** advances Month 1 → 2 and the bars update (money ≈ $2965, water table ≈ 59%, 107 manhours). Planting 24 extra mesquite and hitting Next 3 more times outruns the well, tripping the red irrigation/water warnings — which advise but never block (MVP has no game-over yet).

## How to play

1. **Run it:** `godot --path .` (Godot 4.x). Scripted demo: `godot --path . -- --demo`.
2. **Pick a tool:** keys **1–4** (or HUD buttons) — `1` house, `2` well L1, `3` ditch-berm, `4` mesquite.
3. **Place it:** left-**click** the terrain. House likes dry/gentle ground, wells want moist low spots, ditches belong mid-slope off the flow channel, mesquite goes anywhere free. **Drag** to orbit, **wheel** to zoom.
4. **Unlock Next:** you must place a **house + well + one plant** before the **Next** button (or **N** key) enables.
5. **Take turns:** each Next press = one month. The house pays 160 manhours/mo (minus upkeep), the well pumps 2500 gal/mo from the groundwater stock, ditches capture +12% of that month's rainfall back into the table, mesquite drinks 250 gal/mo and pays $12/mo from month 12. Rainfall follows the real Tucson typical year (monsoon Jul–Sep, dry Apr–Jun); wind is display-only.
6. **Read the bars:** money / water-table % / manhours update every month, plus a monthly summary line. Red banners (dry well, empty table, negative money) warn but don't stop you — tune your build until the garden holds water through the dry months.

## Repo map

- `scripts/terrain_water.gd` — seeded heightfield + D8 downhill flow + per-hex moisture
- `scripts/hex_grid.gd` — 20x20 gameplay overlay, placement rules, Next gating
- `scripts/turn_sim.gd` — monthly economy (water/money/manhours)
- `scripts/main.gd` — camera, raycast placement, HUD, Next wizard
- `data/` — `tuning.json` (costs), `sonoran_rainfall.json`, `mesquite.json`, save schema + example
- `tests/` — headless logic tests (`test_terrain`, `test_hex`, `test_hud`)
- `docs/evidence/` — real captures per issue (`2/` terrain, `3/` hex, `5/` HUD, `8/` Android, `9/` iOS)
- `export_presets.cfg` — Android APK + iOS IPA/Xcode presets (single shared codebase)

```sh
godot --headless --path . --script res://tests/test_terrain.gd
godot --headless --path . --script res://tests/test_hex.gd
godot --headless --path . --script res://tests/test_hud.gd
python3 scripts/validate_tuning.py && python3 scripts/validate_sonoran.py
python3 tools/validate_save.py && python3 tools/validate_android_preset.py
```
