#!/usr/bin/env python3
"""Regression tests for cubic PR #12 findings (spec-only save schema).

Covers: bool version, Infinity numerics, unhashable condition, non-dict
summary path, seed > 2^53-1, bad saved_at, duplicate (q, r), custom-schema
fallback without jsonschema, renderer title per-file.
Run: python3 tools/test_validate_save_regressions.py
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


def expect_reject(name, mutate):
    save = copy.deepcopy(BASE)
    mutate(save)
    errs: list[str] = []
    v.check(save, errs)
    assert errs, f"{name}: payload was ACCEPTED, must be rejected"
    print(f"ok - {name}: rejected ({errs[0][:90]})")


def expect_accept(name, mutate=None):
    save = copy.deepcopy(BASE)
    if mutate:
        mutate(save)
    errs: list[str] = []
    v.check(save, errs)
    assert not errs, f"{name}: wrongly rejected: {errs[:3]}"
    print(f"ok - {name}: accepted")


failures = 0
try:
    expect_reject("version=true rejected", lambda s: s.update(version=True))
    expect_reject("version='1' rejected", lambda s: s.update(version="1"))
    expect_accept("version=1 accepted", None)

    s = copy.deepcopy(BASE)
    s["resources"]["money"] = float("inf")
    errs = []
    v.check(s, errs)
    assert errs, "money=Infinity accepted"
    print(f"ok - money=Infinity rejected ({errs[0][:70]})")

    s = copy.deepcopy(BASE)
    s["resources"]["manhours"] = float("inf")
    errs = []
    v.check(s, errs)
    assert errs, "manhours=Infinity accepted"
    print(f"ok - manhours=Infinity rejected ({errs[0][:70]})")

    s = copy.deepcopy(BASE)
    s["resources"]["water_table"] = float("inf")
    errs = []
    v.check(s, errs)
    assert errs, "water_table=Infinity accepted"
    print(f"ok - water_table=Infinity rejected ({errs[0][:70]})")

    # Unhashable condition must be a clean violation, not TypeError.
    s = copy.deepcopy(BASE)
    s["hexes"][0]["condition"] = ["healthy"]
    errs = []
    try:
        v.check(s, errs)
    except TypeError as e:
        raise AssertionError(f"condition list raised TypeError: {e}")
    assert errs, "condition list accepted"
    print(f"ok - condition=list rejected cleanly ({errs[0][:70]})")

    s = copy.deepcopy(BASE)
    s["hexes"][0]["condition"] = {"x": 1}
    errs = []
    try:
        v.check(s, errs)
    except TypeError as e:
        raise AssertionError(f"condition dict raised TypeError: {e}")
    assert errs, "condition dict accepted"
    print(f"ok - condition=dict rejected cleanly ({errs[0][:70]})")

    # Non-dict summary path: main() must not traceback on JSON array.
    with tempfile.TemporaryDirectory() as td:
        arr = Path(td) / "arr.json"
        arr.write_text("[1, 2, 3]")
        rc = v.main(["validate_save.py", str(arr), str(REPO / "data" / "save_schema.json")])
        assert rc == 1, f"array save main() rc={rc}, want 1"
    print("ok - non-dict save exits 1 without traceback")

    expect_reject("seed > 2^53-1 rejected", lambda s: s.update(seed=2**53))
    expect_accept("seed == 2^53-1 accepted", lambda s: s.update(seed=2**53 - 1))
    expect_reject("saved_at garbage rejected", lambda s: s.update(saved_at="not-a-date"))
    expect_reject("saved_at empty rejected", lambda s: s.update(saved_at=""))
    expect_accept("saved_at ISO-8601 accepted", None)

    dup = copy.deepcopy(BASE)
    dup["hexes"].append(dict(dup["hexes"][0]))
    errs = []
    v.check(dup, errs)
    assert any("duplicate" in e for e in errs), f"dup coords accepted: {errs}"
    print(f"ok - duplicate (q,r) rejected ({[e for e in errs if 'duplicate' in e][0][:70]})")

    # Custom-schema fallback without jsonschema must fail, not claim validated.
    errs2: list[str] = []
    with tempfile.TemporaryDirectory() as td:
        custom = Path(td) / "custom_schema.json"
        custom.write_text("{}")
        msg = v.try_jsonschema({}, {}, custom, errs2)
    assert errs2 and "FAIL" in msg, f"custom schema fallback too lenient: {msg} {errs2}"
    print(f"ok - custom schema without jsonschema rejected ({msg[:60]})")

    # Default schema fallback keeps old authoritative-manual behavior.
    errs3: list[str] = []
    msg3 = v.try_jsonschema({}, {}, v.DEFAULT_SCHEMA, errs3)
    assert not errs3 and "SKIPPED" in msg3, f"default fallback changed: {msg3} {errs3}"
    print("ok - default schema fallback still authoritative-manual")

    # Renderer title uses the actual file name.
    import render_save_diagram as rnd  # noqa: E402

    with tempfile.TemporaryDirectory() as td:
        alt = Path(td) / "alt_save.json"
        alt.write_text(json.dumps(BASE))
        out = Path(td) / "out.png"
        import matplotlib

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
            assert rnd.main(["render", str(alt), str(out)]) == 0
        finally:
            plt.Axes.set_title = orig  # type: ignore[method-assign]
        assert titles and "alt_save.json" in titles[0], f"title wrong: {titles[:1]}"
        assert "save_example.json" not in titles[0], f"title hardcoded: {titles[:1]}"
    print("ok - renderer title uses save_path.name")
except AssertionError as e:
    print(f"FAIL: {e}")
    failures = 1

print("PASS: all regression checks" if not failures else "FAILURES present")
raise SystemExit(failures)
