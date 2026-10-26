#!/usr/bin/env python3
"""Validate a permaculture single-slot autosave against data/save_schema.json.

Stdlib-only structural validator (mirrors the JSON Schema by hand so it runs
with zero dependencies). If the `jsonschema` package is installed it is ALSO
used for a strict schema pass; otherwise the manual pass is authoritative.

Usage:
    python3 tools/validate_save.py [save.json] [schema.json]
Defaults:
    data/save_example.json  data/save_schema.json

Exit 0 on PASS, 1 on FAIL.
"""
from __future__ import annotations

import json
import math
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DEFAULT_SAVE = REPO / "data" / "save_example.json"
DEFAULT_SCHEMA = REPO / "data" / "save_schema.json"

MAX_SEED = 2**53 - 1  # largest int exactly representable in double-based JSON parsers

CONDITIONS = {"healthy", "stressed", "dead", None}


def is_finite_number(x: object) -> bool:
    """True for JSON numbers that are exactly representable: ints (never
    bool) or finite floats. `math.isfinite` is only ever called on floats so
    arbitrarily large ints short-circuit safely."""
    if isinstance(x, bool):
        return False
    if isinstance(x, int):
        return True
    return isinstance(x, float) and math.isfinite(x)

# ISO-8601 UTC/offset datetime, e.g. 2026-10-25T00:00:00Z or +00:00 with optional fraction.
SAVED_AT_RE = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$")


def fail(msg: str, errors: list[str]) -> None:
    errors.append(msg)


def check(save: dict, errors: list[str]) -> int:
    """Manual structural check. Returns number of hexes checked."""
    if not isinstance(save, dict):
        fail("top level must be an object", errors)
        return 0

    allowed_top = {"version", "seed", "biome_id", "month_index", "resources", "hexes", "saved_at"}
    for k in save:
        if k not in allowed_top:
            fail(f"unknown top-level property: {k!r}", errors)

    for field in ("version", "seed", "biome_id", "month_index", "resources", "hexes"):
        if field not in save:
            fail(f"missing required field: {field}", errors)

    # bool is a subclass of int and True == 1, so reject bools explicitly.
    if isinstance(save.get("version"), bool) or save.get("version") != 1:
        fail(f"version must be 1, got {save.get('version')!r}", errors)

    seed = save.get("seed")
    if not (isinstance(seed, int) and not isinstance(seed, bool) and 0 <= seed <= MAX_SEED):
        fail(f"seed must be a non-negative int <= 2^53-1 ({MAX_SEED}), got {seed!r}", errors)

    biome = save.get("biome_id")
    if not (isinstance(biome, str) and len(biome) >= 1):
        fail(f"biome_id must be a non-empty string, got {biome!r}", errors)

    mi = save.get("month_index")
    if not (isinstance(mi, int) and not isinstance(mi, bool) and mi >= 0):
        fail(f"month_index must be a non-negative int, got {mi!r}", errors)

    res = save.get("resources")
    if isinstance(res, dict):
        for f in ("money", "water_table", "manhours"):
            if f not in res:
                fail(f"resources missing required field: {f}", errors)
        m = res.get("money")
        if "money" in res and not (is_finite_number(m) and m >= 0):
            fail(f"resources.money must be a finite number >= 0, got {m!r}", errors)
        w = res.get("water_table")
        if "water_table" in res and not (is_finite_number(w) and 0 <= w <= 100):
            fail(f"resources.water_table must be a finite number in 0..100, got {w!r}", errors)
        h = res.get("manhours")
        if "manhours" in res and not (is_finite_number(h) and h >= 0):
            fail(f"resources.manhours must be a finite number >= 0, got {h!r}", errors)
        for k in res:
            if k not in ("money", "water_table", "manhours"):
                fail(f"unknown resources property: {k!r}", errors)
    else:
        fail(f"resources must be an object, got {res!r}", errors)

    hexes = save.get("hexes")
    n = 0
    if isinstance(hexes, list):
        seen: set[tuple[int, int]] = set()
        for i, hx in enumerate(hexes):
            n += 1
            where = f"hexes[{i}]"
            if not isinstance(hx, dict):
                fail(f"{where} must be an object", errors)
                continue
            for k in hx:
                if k not in ("q", "r", "structure_id", "plant_id", "growth_stage", "condition"):
                    fail(f"{where} unknown property: {k!r}", errors)
            q, r = hx.get("q"), hx.get("r")
            if not (isinstance(q, int) and not isinstance(q, bool)):
                fail(f"{where}.q must be int, got {q!r}", errors)
            if not (isinstance(r, int) and not isinstance(r, bool)):
                fail(f"{where}.r must be int, got {r!r}", errors)
            if isinstance(q, int) and isinstance(r, int) and not isinstance(q, bool) and not isinstance(r, bool):
                if (q, r) in seen:
                    fail(f"{where} duplicate axial coord (q={q}, r={r})", errors)
                seen.add((q, r))
            for f in ("structure_id", "plant_id"):
                v = hx.get(f)
                if v is not None and not (isinstance(v, str) and len(v) >= 1):
                    fail(f"{where}.{f} must be string or null, got {v!r}", errors)
            g = hx.get("growth_stage")
            if g is not None and not (isinstance(g, int) and not isinstance(g, bool) and 0 <= g <= 5):
                fail(f"{where}.growth_stage must be int 0..5 or null, got {g!r}", errors)
            c = hx.get("condition", None)
            # Type-guard before membership: unhashable values (list/dict) must
            # fail cleanly as schema violations, not raise TypeError.
            if not (c is None or (isinstance(c, str) and c in CONDITIONS)):
                fail(f"{where}.condition must be one of healthy/stressed/dead/null, got {c!r}", errors)
    else:
        fail(f"hexes must be an array, got {hexes!r}", errors)

    if "saved_at" in save:
        sa = save["saved_at"]
        if not (isinstance(sa, str) and SAVED_AT_RE.match(sa)):
            fail(f"saved_at must be an ISO-8601 datetime when present, got {sa!r}", errors)

    return n


