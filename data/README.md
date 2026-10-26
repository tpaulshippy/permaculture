# Store tuning data (issue #4)

Source of truth: [`tuning.json`](./tuning.json). Fixed numbers, no RNG (per Q11).
Sim resources: **water (gal) / money ($) / manhours (mh) / rain (gal)**. All units explicit below.

## MVP store cut (Q10: 4 items)

| Item | Category | Cost ($) | Build (mh) | Upkeep (mh/mo) | Upkeep ($/mo) | Water (gal/mo) | Other |
|---|---|---|---|---|---|---|---|
| House | structure | 4000 | 40 | 8 | 80 food | 0 | **provides 160 mh/mo** (net +152) |
| Well L1 | structure | 2500 | 24 | 4 | 15 energy | **+2500 pump** | depletes water table |
| Ditch / Berm (100 ft swale) | structure | 400 | 12 | 2 | 0 | +120 effective | **retention +12%** of rainfall/unit (cap 60%) |
| Mesquite (per tree) | plant | 40 | 2 | 1 | 0 | **−250 demand** | **yields +$12/mo** from month 12 |

Conventions: `+` water = supply (pump/capture), `−` water = irrigation demand.
Retention % = share of monthly rainfall captured that would otherwise run off (additive per swale).
Tree removal (dead or alive) costs 1 mh (per #1); not in table.

## Balance check (reference rain 1000 gal/mo, base capture 5% = 50 gal)

Setup: 1× house + 1× well L1 + 2× ditch/berm + 4× mesquite:

- Money upfront: 4000 + 2500 + 2·400 + 4·40 = **$7460** (start $10,000 → $2540 left)
- Labor upfront: 40 + 24 + 2·12 + 4·2 = **96 mh** (build order: house first, player starts at 0 mh)
- Monthly labor: upkeep 8+4+2·2+4·1 = 20 mh vs 160 provided → **140 mh free** for expansion
- Monthly money: −80 −15 + 0 (trees pre-yield) = **−$95/mo**; at maturity +4·12 = **−$47/mo** (slight burn → pressure to scale to ~8–10 trees/well, 5-yr arc per #1)
- Monthly water: +2500 pump + (50 base + 2·120 capture) − 4·250 demand = **+1790 gal surplus** (room for ~7 more trees per well; over-pumping without swales loses)

## Validation

```sh
python3 scripts/validate_tuning.py
```

Checks: JSON parses, exactly these 4 item ids, all required fields present with correct units/types,
house `provides_manhours_per_mo`, well `pump_gal_per_mo`, ditch `retention_percent`, mesquite `water_need_gal_per_mo` + `yield_usd_per_mo`,
and the balance-check arithmetic above. Evidence chart: `docs/evidence/4/store_tuning.png` (generated from `tuning.json`).

## Full field reference

See `meta.units` and `meta.sim_baseline` in `tuning.json` for unit definitions and assumptions.
