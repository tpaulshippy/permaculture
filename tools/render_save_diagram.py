#!/usr/bin/env python3
"""Render docs/evidence/7/save_diagram.png from data/save_example.json.

Reads the REAL example save (no mockups) and draws:
  - header: version / seed / biome / month / resources
  - axial hex grid colored by content type (structure vs plant vs empty)
Labels show structure_id / plant_id + growth stage.

Usage:
    python3 tools/render_save_diagram.py [save.json] [out.png]
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DEFAULT_SAVE = REPO / "data" / "save_example.json"
DEFAULT_OUT = REPO / "docs" / "evidence" / "7" / "save_diagram.png"


def axial_to_pixel(q: int, r: int, size: float = 1.0):
    # pointy-top axial layout
    x = size * math.sqrt(3) * (q + r / 2)
    y = size * 1.5 * r
    return x, y


def main(argv: list[str]) -> int:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.patches import RegularPolygon

    save_path = Path(argv[1]) if len(argv) > 1 else DEFAULT_SAVE
    out_path = Path(argv[2]) if len(argv) > 2 else DEFAULT_OUT
    save = json.loads(save_path.read_text())
    hexes = save.get("hexes", [])
    res = save.get("resources", {})

    fig, ax = plt.subplots(figsize=(10, 6))
    ax.set_aspect("equal")
    ax.axis("off")

    title = (
        f"save_example.json — v{save.get('version')} | seed={save.get('seed')} "
        f"| biome={save.get('biome_id')} | month_index={save.get('month_index')}"
    )
    subtitle = (
        f"money={res.get('money')}  water_table={res.get('water_table')}  "
        f"manhours={res.get('manhours')}  hexes={len(hexes)}"
    )
    ax.set_title(f"{title}\n{subtitle}", fontsize=10, loc="left", pad=12)

    def color_for(h: dict) -> str:
        if h.get("structure_id"):
            return {"house": "#e8b34b", "well_1": "#5aa9e6"}.get(
                str(h["structure_id"]), "#c9a0dc"
            )
        pid = h.get("plant_id")
        if pid:
            return "#7bc96f" if h.get("condition") != "dead" else "#8a8a8a"
        return "#eeeeee"

    for h in hexes:
        x, y = axial_to_pixel(int(h["q"]), int(h["r"]))
        poly = RegularPolygon(
            (x, y), numVertices=6, radius=0.95, orientation=math.pi / 6,
            facecolor=color_for(h), edgecolor="#333333",
        )
        ax.add_patch(poly)
        label = h.get("structure_id") or h.get("plant_id") or f"{h['q']},{h['r']}"
        g = h.get("growth_stage")
        if g is not None and h.get("plant_id"):
            label = f"{label}\ng{g}"
        ax.text(x, y, str(label), ha="center", va="center", fontsize=7)

    # legend (proxy artists)
    import matplotlib.patches as mpatches

    legend = [
        mpatches.Patch(color="#e8b34b", label="house"),
        mpatches.Patch(color="#5aa9e6", label="well"),
        mpatches.Patch(color="#c9a0dc", label="other structure"),
        mpatches.Patch(color="#7bc96f", label="plant"),
        mpatches.Patch(color="#8a8a8a", label="dead"),
    ]
    ax.legend(handles=legend, loc="lower right", fontsize=8, title="hex content")

    xs = [axial_to_pixel(int(h["q"]), int(h["r"]))[0] for h in hexes] or [0]
    ys = [axial_to_pixel(int(h["q"]), int(h["r"]))[1] for h in hexes] or [0]
    ax.set_xlim(min(xs) - 2, max(xs) + 2)
    ax.set_ylim(min(ys) - 2.5, max(ys) + 2)
    fig.text(
        0.01, 0.01,
        f"source: {save_path.name} (rendered from actual file, not a mockup)",
        fontsize=7, color="#555555",
    )
    out_path.parent.mkdir(parents=True, exist_ok=True)
    fig.tight_layout()
    fig.savefig(out_path, dpi=150)
    print(f"wrote {out_path} ({len(hexes)} hexes from {save_path})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
