# Permaculture

A 3D desert-garden strategy game for **mobile** (Android + iOS) built in **Godot 4**. You shape a 2-acre Sonoran plot where **water flows downhill** — place a house, a well, and plants, then advance month by month, balancing water, money, and labor against the desert's rainfall year.

> MVP status: single Sonoran garden, local play. Accounts, win/lose screens, and extra biomes are future work (see issue #1).

## Demo

All footage is real in-engine capture (Godot 4.7.2, 1280x720) — tap any preview to play the full-quality video.

### Video 1 — Full turn flow: place, press Next, watch the bars move

House → well → ditch → mesquite go down, the gate flips `Next LOCKED` → `Next UNLOCKED`, then **Next** advances Month 1 → 2 (money ≈ $2965, water table ≈ 59%, 107 manhours). Over-planting 24 extra mesquite and pushing 3 more months outruns the well and trips the red water warnings — advisory only, the game continues.

[![Full turn flow: place, press Next, watch the bars move — tap to play](docs/evidence/5/demo_preview.gif)](https://github.com/user-attachments/assets/a7f2fd39-cd22-4732-bfb0-75f5eb41e1c8)

### Video 2 — Placement close-up: orbit while each item goes down

Same terrain, tighter shot: the camera orbits while house, well L1, ditch-berm, and mesquite are placed one by one and the gate readout flips to unlocked. No months advance here — this one is just about aiming at the right ground.

[![Placement close-up: orbit while each item goes down — tap to play](docs/evidence/3/demo_preview.gif)](https://github.com/user-attachments/assets/eea0cbd7-5e29-4d59-a1da-40c31b4a6025)

## How to play

This is a **mobile game** — install the Android APK or iOS build and play with your thumbs. (Desktop runs too: mouse + keys `1–4`, `N`, wheel-zoom.)

1. **Pick a tool:** tap a HUD button — house, well L1, ditch-berm, mesquite.
2. **Place it:** **tap** the terrain. House likes dry/gentle ground, wells want moist low spots, ditches belong mid-slope off the flow channel, mesquite goes anywhere free. **Drag** with one finger to orbit, **pinch** to zoom.
3. **Unlock Next:** you must place a **house + well + one plant** before the **Next turn ▸** button enables.
4. **Take turns:** each Next tap = one month. The house pays 160 manhours/mo (minus upkeep), the well pumps 2500 gal/mo from the groundwater stock, ditches capture +12% of that month's rainfall back into the table, mesquite drinks 250 gal/mo and pays $12/mo from month 12. Rainfall follows the real Tucson typical year (monsoon Jul–Sep, dry Apr–Jun); wind is display-only.
5. **Read the bars:** money / water-table % / manhours update every month, plus a monthly summary line. Red banners (dry well, empty table, negative money) warn but don't stop you — tune your build until the garden holds water through the dry months.

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
