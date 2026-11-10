#!/usr/bin/env python3
"""Install the Solo Leveling screensaver beside any other theme's screensaver."""
import argparse
import datetime
import getpass
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
STOCK_LAUNCH = 'omarchy-launch-screensaver")'
EXPANSE_LAUNCH = '\\"$HOME/.local/share/omarchy-expanse/launch-screensaver\\"")'
DISPATCH_LAUNCH = '\\"$HOME/.local/share/omarchy-theme-screensaver/launch-screensaver\\"")'


def patch_service(text):
    if DISPATCH_LAUNCH in text:
        return text
    matches = [candidate for candidate in (STOCK_LAUNCH, EXPANSE_LAUNCH) if text.count(candidate) == 1]
    if len(matches) != 1:
        raise ValueError("Unsupported Omarchy idle service; no files changed.")
    return text.replace(matches[0], DISPATCH_LAUNCH, 1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="check compatibility without making changes")
    args = parser.parse_args()
    home = Path.home()
    omarchy = Path(os.environ.get("OMARCHY_PATH", "/usr/share/omarchy"))
    stock = (omarchy / "shell/plugins/services/idle/Service.qml").read_text()
    plugin_id = getpass.getuser() + ".idle"
    target = home / ".config/omarchy/plugins" / plugin_id
    current = (target / "Service.qml").read_text() if target.exists() else stock
    updated = patch_service(current)

    if target.exists():
        manifest = json.loads((target / "manifest.json").read_text())
        if manifest.get("omarchy", {}).get("clonedFrom") != "omarchy.idle":
            raise ValueError(f"{target} is not a clone of omarchy.idle.")

    for command in ("qs", "omarchy", "omarchy-shell", "flock", "hyprctl", "jq"):
        if not shutil.which(command):
            raise ValueError(f"Required command is missing: {command}")
    version = subprocess.check_output(["qs", "--version"], text=True)
    match = re.search(r"Quickshell (\d+)\.(\d+)", version)
    if not match or tuple(map(int, match.groups())) < (0, 3):
        raise ValueError("Quickshell 0.3 or later is required.")

    for asset in ("shell.qml", "pixel-rain.frag.qsb", "launch-screensaver", "dispatch-screensaver"):
        if not (ROOT / "screensaver" / asset).is_file():
            raise ValueError(f"Missing screensaver asset: {asset}")
    images = sorted(
        path for path in (ROOT / "backgrounds").iterdir()
        if path.suffix.lower() in (".jpg", ".jpeg", ".png", ".webp")
    )
    if not images:
        raise ValueError("No images in backgrounds/ for the screensaver to show.")

    if args.check:
        print("Compatible idle service and complete Solo Leveling screensaver assets. No files changed.")
        return

    status = json.loads(subprocess.check_output(["omarchy-shell", "lock", "status"], text=True))
    if status.get("locked") or status.get("requested") or status.get("secure"):
        raise ValueError("Unlock your session before installing.")
    if not target.exists():
        subprocess.run(["omarchy", "plugin", "clone", "omarchy.idle"], check=True)

    backup = home / ".local/state/omarchy/backups" / (
        "solo-leveling-screensaver-" + datetime.datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    )
    shutil.copytree(target, backup / "idle-plugin")
    runtime = home / ".local/share/omarchy-solo-leveling"
    dispatcher = home / ".local/share/omarchy-theme-screensaver"
    if runtime.exists():
        shutil.copytree(runtime, backup / "runtime")
    if dispatcher.exists():
        shutil.copytree(dispatcher, backup / "dispatcher")

    runtime.mkdir(parents=True, exist_ok=True)
    dispatcher.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["qs", "ipc", "-p", str(runtime / "org.omarchy.screensaver"), "call", "screensaver", "quit"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    app = runtime / "org.omarchy.screensaver"
    shutil.copytree(ROOT / "screensaver", app, dirs_exist_ok=True)
    # The scenes are the theme's wallpapers, replaced wholesale so a wallpaper
    # removed from the theme leaves the rotation too.
    shutil.rmtree(app / "images", ignore_errors=True)
    (app / "images").mkdir()
    for image in images:
        shutil.copy2(image, app / "images" / image.name)
    shutil.copy2(ROOT / "screensaver/launch-screensaver", runtime / "launch-screensaver")
    shutil.copy2(ROOT / "screensaver/dispatch-screensaver", dispatcher / "launch-screensaver")
    (runtime / "launch-screensaver").chmod(0o755)
    (dispatcher / "launch-screensaver").chmod(0o755)

    temporary = target / "Service.qml.new"
    temporary.write_text(updated)
    temporary.replace(target / "Service.qml")
    subprocess.run(["omarchy-shell", "shell", "rescanPlugins"], check=True)
    subprocess.run(["omarchy", "plugin", "enable", plugin_id], check=True)
    print(f"Installed the Solo Leveling screensaver with {len(images)} scenes. Backup: {backup}")
    print("Activate it with: omarchy restart shell")
    print(f"Preview: SOLO_PREVIEW_SECONDS=30 {runtime}/launch-screensaver --preview")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
