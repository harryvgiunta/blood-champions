"""Rebuild the reward card's art.

    python tools/build_reward_cards.py

Runs Blender 5.1 in background mode on `tools/prepare_reward_cards.py`, which
writes `assets/ui/cards/`: the rarity frames (idle and hover), the five family
sigils, the world plaques and `cards.json`, the manifest the HUD reads. Override
the executable with ``IRONWOOD_BLENDER``.

Everything is rendered here - no source pack, no download - so there is no
staging step. After a rebuild, reimport in Godot:

    $Godot = '.\\.runtime\\godot\\Godot_v4.7.2-stable_win64_console.exe'
    & $Godot --headless --editor --path . --import
"""

from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_BLENDER = Path(r"C:/Program Files/Blender Foundation/Blender 5.1/blender.exe")
OUT_DIR = ROOT / "assets" / "ui" / "cards"
WORK_DIR = ROOT / ".runtime" / "card-build"


def blender_path() -> Path:
    override = os.environ.get("IRONWOOD_BLENDER")
    candidate = Path(override) if override else DEFAULT_BLENDER
    if not candidate.exists():
        raise SystemExit(f"Blender not found at {candidate}; set IRONWOOD_BLENDER")
    return candidate


def build() -> dict:
    WORK_DIR.mkdir(parents=True, exist_ok=True)
    command = [
        str(blender_path()),
        "--background",
        "--factory-startup",
        "--python-exit-code", "1",
        "--python", str(ROOT / "tools" / "prepare_reward_cards.py"),
        "--",
        str(OUT_DIR),
        str(WORK_DIR),
    ]
    result = subprocess.run(command, cwd=str(ROOT))
    if result.returncode != 0:
        raise SystemExit(f"Blender failed with code {result.returncode}")
    manifest = OUT_DIR / "cards.json"
    if not manifest.exists():
        raise SystemExit(f"no manifest at {manifest}")
    return json.loads(manifest.read_text(encoding="utf-8"))


def main() -> None:
    report = build()
    for rarity, states in report["frames"].items():
        print(f"  frame {rarity:10s} {', '.join(sorted(states))}")
    print(f"  sigils {', '.join(sorted(report['sigils']))}")
    print(f"  plaques {', '.join(sorted(report['plaques']))}")
    print(f"  margin {report['frame_margin']} px   build {report['build_seconds']} s")


if __name__ == "__main__":
    main()