def try_jsonschema(save: dict, schema: dict, schema_path: Path, errors: list[str]) -> str:
    try:
        import jsonschema  # type: ignore
    except ImportError:
        if schema_path.resolve() != DEFAULT_SCHEMA.resolve():
            fail(
                f"custom schema {schema_path} cannot be enforced without the "
                "'jsonschema' package installed (manual check covers v1 only); "
                "install jsonschema or validate against data/save_schema.json",
                errors,
            )
            return "jsonschema strict pass: FAIL (custom schema needs jsonschema installed)"
        return "jsonschema library not installed; manual stdlib check is authoritative (SKIPPED strict pass)"
    try:
        jsonschema.validate(instance=save, schema=schema)
    except Exception as e:  # jsonschema.ValidationError
        fail(f"jsonschema strict pass failed: {e}", errors)
        return "jsonschema strict pass: FAIL"
    return "jsonschema strict pass: PASS"


def main(argv: list[str]) -> int:
    save_path = Path(argv[1]) if len(argv) > 1 else DEFAULT_SAVE
    schema_path = Path(argv[2]) if len(argv) > 2 else DEFAULT_SCHEMA
    print(f"save:   {save_path}")
    print(f"schema: {schema_path}")

    try:
        save = json.loads(save_path.read_text())
    except Exception as e:
        print(f"FAIL: could not parse save JSON: {e}")
        print("rule: corrupt/unparseable file -> loader MUST discard and start a fresh seed, no crash.")
        return 1
    try:
        schema = json.loads(schema_path.read_text())
    except Exception as e:
        print(f"FAIL: could not parse schema JSON: {e}")
        return 1

    errors: list[str] = []
    n = check(save, errors)
    strict = try_jsonschema(save, schema, schema_path, errors)

    summary = save if isinstance(save, dict) else {}
    print(f"version={summary.get('version')} seed={summary.get('seed')} "
          f"biome={summary.get('biome_id')} month_index={summary.get('month_index')} hexes={n}")
    print(strict)

    # Corrupt-file rule self-test: a garbage payload must FAIL validation
    # (proving the loader can detect it and fall back to a fresh seed).
    corrupt: dict = {"version": 999, "seed": -1}
    c_errors: list[str] = []
    check(corrupt, c_errors)
    if c_errors and any("version" in e for e in c_errors):
        print(f"corrupt-file self-test: correctly REJECTED ({len(c_errors)} errors, e.g. {c_errors[0]})")
    else:
        fail("corrupt-file self-test: garbage payload was ACCEPTED or version rule missing (must be rejected)", errors)

    if errors:
        print(f"FAIL: {len(errors)} error(s):")
        for e in errors[:20]:
            print(f"  - {e}")
        return 1
    print("PASS: save validates against schema (manual check + corrupt-rejection self-test).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
