"""Generate docs/evidence/6/rainfall_chart.png FROM data/sonoran_rainfall.json (no hardcoded numbers).

Requires matplotlib: pip install matplotlib
"""
import hashlib
import json
from pathlib import Path
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

ROOT = Path(__file__).resolve().parent.parent
data = json.loads((ROOT / "data/sonoran_rainfall.json").read_text())
months, vals = data["months"], data["rainfall_mm"]
if len(months) != 12 or len(vals) != 12:
    raise ValueError("need 12 months of data")
seasons = data["seasons"]
WINTER = {months.index(m) for m in seasons["winter_rains"]}
MONSOON = {months.index(m) for m in seasons["monsoon"]}
if not WINTER.isdisjoint(MONSOON):
    raise ValueError("winter and monsoon months must not overlap")
colors = ["#2e86ab" if i in MONSOON else "#7fb069" if i in WINTER else "#b0a898" for i in range(12)]
fig, ax = plt.subplots(figsize=(9, 5))
bars = ax.bar(months, vals, color=colors, edgecolor="black")
ax.bar_label(bars, fmt="%.1f")
ax.set_ylabel("Rainfall (mm/month)")
ax.set_title(f"Sonoran typical year rainfall — {data['station']}\nAnnual {data['annual_mm']} mm")
ax.set_ylim(0, max(vals) * 1.25)
ax.text(0.99, 0.97, f"winter rains {'/'.join(seasons['winter_rains'])} (green) | monsoon {'/'.join(seasons['monsoon'])} (blue) | other months (tan)",
        transform=ax.transAxes, ha="right", va="top", fontsize=8, style="italic")
fig.tight_layout()
out = ROOT / "docs/evidence/6/rainfall_chart.png"
out.parent.mkdir(parents=True, exist_ok=True)
fig.savefig(out, dpi=120)
fingerprint = hashlib.sha256(json.dumps({"months": months, "rainfall_mm": vals, "seasons": seasons,
                                          "annual_mm": data["annual_mm"], "station": data["station"]},
                                         sort_keys=True).encode()).hexdigest()
(out.parent / "rainfall_chart.sha256").write_text(fingerprint + "\n")
print(f"wrote {out} ({out.stat().st_size} bytes) from data/sonoran_rainfall.json")
