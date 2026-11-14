#!/usr/bin/env python3
"""Write hyroxlab-source.json, the AltStore / SideStore source for the HYROX Lab iOS build.

Called by .github/workflows/hyroxlab-ios.yml after every successful build. The download URL is the
rolling `latest` release, so it never changes; AltStore decides whether an update is available from
the (version, buildVersion) pair, which is why the CI run number is the build number.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
from pathlib import Path

TINT = "C8FF2E"  # HYROX Lab volt accent


def build(repo: str, version: str, build_no: str, bundle_id: str, size: int, sha: str) -> dict:
    owner, name = repo.split("/", 1)
    raw = f"https://raw.githubusercontent.com/{owner}/{name}/main"
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
                    "mode and readiness, a food and supplement log, and a coach. Everything stays on the "
                    "phone. A personal, non-commercial build on open-source foundations, credited in the "
                    "app's About screen; not affiliated with WHOOP or HYROX."
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
                        "localizedDescription": f"Build {build_no} from commit {sha}.",
                        "downloadURL": f"https://github.com/{owner}/{name}/releases/download/latest/HYROXLab-ios.ipa",
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
    ap.add_argument("--out", required=True, type=Path)
    a = ap.parse_args()
    a.out.write_text(json.dumps(build(a.repo, a.version, a.build, a.bundle_id, a.size, a.sha), indent=2) + "\n")
    print(f"wrote {a.out}")


if __name__ == "__main__":
    main()
