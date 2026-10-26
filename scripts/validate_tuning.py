#!/usr/bin/env python3
"""Validate data/tuning.json for issue #4.

Checks: JSON parses, 4 required item ids present, required fields/types,
per-item rules (house/well/ditch/mesquite), and balance-check arithmetic
against meta.sim_baseline.balance_check_monthly.
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PATH = ROOT / "data" / "tuning.json"

EXPECTED_IDS = ["house", "well_l1", "ditch_berm", "mesquite"]
# field -> (unit label, python type)
REQUIRED_ALL = {
    "id": ("-", str),
    "name": ("-", str),
    "category": ("-", str),
    "cost_usd": ("$", (int, float)),
    "build_manhours": ("mh", (int, float)),
    "upkeep_manhours_per_mo": ("mh/mo", (int, float)),
    "water_gal_per_mo": ("gal/mo", (int, float)),
}

errors = []


def fail(msg):
    errors.append(msg)


def main():
    try:
        raw = PATH.read_text()
    except FileNotFoundError:
        print(f"FAIL: missing file {PATH}")
        return 1
    try:
        data = json.loads(raw)
    except json.JSONDecodeError as e:
        print(f"FAIL: invalid JSON: {e}")
        return 1
    print(f"OK: parses ({len(raw)} bytes)")

    for key in ("meta", "items"):
        if key not in data:
            fail(f"missing top-level key '{key}'")
    if errors:
        return report()

    items = data["items"]
    by_id = {i.get("id"): i for i in items if isinstance(i, dict)}
    if sorted(by_id) != sorted(EXPECTED_IDS):
        fail(f"item ids {sorted(by_id)} != expected {sorted(EXPECTED_IDS)}")
    print(f"OK: 4 items {sorted(by_id)}")

    for item_id in EXPECTED_IDS:
        it = by_id.get(item_id)
        if not isinstance(it, dict):
            continue
        for field, (unit, typ) in REQUIRED_ALL.items():
            if field not in it:
                fail(f"{item_id}: missing required field '{field}' [{unit}]")
            elif not isinstance(it[field], typ) or isinstance(it[field], bool):
                fail(f"{item_id}.{field} must be numeric/str [{unit}], got {it[field]!r}")

    # per-item rules
    h, w, d, m = (by_id.get(k, {}) for k in EXPECTED_IDS)
    if h.get("provides_manhours_per_mo") != 160:
        fail("house.provides_manhours_per_mo must be 160 (mh/mo)")
    if w.get("pump_gal_per_mo") != 2500:
        fail("well_l1.pump_gal_per_mo must be 2500 (gal/mo)")
    if d.get("retention_percent") != 12:
        fail("ditch_berm.retention_percent must be 12 (%)")
    if m.get("water_need_gal_per_mo") != 250 or m.get("yield_usd_per_mo") != 12:
        fail("mesquite needs water_need_gal_per_mo=250 (gal/mo) and yield_usd_per_mo=12 ($/mo)")
    for k in EXPECTED_IDS:
        if by_id.get(k, {}).get("cost_usd", -1) < 0:
            fail(f"{k}.cost_usd must be >= 0 ($)")
    print("OK: per-item rules (house mh/mo, well pump, ditch retention, mesquite need/yield)")

    # balance arithmetic: 1 house + 1 well + 2 ditch + 4 mesquite
    try:
        money = h["cost_usd"] + w["cost_usd"] + 2 * d["cost_usd"] + 4 * m["cost_usd"]
        labor = h["build_manhours"] + w["build_manhours"] + 2 * d["build_manhours"] + 4 * m["build_manhours"]
        up_mh = h["upkeep_manhours_per_mo"] + w["upkeep_manhours_per_mo"] + 2 * d["upkeep_manhours_per_mo"] + 4 * m["upkeep_manhours_per_mo"]
        free_mh = h["provides_manhours_per_mo"] - up_mh
        bc = data["meta"]["sim_baseline"]["balance_check_monthly"]
        assert money == bc["money_upfront_usd"] == 7460, f"money {money}"
        assert labor == bc["labor_upfront_mh"] == 96, f"labor {labor}"
        assert up_mh == bc["upkeep_mh_per_mo"] == 20, f"upkeep {up_mh}"
        assert free_mh == bc["free_mh_per_mo"] == 140, f"free {free_mh}"
        print(f"OK: balance 1+1+2+4 -> ${money}, {labor}mh build, {up_mh}mh/mo upkeep, {free_mh}mh/mo free")
    except (KeyError, TypeError, AssertionError) as e:
        fail(f"balance arithmetic mismatch: {e}")

    return report()


def report():
    if errors:
        print("FAIL:")
        for e in errors:
            print(f"  - {e}")
        return 1
    print("PASS: data/tuning.json valid (units $, mh, gal/mo, % consistent with water/money/manhours/rain sim)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
