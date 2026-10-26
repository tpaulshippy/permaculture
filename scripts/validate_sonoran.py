"""Validate Sonoran content pack (issue #6). Pure stdlib. Exit 0 = pass."""
import hashlib
import json, re, sys
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parent.parent
fails = []
def check(cond, msg):
    print(("PASS" if cond else "FAIL") + ": " + msg)
    if not cond:
        fails.append(msg)

try:
    r = json.loads((ROOT / "data/sonoran_rainfall.json").read_text())
    m = json.loads((ROOT / "data/mesquite.json").read_text())
except (OSError, ValueError) as e:
    check(False, f"content files load as JSON ({e})")
    print(f"\n{len(fails)} FAILURES (unreadable content data)")
    sys.exit(1)
if not isinstance(r, dict) or not isinstance(m, dict):
    check(False, "content files are JSON objects")
    print(f"\n{len(fails)} FAILURES (malformed content data)")
    sys.exit(1)

for k in ("months", "rainfall_mm", "rainfall_in", "annual_mm", "annual_in", "source", "units", "seasons", "station"):
    check(k in r, f"rainfall data has '{k}'")
shape_ok = (
    isinstance(r.get("months"), list) and len(r["months"]) == 12 and all(isinstance(x, str) for x in r["months"])
    and isinstance(r.get("rainfall_mm"), list) and len(r["rainfall_mm"]) == 12 and all(isinstance(x, (int, float)) for x in r["rainfall_mm"])
    and isinstance(r.get("rainfall_in"), list) and len(r["rainfall_in"]) == 12 and all(isinstance(x, (int, float)) for x in r["rainfall_in"])
    and isinstance(r.get("seasons"), dict)
    and all(isinstance(r["seasons"].get(s), list) for s in ("winter_rains", "foresummer_drought", "monsoon", "autumn"))
    and all(lbl in r["months"] for s in ("winter_rains", "foresummer_drought", "monsoon", "autumn") for lbl in r["seasons"][s])
    and isinstance(r.get("annual_mm"), (int, float)) and isinstance(r.get("annual_in"), (int, float))
)
check(shape_ok, "rainfall data values have valid shapes/types/labels")
if any(k not in r for k in ("months", "rainfall_mm", "rainfall_in", "annual_mm", "annual_in", "seasons", "station")) or not shape_ok:
    print(f"\n{len(fails)} FAILURES (malformed rainfall data)")
    sys.exit(1)

check(r.get("units") == "mm/month", "rainfall units are mm/month")
check(len(r.get("rainfall_mm", [])) == 12, "rainfall_mm has 12 values")
check(len(r.get("months", [])) == 12, "months has 12 labels")
check(len(set(r.get("months", []))) == 12, "month labels are 12 unique names (season lookups use .index)")
check(all(v >= 0 for v in r["rainfall_mm"]), "all rainfall values >= 0")
check(abs(sum(r["rainfall_mm"]) - r["annual_mm"]) < 0.5, f"annual_mm {r['annual_mm']} ~= sum {sum(r['rainfall_mm']):.1f} (12 values rounded to 0.1 mm)")
try:
    src_text = r.get("source", "")
    src_hosts = [urlparse(u).hostname or "" for u in re.findall(r"https://[^\s)]+", src_text if isinstance(src_text, str) else "")]
except (TypeError, ValueError):
    src_hosts = []
check(any(h == "weather.gov" or h.endswith(".weather.gov") for h in src_hosts), "rainfall cites NWS source with URL")
check(len(r.get("rainfall_in", [])) == 12, "rainfall_in has 12 source values")
check(abs(sum(r["rainfall_in"]) - r["annual_in"]) < 0.05, "annual_in matches monthly sum")
check(all(abs(mm - inch * 25.4) < 0.06 for mm, inch in zip(r["rainfall_mm"], r["rainfall_in"])), "each rainfall_mm matches rainfall_in x25.4 (0.1 mm rounding)")
# monsoon peak check (seasons["monsoon"] months dominate)
monsoon_months = r.get("seasons", {}).get("monsoon", ["Jul", "Aug", "Sep"])
monsoon = sum(r["rainfall_mm"][r["months"].index(m)] for m in monsoon_months)
total = sum(r["rainfall_mm"])
check(total > 0 and monsoon / total > 0.45, f"monsoon {'/'.join(monsoon_months)} share {monsoon/total:.0%} > 45%" if total > 0 else "monsoon share check needs positive rainfall total")

