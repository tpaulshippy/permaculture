#!/usr/bin/env python3
"""Generate docs/evidence/4/store_tuning.png from data/tuning.json (issue #4).

Requires matplotlib (not in the stdlib). Setup from a fresh checkout::

    pip install matplotlib
    python3 docs/evidence/4/generate_chart.py

Balance-row numbers and panel titles are derived from data/tuning.json, so
regenerating the chart after a tuning change cannot leave stale figures.
"""
import json
import sys
from pathlib import Path

try:
    import matplotlib
except ImportError:
    sys.exit("generate_chart.py requires matplotlib: pip install matplotlib")

matplotlib.use("Agg")
import matplotlib.pyplot as plt

ROOT = Path(__file__).resolve().parents[3]
data = json.loads((ROOT / "data" / "tuning.json").read_text())
items = {i["id"]: i for i in data["items"]}
base = data["meta"]["sim_baseline"]
bc = base["balance_check_monthly"]
order = ["house", "well_l1", "ditch_berm", "mesquite"]
labels = [items[k]["name"] for k in order]

fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(10, 7), gridspec_kw={"height_ratios": [3, 2]})
fig.suptitle("Issue #4 — MVP store tuning (from data/tuning.json)", fontsize=12, fontweight="bold")

costs = [items[k]["cost_usd"] for k in order]
builds = [items[k]["build_manhours"] for k in order]
x = range(len(order))
w = 0.35
ax1.bar([p - w / 2 for p in x], costs, width=w, label="Cost ($)", color="tab:blue")
ax1.set_ylabel("Cost ($)", color="tab:blue")
ax1.tick_params(axis="y", labelcolor="tab:blue")
# Separate labor axis: build labor (mh) is ~100x smaller than costs ($),
# so sharing one y-axis would render the build bars nearly invisible.
ax1b = ax1.twinx()
ax1b.bar([p + w / 2 for p in x], builds, width=w, label="Build (mh)", color="tab:orange")
ax1b.set_ylabel("Build (mh)", color="tab:orange")
ax1b.tick_params(axis="y", labelcolor="tab:orange")
for i, (c, b) in enumerate(zip(costs, builds)):
    ax1.text(i - w / 2, c, f"${c}", ha="center", va="bottom", fontsize=8)
    ax1b.text(i + w / 2, b, f"{b}", ha="center", va="bottom", fontsize=8)
ax1.set_xticks(list(x), labels, fontsize=9)
lines1, labels1 = ax1.get_legend_handles_labels()
lines2, labels2 = ax1b.get_legend_handles_labels()
ax1.legend(lines1 + lines2, labels1 + labels2, fontsize=8, loc="upper left")
ax1.set_title("Upfront cost vs build labor", fontsize=10)

ax2.axis("off")
rows = [
    [items[k]["name"], f"${items[k]['cost_usd']}", f"{items[k]['build_manhours']} mh",
     f"{items[k]['upkeep_manhours_per_mo']} mh/mo", f"{items[k]['water_gal_per_mo']:+} gal/mo"]
    for k in order
]
rows.append([f"Balance {bc['setup']}",
             f"${bc['money_upfront_usd']} upfront",
             f"{bc['labor_upfront_mh']} mh build",
             f"{bc['upkeep_mh_per_mo']} mh/mo upkeep / {bc['free_mh_per_mo']} free",
             f"{bc['water_per_mo_gal']:+} gal/mo surplus"])
t = ax2.table(cellText=rows,
              colLabels=["Item", "Cost", "Build", "Upkeep", "Water"],
              loc="center", colWidths=[0.34, 0.16, 0.14, 0.22, 0.20])
t.auto_set_font_size(False)
t.set_fontsize(8)
t.scale(1, 1.4)
h, wl, d, m = (items[k] for k in order)
ax2.set_title(
    f"Monthly numbers (house {h['provides_manhours_per_mo']} mh/mo | "
    f"well {wl['pump_gal_per_mo']} gal/mo | "
    f"swale +{d['retention_percent']}% | "
    f"mesquite {m['water_gal_per_mo']:+}/+${m['yield_usd_per_mo']})",
    fontsize=9)

out = ROOT / "docs" / "evidence" / "4" / "store_tuning.png"
fig.tight_layout()
fig.savefig(out, dpi=150)
print(f"wrote {out} ({out.stat().st_size} bytes)")
