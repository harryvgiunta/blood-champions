"""Rebuild the roguelite's reward chests.

    python tools/build_reward_chests.py

Runs Blender 5.1 in background mode on `tools/prepare_reward_chests.py`, which
writes `assets/props/chests/` - the three-variant GLB, one PBR set per material
and `reward_chests.json` - and leaves the beauty renders in
`.runtime/chest-build/`. Override the executable with ``IRONWOOD_BLENDER``.

Everything is authored here: no downloaded scan, no external model, so there is
no source staging step and no hash to pin. After a rebuild, reimport in Godot:

    $Godot = '.\\.runtime\\godot\\Godot_v4.7.2-stable_win64_console.exe'
    & $Godot --headless --editor --path . --import
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_BLENDER = Path(r"C:/Program Files/Blender Foundation/Blender 5.1/blender.exe")
OUT_DIR = ROOT / "assets" / "props" / "chests"
WORK_DIR = ROOT / ".runtime" / "chest-build"


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
        "--python", str(ROOT / "tools" / "prepare_reward_chests.py"),
        "--",
        str(OUT_DIR),
        str(WORK_DIR),
    ]
    result = subprocess.run(command, cwd=str(ROOT))
    if result.returncode != 0:
        raise SystemExit(f"Blender failed with code {result.returncode}")
    manifest = OUT_DIR / "reward_chests.json"
    if not manifest.exists():
        raise SystemExit(f"no manifest at {manifest}")
    return json.loads(manifest.read_text(encoding="utf-8"))


def main() -> None:
    report = build()
    file = report["file"]
    print(f"reward chests: {file['name']} {file['bytes']} bytes  sha256 {file['sha256']}")
    for variant, row in report["variants"].items():
        print(f"  {variant:7s} {row['node']:14s} {row['triangles']:6d} tris  "
              f"{', '.join(row['materials'])}")
    for group, row in report["textures"].items():
        print(f"  {group:5s} {row['size']:5d}  metal {row['metallic']:.2f}  "
              f"{', '.join(sorted(row['files']))}")
    print(f"  build {report['build_seconds']} s")
    if not report.get("blender"):
        print("  warning: manifest carries no Blender version", file=sys.stderr)


if __name__ == "__main__":
    main()
