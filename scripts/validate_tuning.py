#!/usr/bin/env python3
"""Validate data/tuning.json for issue #4.

Checks: JSON parses, expected item ids present exactly once, required
fields/types (all units in REQUIRED_ALL), per-item rules (house/well/
ditch/mesquite), nonnegative cost/labor ranges, opening labor-grant
feasibility, and balance-check arithmetic (upfront money/labor, monthly
labor, monthly money pre-yield + mature, monthly water surplus) against
meta.sim_baseline.
"""
import json
import math
import sys
from collections import Counter
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
    "upkeep_usd_per_mo": ("$/mo", (int, float)),
    "water_gal_per_mo": ("gal/mo", (int, float)),
}

errors = []


def fail(msg):
    errors.append(msg)


def is_num(x):
    return isinstance(x, (int, float)) and not isinstance(x, bool) and math.isfinite(x)


def check_equal(label, actual, expected):
    if actual != expected:
        fail(f"{label} mismatch: got {actual!r}, expected {expected!r}")


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
        if not isinstance(data, dict) or key not in data:
            fail(f"missing top-level key '{key}'")
    if errors:
        return report()

    items = data["items"]
    if not isinstance(items, list):
        fail("items must be a list")
        return report()

    # Reject duplicate IDs and count mismatches before collapsing into a map.
    # (Count only string IDs: unhashable IDs are reported, not counted.)
    ids = [i.get("id") if isinstance(i, dict) else None for i in items]
    for bad in ids:
        if not isinstance(bad, str):
            fail(f"item id must be a string, got {bad!r}")
    dupes = sorted(k for k, n in Counter(i for i in ids if isinstance(i, str)).items() if n > 1)
    if dupes:
        fail(f"duplicate item ids: {dupes}")
    if len(items) != len(EXPECTED_IDS):
        fail(f"item count {len(items)} != expected {len(EXPECTED_IDS)}")
    if sorted(i for i in ids if isinstance(i, str)) != sorted(EXPECTED_IDS):
        fail(f"item ids {sorted(i for i in ids if isinstance(i, str))} != expected {sorted(EXPECTED_IDS)}")
    if errors:
        print(f"OK: 4 items check attempted, errors found")
        return report()
    by_id = {i["id"]: i for i in items if isinstance(i, dict)}
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
    # Nonnegative ranges per item (type-guarded so malformed types FAIL cleanly).
    for k in EXPECTED_IDS:
        it = by_id.get(k, {})
        for field in ("cost_usd", "build_manhours", "upkeep_manhours_per_mo",
                      "upkeep_usd_per_mo", "water_gal_per_mo"):
            v = it.get(field)
            if field in it and field != "water_gal_per_mo":
                if not is_num(v):
                    fail(f"{k}.{field} must be numeric, got {v!r}")
                elif v < 0:
                    fail(f"{k}.{field} must be >= 0, got {v!r}")
    print("OK: per-item rules (house mh/mo, well pump, ditch retention, mesquite need/yield; nonnegative cost/labor)")

    # Baseline containers must be mappings before any field access below.
    base = data["meta"].get("sim_baseline") if isinstance(data.get("meta"), dict) else None
    if not isinstance(base, dict):
        fail("meta.sim_baseline must be an object")
        return report()
    bc = base.get("balance_check_monthly")
    if not isinstance(bc, dict):
        fail("meta.sim_baseline.balance_check_monthly must be an object")
        return report()

    # opening labor-grant feasibility: the grant must cover the first build.
    grant = base.get("starting_manhours_mh")
    if not is_num(grant):
        fail(f"sim_baseline.starting_manhours_mh must be a finite number, got {grant!r}")
    elif grant < h.get("build_manhours", float("inf")):
        fail(f"starting grant {grant} mh cannot cover first house build {h.get('build_manhours')} mh")
    else:
        print(f"OK: starting grant {grant} mh covers house build {h.get('build_manhours')} mh")

    # balance arithmetic: 1 house + 1 well + 2 ditch + 4 mesquite
    # (explicit conditionals: must also hold under `python -O`).
    try:
        money = h["cost_usd"] + w["cost_usd"] + 2 * d["cost_usd"] + 4 * m["cost_usd"]
        labor = h["build_manhours"] + w["build_manhours"] + 2 * d["build_manhours"] + 4 * m["build_manhours"]
        up_mh = h["upkeep_manhours_per_mo"] + w["upkeep_manhours_per_mo"] + 2 * d["upkeep_manhours_per_mo"] + 4 * m["upkeep_manhours_per_mo"]
        free_mh = h["provides_manhours_per_mo"] - up_mh
        up_usd_pre = h["upkeep_usd_per_mo"] + w["upkeep_usd_per_mo"] + 2 * d["upkeep_usd_per_mo"]
        money_pre = -(up_usd_pre)  # trees pay no $ upkeep pre-yield
        money_mature = money_pre + 4 * m["yield_usd_per_mo"]
        rain_ref = base["rainfall_reference_gal_per_mo"]
        base_cap = base["base_rain_capture_gal_per_mo"]
        water = w["pump_gal_per_mo"] + base_cap + 2 * d["water_gal_per_mo"] + 4 * m["water_gal_per_mo"]
        check_equal("money_upfront_usd", money, bc.get("money_upfront_usd"))
        check_equal("money_upfront_usd vs 7460", money, 7460)
        check_equal("labor_upfront_mh", labor, bc.get("labor_upfront_mh"))
        check_equal("labor_upfront_mh vs 96", labor, 96)
        check_equal("upkeep_mh_per_mo", up_mh, bc.get("upkeep_mh_per_mo"))
        check_equal("free_mh_per_mo", free_mh, bc.get("free_mh_per_mo"))
        check_equal("provided_mh_per_mo", h.get("provides_manhours_per_mo"), bc.get("provided_mh_per_mo"))
        check_equal("money_per_mo_usd_pre_yield", money_pre, bc.get("money_per_mo_usd_pre_yield"))
        check_equal("money_per_mo_usd_mature", money_mature, bc.get("money_per_mo_usd_mature"))
        if not is_num(bc.get("water_per_mo_gal")):
            fail(f"balance_check_monthly.water_per_mo_gal must be a finite number (gal/mo), got {bc.get('water_per_mo_gal')!r}")
        else:
            check_equal("water_per_mo_gal", water, bc.get("water_per_mo_gal"))
        check_equal("rainfall_reference_gal_per_mo vs 1000", rain_ref, 1000)
        print(f"OK: balance 1+1+2+4 -> ${money}, {labor}mh build, {up_mh}mh/mo upkeep, {free_mh}mh/mo free, "
              f"{money_pre}/{money_mature}$/mo pre/mature, {water:+}gal/mo water")
    except (KeyError, TypeError) as e:
        fail(f"balance arithmetic mismatch: {e}")

    return report()


def report():
    if errors:
        print("FAIL:")
        for e in errors:
            print(f"  - {e}")
        return 1
    print("PASS: data/tuning.json valid (ids/fields/types, per-item rules, nonnegative ranges, "
          "starting-grant feasibility, upfront/labor/monthly-money/monthly-water balance)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
