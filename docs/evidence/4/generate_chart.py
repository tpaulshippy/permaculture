#!/usr/bin/env python3
"""Generate docs/evidence/4/store_tuning.png from data/tuning.json (issue #4)."""
import json
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

ROOT = Path(__file__).resolve().parents[3]
data = json.loads((ROOT / "data" / "tuning.json").read_text())
items = {i["id"]: i for i in data["items"]}
order = ["house", "well_l1", "ditch_berm", "mesquite"]
labels = [items[k]["name"] for k in order]

fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(10, 7), gridspec_kw={"height_ratios": [3, 2]})
fig.suptitle("Issue #4 — MVP store tuning (from data/tuning.json)", fontsize=12, fontweight="bold")

costs = [items[k]["cost_usd"] for k in order]
builds = [items[k]["build_manhours"] for k in order]
x = range(len(order))
w = 0.35
ax1.bar([p - w / 2 for p in x], costs, width=w, label="Cost ($)")
ax1.bar([p + w / 2 for p in x], builds, width=w, label="Build (mh)")
for i, (c, b) in enumerate(zip(costs, builds)):
    ax1.text(i - w / 2, c, f"${c}", ha="center", va="bottom", fontsize=8)
    ax1.text(i + w / 2, b, f"{b}", ha="center", va="bottom", fontsize=8)
ax1.set_xticks(list(x), labels, fontsize=9)
ax1.set_ylabel("$/mh")
ax1.legend(fontsize=8)
ax1.set_title("Upfront cost vs build labor", fontsize=10)

ax2.axis("off")
rows = [
    [items[k]["name"], f"${items[k]['cost_usd']}", f"{items[k]['build_manhours']} mh",
     f"{items[k]['upkeep_manhours_per_mo']} mh/mo", f"{items[k]['water_gal_per_mo']:+} gal/mo"]
    for k in order
]
rows.append(["Balance 1+1+2+4", "$7460 upfront", "96 mh build", "20 mh/mo upkeep / 140 free", "+1790 gal/mo surplus"])
t = ax2.table(cellText=rows,
              colLabels=["Item", "Cost", "Build", "Upkeep", "Water"],
              loc="center", colWidths=[0.34, 0.16, 0.14, 0.22, 0.20])
t.auto_set_font_size(False)
t.set_fontsize(8)
t.scale(1, 1.4)
ax2.set_title("Monthly numbers (house 160 mh/mo | well 2500 gal/mo | swale +12% | mesquite -250/+ $12)", fontsize=9)

out = ROOT / "docs" / "evidence" / "4" / "store_tuning.png"
fig.tight_layout()
fig.savefig(out, dpi=150)
print(f"wrote {out} ({out.stat().st_size} bytes)")
