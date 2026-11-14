#!/usr/bin/env python3
"""Write hyroxlab-source.json, the AltStore / SideStore source for the Luma iOS build.

Called by .github/workflows/hyroxlab-ios.yml after every successful build. AltStore decides whether an
update is available from the (version, buildVersion) pair, which is why the CI run number is the build
number, and it refuses a download whose build number is not the one the listing gave.

So a listing must name a file that is that build and stays that build. Each build is published under
its own tag (`build-<number>`) and the listing points there. It used to point at one rolling `latest`
file: a phone still holding the previous listing then downloaded the newer file and AltStore refused
it. `build()` rejects a download URL that does not carry the build's own tag, so that cannot come back
unnoticed.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
from pathlib import Path

TINT = "C8FF2E"  # Luma's volt accent


def release_tag(build_no: str) -> str:
    """The tag one build is published under. Never reused for another build."""
    return f"build-{build_no}"


def whats_new(build_no: str, sha: str, notes: str | None) -> str:
    """What AltStore shows under "What's New": the build, then what changed in plain words."""
    text = " ".join((notes or "").split())
    return f"Build {build_no}. {text}" if text else f"Build {build_no} from commit {sha}."


def build(repo: str, version: str, build_no: str, bundle_id: str, size: int, sha: str,
          download_url: str, notes: str | None = None) -> dict:
    owner, name = repo.split("/", 1)
    raw = f"https://raw.githubusercontent.com/{owner}/{name}/main"
    if f"/releases/download/{release_tag(build_no)}/" not in download_url:
        raise ValueError(
            f"the listing for build {build_no} must download from its own release "
            f"({release_tag(build_no)}), not {download_url}: a file that can change under a listing "
            "is refused by AltStore as soon as a newer build replaces it")
    return {
        "name": "Luma",
        "identifier": f"{bundle_id}.altstore",
        "sourceURL": f"{raw}/hyroxlab-source.json",
        "subtitle": "Luma — recovery, running, HYROX and fuelling from your strap, on your own phone.",
        "description": (
            "Personal AltStore / SideStore source for Luma: recovery, sleep, strain, running, HYROX and "
            "fuelling from a WHOOP strap you own, computed on your phone. Add this source once; every "
            "new build appears as an update."
        ),
        "iconURL": f"https://github.com/{owner}/{name}/raw/main/Design/luma-icon-1024.png",
        "website": f"https://github.com/{owner}/{name}",
        "tintColor": TINT,
        "apps": [
            {
                "name": "Luma",
                "bundleIdentifier": bundle_id,
                "developerName": owner,
                "subtitle": "Recovery, running, HYROX and fuelling from your WHOOP.",
                "localizedDescription": (
                    "Luma reads a WHOOP strap you own directly over Bluetooth and turns it into recovery, "
                    "sleep and strain each morning, GPS running with splits and spoken cues, HYROX race "
                    "mode and readiness, a food and supplement log, and a coach. Your data stays on the "
                    "phone; the coach runs on your own Anthropic key and reads only what you let it. A "
                    "personal, non-commercial build on open-source foundations, credited in the app's "
                    "About screen; not affiliated with WHOOP or HYROX."
                ),
                "iconURL": f"https://github.com/{owner}/{name}/raw/main/Design/luma-icon-1024.png",
                "tintColor": TINT,
                "category": "healthcare-fitness",
                "screenshotURLs": [],
                "versions": [
                    {
                        "version": version,
                        "buildVersion": str(build_no),
                        "date": dt.date.today().isoformat(),
                        "localizedDescription": whats_new(str(build_no), sha, notes),
                        "downloadURL": download_url,
                        "size": int(size),
                        "minOSVersion": "17.0",
                    }
                ],
                "appPermissions": {
                    "entitlements": [
                        "com.apple.developer.healthkit",
                        "com.apple.security.application-groups",
                    ],
                    "privacy": {
                        "NSBluetoothAlwaysUsageDescription": "Talks to your WHOOP strap.",
                        "NSLocationWhenInUseUsageDescription": "Records your route during outdoor runs.",
                        "NSHealthShareUsageDescription": "Reads Apple Health data you authorise.",
                        "NSHealthUpdateUsageDescription": "Writes workouts you authorise to Apple Health.",
                        "NSMotionUsageDescription": "Counts steps during a walk or run.",
                        "NSCameraUsageDescription": "Photographs a meal, label or supplement to log it.",
                        "NSMicrophoneUsageDescription": "Lets you ask the coach a question by voice.",
                        "NSSpeechRecognitionUsageDescription": "Transcribes a spoken question on the phone.",
                    },
                },
            }
        ],
    }


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--repo", required=True)
    ap.add_argument("--version", required=True)
    ap.add_argument("--build", required=True)
    ap.add_argument("--bundle-id", required=True)
    ap.add_argument("--size", required=True, type=int)
    ap.add_argument("--sha", required=True)
    ap.add_argument("--download-url", required=True,
                    help="where this build's .ipa is published; must be under its own build-<number> release")
    ap.add_argument("--notes-file", type=Path,
                    help="plain text shown as What's New for this build; optional")
    ap.add_argument("--out", required=True, type=Path)
    a = ap.parse_args()
    notes = a.notes_file.read_text(encoding="utf-8") if a.notes_file and a.notes_file.exists() else None
    source = build(a.repo, a.version, a.build, a.bundle_id, a.size, a.sha, a.download_url, notes)
    a.out.write_text(json.dumps(source, indent=2) + "\n")
    print(f"wrote {a.out}")


if __name__ == "__main__":
    main()
