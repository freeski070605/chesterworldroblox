#!/usr/bin/env python3
from __future__ import annotations

import re
import shutil
from datetime import datetime
from pathlib import Path

PROJECT = Path(r"E:\code\chesterworld-roblox")

BOOTSTRAP = PROJECT / "src" / "server" / "Bootstrap.server.lua"
WORLD_DIR = PROJECT / "src" / "server" / "World"

SOURCE_CONFORMER = PROJECT / "tools" / "RoadTerrainConformer.server.lua"
SOURCE_FINISH = PROJECT / "tools" / "StreetFinishBuilder.server.lua"

TARGET_CONFORMER = WORLD_DIR / "RoadTerrainConformer.server.lua"
TARGET_FINISH = WORLD_DIR / "StreetFinishBuilder.server.lua"

BACKUP_ROOT = PROJECT / "tools" / "backups" / "street_system_v32"


def backup(path: Path, stamp: str):
    if not path.exists():
        return

    BACKUP_ROOT.mkdir(parents=True, exist_ok=True)
    shutil.copy2(
        path,
        BACKUP_ROOT / f"{path.name}.before_v32_{stamp}",
    )


def patch_bootstrap():
    if not BOOTSTRAP.exists():
        raise SystemExit(f"Missing Bootstrap: {BOOTSTRAP}")

    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    backup(BOOTSTRAP, stamp)

    text = BOOTSTRAP.read_text(encoding="utf-8")

    # Remove any previous V3.2 signal lines so reruns are idempotent.
    text = re.sub(
        r'^\s*workspace:SetAttribute\("CW_BootstrapComplete",\s*(?:true|false)\)\s*$\n?',
        "",
        text,
        flags=re.MULTILINE,
    )
    text = re.sub(
        r'^\s*workspace:SetAttribute\("CW_RoadConformComplete",\s*(?:true|false)\)\s*$\n?',
        "",
        text,
        flags=re.MULTILINE,
    )

    # At script start, nil/false prevents the conformer from racing Bootstrap.
    prefix = (
        'workspace:SetAttribute("CW_BootstrapComplete", false)\n'
        'workspace:SetAttribute("CW_RoadConformComplete", false)\n\n'
    )
    text = prefix + text

    marker = 'print("[ChesterWorld] Bootstrap complete.")'
    if marker not in text:
        raise RuntimeError(
            "Could not find Bootstrap complete marker. "
            "No runtime scripts were installed."
        )

    text = text.replace(
        marker,
        'workspace:SetAttribute("CW_BootstrapComplete", true)\n' + marker,
        1,
    )

    BOOTSTRAP.write_text(text, encoding="utf-8")
    print(f"Patched Bootstrap ordering signal: {BOOTSTRAP}")


def install_runtime():
    WORLD_DIR.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")

    backup(TARGET_CONFORMER, stamp)
    backup(TARGET_FINISH, stamp)

    shutil.copy2(SOURCE_CONFORMER, TARGET_CONFORMER)
    shutil.copy2(SOURCE_FINISH, TARGET_FINISH)

    print(f"Installed deterministic conformer: {TARGET_CONFORMER}")
    print(f"Installed StreetSystem V3.2:       {TARGET_FINISH}")


def main():
    print("=" * 88)
    print("CHESTERWORLD STREET SYSTEM V3.2 - INSTALL")
    print("=" * 88)

    patch_bootstrap()
    install_runtime()

    print("=" * 88)
    print("V3.2 INSTALL COMPLETE")
    print("=" * 88)


if __name__ == "__main__":
    main()