check(m.get("species") == "Prosopis velutina", "mesquite species set")
check(m.get("nitrogen_fixer") is True, "mesquite nitrogen_fixer true")
check(isinstance(m.get("game_stats_proposed"), dict), "mesquite has proposed game stats (no tuning.json overwrite)")
g = m.get("game_stats_proposed") if isinstance(m.get("game_stats_proposed"), dict) else {}
ext = g.get("extensions") if isinstance(g.get("extensions"), dict) else None
check(isinstance(ext, dict), "mesquite extensions is an object")
surv_raw = ext.get("survival") if isinstance(ext, dict) else None
check(surv_raw is None or isinstance(surv_raw, dict), "mesquite survival is an object when present")
if ext is None or not (surv_raw is None or isinstance(surv_raw, dict)):
    print(f"\n{len(fails)} FAILURES (malformed mesquite data)")
    sys.exit(1)
ext, surv = ext or {}, surv_raw or {}
check(g.get("cost_usd") == 40 and g.get("build_manhours") == 2, "mesquite cost/manhours match feat/4 tuning (40 USD, 2 mh)")
check(g.get("water_need_gal_per_mo") == 250, "mesquite water need matches tuning (250 gal/mo)")
check(g.get("yield_usd_per_mo") == 12 and g.get("yield_start_month") == 12, "mesquite yield matches tuning ($12/mo from month 12)")
check("game_stats_proposed" in m and all(k not in m for k in ("cost_usd", "water_need_gal_per_mo", "yield_usd_per_mo")), "mesquite stats namespaced under game_stats_proposed, separate from tuning schema")
check(len(m.get("sources", [])) >= 2, "mesquite cites >=2 sources")
seasons = r.get("seasons", {})
check(sorted(sum([seasons.get(k, []) for k in ("winter_rains", "foresummer_drought", "monsoon", "autumn")], [])) == sorted(r.get("months", [])), "seasons partition all 12 months exactly once")
penalty = set(surv.get("foresummer_penalty_months", []))
check(set(seasons.get("foresummer_drought", [])) == penalty and set(r.get("months", [])) - set(surv.get("optimal_plant_months", [])) == penalty, "penalty months equal the foresummer drought season and cover exactly the non-optimal months")
check(set(surv.get("optimal_plant_months", [])) <= set(r.get("months", [])), "optimal months are all known month labels")
check(surv.get("foresummer_survival_multiplier") == 0.6 and surv.get("foresummer_survival_multiplier_irrigated") == 1.0, "survival multipliers numeric (0.6 unirrigated, 1.0 at establishment rate)")
check("establishment_yield_rule" in ext, "yield-during-establishment rule is defined (yield mo 12 vs watering thru mo 18)")
check("growth_cm_per_year_note" in m, "growth rate is marked as a game-balance representative value")
check(isinstance(m.get("taproot_m"), (int, float)), "taproot_m is a numeric metric (qualifier in taproot_note)")

info = (ROOT / "docs/sonoran_info.md").read_text().lower()
for kw in ["best time to plant", "problems", "strategies", "monsoon", "caliche"]:
    check(kw in info, f"info text covers '{kw}'")

chart = ROOT / "docs/evidence/6/rainfall_chart.png"
check(chart.exists() and chart.stat().st_size > 5000, "evidence chart PNG exists and non-trivial")
fingerprint = hashlib.sha256(json.dumps({"months": r["months"], "rainfall_mm": r["rainfall_mm"], "seasons": seasons,
                                          "annual_mm": r["annual_mm"], "station": r["station"]},
                                         sort_keys=True).encode()).hexdigest()
sidecar = ROOT / "docs/evidence/6/rainfall_chart.sha256"
check(sidecar.exists() and sidecar.read_text().strip() == fingerprint, "evidence chart fingerprint matches current rainfall data (regen plot after data changes)")

print(f"\n{'ALL CHECKS PASSED' if not fails else f'{len(fails)} FAILURES'}")
sys.exit(1 if fails else 0)
