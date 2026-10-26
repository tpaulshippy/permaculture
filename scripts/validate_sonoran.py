"""Validate Sonoran content pack (issue #6). Pure stdlib. Exit 0 = pass."""
import json, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
fails = []
def check(cond, msg):
    print(("PASS" if cond else "FAIL") + ": " + msg)
    if not cond:
        fails.append(msg)

r = json.loads((ROOT / "data/sonoran_rainfall.json").read_text())
m = json.loads((ROOT / "data/mesquite.json").read_text())

check(r.get("units") == "mm/month", "rainfall units are mm/month")
check(len(r.get("rainfall_mm", [])) == 12, "rainfall_mm has 12 values")
check(len(r.get("months", [])) == 12, "months has 12 labels")
check(len(set(r.get("months", []))) == 12, "month labels are 12 unique names (season lookups use .index)")
check(all(v >= 0 for v in r["rainfall_mm"]), "all rainfall values >= 0")
check(abs(sum(r["rainfall_mm"]) - r["annual_mm"]) < 0.5, f"annual_mm {r['annual_mm']} ~= sum {sum(r['rainfall_mm']):.1f} (12 values rounded to 0.1 mm)")
check("weather.gov" in r.get("source", ""), "rainfall cites NWS source with URL")
check(len(r.get("rainfall_in", [])) == 12, "rainfall_in has 12 source values")
check(abs(sum(r["rainfall_in"]) - r["annual_in"]) < 0.05, "annual_in matches monthly sum")
check(all(abs(mm - inch * 25.4) < 0.06 for mm, inch in zip(r["rainfall_mm"], r["rainfall_in"])), "each rainfall_mm matches rainfall_in x25.4 (0.1 mm rounding)")
# monsoon peak check (seasons["monsoon"] months dominate)
monsoon_months = r.get("seasons", {}).get("monsoon", ["Jul", "Aug", "Sep"])
monsoon = sum(r["rainfall_mm"][r["months"].index(m)] for m in monsoon_months)
check(monsoon > sum(r["rainfall_mm"]) * 0.45, f"monsoon {'/'.join(monsoon_months)} share {monsoon/sum(r['rainfall_mm']):.0%} > 45%")

check(m.get("species") == "Prosopis velutina", "mesquite species set")
check(m.get("nitrogen_fixer") is True, "mesquite nitrogen_fixer true")
check("game_stats_proposed" in m, "mesquite has proposed game stats (no tuning.json overwrite)")
g = m.get("game_stats_proposed") or {}
check(g.get("cost_usd") == 40 and g.get("build_manhours") == 2, "mesquite cost/manhours match feat/4 tuning (40 USD, 2 mh)")
check(g.get("water_need_gal_per_mo") == 250, "mesquite water need matches tuning (250 gal/mo)")
check(g.get("yield_usd_per_mo") == 12 and g.get("yield_start_month") == 12, "mesquite yield matches tuning ($12/mo from month 12)")
check("game_stats_proposed" in m and all(k not in m for k in ("cost_usd", "water_need_gal_per_mo", "yield_usd_per_mo")), "mesquite stats namespaced under game_stats_proposed, separate from tuning schema")
check(len(m.get("sources", [])) >= 2, "mesquite cites >=2 sources")
seasons = r.get("seasons", {})
check(sorted(sum([seasons.get(k, []) for k in ("winter_rains", "foresummer_drought", "monsoon", "autumn")], [])) == sorted(r.get("months", [])), "seasons partition all 12 months exactly once")
surv = g.get("extensions", {}).get("survival", {})
check(set(r.get("months", [])) - set(surv.get("optimal_plant_months", [])) == {"Apr", "May", "Jun"} and "plant_in_foresummer_penalty" in surv, "every month has a defined survival effect (optimal except Apr-Jun penalty)")
check(surv.get("foresummer_survival_multiplier") == 0.6 and set(surv.get("foresummer_penalty_months", [])) == {"Apr", "May", "Jun"}, "foresummer penalty is a numeric 0.6 multiplier on Apr-Jun")
check(isinstance(m.get("taproot_m"), (int, float)), "taproot_m is a numeric metric (qualifier in taproot_note)")

info = (ROOT / "docs/sonoran_info.md").read_text().lower()
for kw in ["best time to plant", "problems", "strategies", "monsoon", "caliche"]:
    check(kw in info, f"info text covers '{kw}'")

chart = ROOT / "docs/evidence/6/rainfall_chart.png"
check(chart.exists() and chart.stat().st_size > 5000, "evidence chart PNG exists and non-trivial")
check(chart.exists() and chart.stat().st_mtime >= (ROOT / "data/sonoran_rainfall.json").stat().st_mtime, "evidence chart is newer than the rainfall data (regenerate after data changes)")

print(f"\n{'ALL CHECKS PASSED' if not fails else f'{len(fails)} FAILURES'}")
sys.exit(1 if fails else 0)
