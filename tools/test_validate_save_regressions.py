#!/usr/bin/env python3
"""Regression tests for cubic PR #12 findings (spec-only save schema).

Covers: bool version, Infinity numerics, unhashable condition, non-dict
summary path, seed > 2^53-1, bad saved_at, duplicate (q, r), custom-schema
fallback without jsonschema, renderer title per-file.

Uses explicit checks (no bare `assert`: `python -O` strips asserts).
Run: python3 tools/test_validate_save_regressions.py
Exit 0 on PASS, 1 on FAIL.
"""
from __future__ import annotations

import copy
import json
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "tools"))
import validate_save as v  # noqa: E402

BASE = json.loads((REPO / "data" / "save_example.json").read_text())


def need(cond: bool, msg: str) -> None:
    if not cond:
        raise AssertionError(msg)


def expect_reject(name: str, mutate) -> None:
    save = copy.deepcopy(BASE)
    mutate(save)
    errs: list[str] = []
    v.check(save, errs)
    need(bool(errs), f"{name}: payload was ACCEPTED, must be rejected")
    print(f"ok - {name}: rejected ({errs[0][:90]})")


def expect_accept(name: str, mutate=None) -> None:
    save = copy.deepcopy(BASE)
    if mutate:
        mutate(save)
    errs: list[str] = []
    v.check(save, errs)
    need(not errs, f"{name}: wrongly rejected: {errs[:3]}")
    print(f"ok - {name}: accepted")


def block_jsonschema():
    """Force the ImportError fallback path deterministically, whether or
    not the `jsonschema` package is installed. Returns a restore function."""
    prev = sys.modules.get("jsonschema")
    sys.modules["jsonschema"] = None  # type: ignore[assignment]

    def restore() -> None:
        if prev is None:
            sys.modules.pop("jsonschema", None)
        else:
            sys.modules["jsonschema"] = prev

    return restore


failures = 0
skipped: list[str] = []
try:
    expect_reject("version=true rejected", lambda s: s.update(version=True))
    expect_reject("version='1' rejected", lambda s: s.update(version="1"))
    expect_accept("version=1 accepted", None)

    for field in ("money", "manhours", "water_table"):
        s = copy.deepcopy(BASE)
        s["resources"][field] = float("inf")
        errs = []
        v.check(s, errs)
        need(bool(errs), f"{field}=Infinity accepted")
        print(f"ok - {field}=Infinity rejected ({errs[0][:70]})")

    # Arbitrarily large ints must reject-or-accept cleanly, never raise.
    s = copy.deepcopy(BASE)
    s["resources"]["money"] = 10**1000
    errs = []
    v.check(s, errs)  # must not raise
    print(f"ok - money=10**1000 handled without crash ({len(errs)} errors)")

    # Unhashable condition must be a clean violation, not TypeError.
    for bad in (["healthy"], {"x": 1}):
        s = copy.deepcopy(BASE)
        s["hexes"][0]["condition"] = bad
        errs = []
        try:
            v.check(s, errs)
        except TypeError as e:
            raise AssertionError(f"condition {bad!r} raised TypeError: {e}")
        need(bool(errs), f"condition {bad!r} accepted")
        print(f"ok - condition={bad!r} rejected cleanly ({errs[0][:70]})")

    # Non-dict summary path: main() must not traceback on JSON array.
    with tempfile.TemporaryDirectory() as td:
        arr = Path(td) / "arr.json"
        arr.write_text("[1, 2, 3]")
        rc = v.main(["validate_save.py", str(arr), str(REPO / "data" / "save_schema.json")])
        need(rc == 1, f"array save main() rc={rc}, want 1")
    print("ok - non-dict save exits 1 without traceback")

    expect_reject("seed > 2^53-1 rejected", lambda s: s.update(seed=2**53))
    expect_accept("seed == 2^53-1 accepted", lambda s: s.update(seed=2**53 - 1))
    expect_reject("saved_at garbage rejected", lambda s: s.update(saved_at="not-a-date"))
    expect_reject("saved_at empty rejected", lambda s: s.update(saved_at=""))
    expect_reject("saved_at explicit null rejected", lambda s: s.update(saved_at=None))
    expect_accept("saved_at ISO-8601 accepted", None)
    expect_accept(
        "saved_at fractional seconds accepted",
        lambda s: s.update(saved_at="2026-10-25T00:00:00.123Z"),
    )

    dup = copy.deepcopy(BASE)
    dup["hexes"].append(dict(dup["hexes"][0]))
    errs = []
    v.check(dup, errs)
    need(any("duplicate" in e for e in errs), f"dup coords accepted: {errs}")
    print(f"ok - duplicate (q,r) rejected ({[e for e in errs if 'duplicate' in e][0][:70]})")

    # Custom-schema fallback with jsonschema blocked must fail loudly.
    restore = block_jsonschema()
    try:
        errs2: list[str] = []
        with tempfile.TemporaryDirectory() as td:
            custom = Path(td) / "custom_schema.json"
            custom.write_text("{}")
            msg = v.try_jsonschema({}, {}, custom, errs2)
        need(bool(errs2) and "FAIL" in msg, f"custom schema fallback too lenient: {msg} {errs2}")
        print(f"ok - custom schema without jsonschema rejected ({msg[:60]})")

        # Default schema fallback keeps authoritative-manual behavior.
        errs3: list[str] = []
        msg3 = v.try_jsonschema({}, {}, v.DEFAULT_SCHEMA, errs3)
        need(not errs3 and "SKIPPED" in msg3, f"default fallback changed: {msg3} {errs3}")
        print("ok - default schema fallback still authoritative-manual")
    finally:
        restore()

    # Renderer title uses the actual file name (skip cleanly w/o matplotlib).
    try:
        import matplotlib  # noqa: F401
    except ImportError:
        skipped.append("renderer title (matplotlib not installed)")
        print("SKIP - renderer title check (matplotlib not installed)")
    else:
        import render_save_diagram as rnd  # noqa: E402

        with tempfile.TemporaryDirectory() as td:
            alt = Path(td) / "alt_save.json"
            alt.write_text(json.dumps(BASE))
            out = Path(td) / "out.png"
            matplotlib.use("Agg")
            import matplotlib.pyplot as plt

            titles = []
            orig = plt.Axes.set_title

            def spy(self, label=None, *a, **k):
                if label:
                    titles.append(label)
                return orig(self, label, *a, **k)

            plt.Axes.set_title = spy  # type: ignore[method-assign]
            try:
                need(rnd.main(["render", str(alt), str(out)]) == 0, "renderer failed")
            finally:
                plt.Axes.set_title = orig  # type: ignore[method-assign]
            need(bool(titles) and "alt_save.json" in titles[0], f"title wrong: {titles[:1]}")
            need("save_example.json" not in titles[0], f"title hardcoded: {titles[:1]}")
        print("ok - renderer title uses save_path.name")
except AssertionError as e:
    print(f"FAIL: {e}")
    failures = 1

print("PASS: all regression checks" if not failures else "FAILURES present")
if not failures and skipped:
    print(f"(skipped: {', '.join(skipped)})")
raise SystemExit(failures)
