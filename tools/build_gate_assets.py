"""Rebuild the run's three gates.

    python tools/build_gate_assets.py

Runs Blender 5.1 in background mode on `tools/prepare_gate_assets.py`, which
writes `assets/props/gates/` - the three-variant GLB, one PBR set per material
and `ironwood_gates.json` - and leaves the beauty renders in
`.runtime/gate-build/`. Override the executable with ``IRONWOOD_BLENDER``.

Everything is authored here: no downloaded model or scan, so there is no source
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
OUT_DIR = ROOT / "assets" / "props" / "gates"
WORK_DIR = ROOT / ".runtime" / "gate-build"


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
        "--python", str(ROOT / "tools" / "prepare_gate_assets.py"),
        "--",
        str(OUT_DIR),
        str(WORK_DIR),
    ]
    result = subprocess.run(command, cwd=str(ROOT))
    if result.returncode != 0:
        raise SystemExit(f"Blender failed with code {result.returncode}")
    manifest = OUT_DIR / "ironwood_gates.json"
    if not manifest.exists():
        raise SystemExit(f"no manifest at {manifest}")
    return json.loads(manifest.read_text(encoding="utf-8"))


def main() -> None:
    report = build()
    file = report["file"]
    print(f"gates: {file['name']} {file['bytes']} bytes  sha256 {file['sha256']}")
    for variant, row in report["variants"].items():
        print(f"  {variant:9s} {row['node']:14s} {row['triangles']:6d} tris  "
              f"{', '.join(row['materials'])}")
    for group, row in report["textures"].items():
        print(f"  {group:8s} {row['size']:5d}  metal {row['metallic']:.2f}")
    print(f"  build {report['build_seconds']} s")


if __name__ == "__main__":
    main()
