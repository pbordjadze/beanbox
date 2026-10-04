#!/usr/bin/env python3
"""Writes the SideStore/AltStore source (JSON) listing the latest IPA builds.

    ci/sidestore_source.py <BeanBox.app> <icon-url>  > source.json

Versions come from this repository's `build-<n>` releases that carry an .ipa asset (newest
first); privacy usage descriptions come from the built app's Info.plist, so the source always
declares exactly what the app asks for. Needs `gh` with GH_TOKEN and GITHUB_REPOSITORY.
"""
import json
import os
import plistlib
import subprocess
import sys

KEEP = 5
TINT = "#E2542C"

app_path, icon_url = sys.argv[1], sys.argv[2]
repo = os.environ["GITHUB_REPOSITORY"]
info = plistlib.load(open(os.path.join(app_path, "Info.plist"), "rb"))

releases = json.loads(subprocess.run(
    ["gh", "api", f"repos/{repo}/releases?per_page=30"], check=True, capture_output=True, text=True).stdout)
versions = []
for r in releases:
    tag = r["tag_name"]
    ipa = next((a for a in r["assets"] if a["name"].endswith(".ipa")), None)
    if not tag.startswith("build-") or ipa is None:
        continue
    build = tag.removeprefix("build-")
    versions.append({
        "version": f"1.0.{build}",
        "buildVersion": build,
        "date": r["published_at"] or r["created_at"],
        "localizedDescription": (r["body"] or "").strip() or f"Build {build}",
        "downloadURL": ipa["browser_download_url"],
        "size": ipa["size"],
        "minOSVersion": info.get("MinimumOSVersion", "26.0"),
    })
versions.sort(key=lambda v: int(v["buildVersion"]), reverse=True)
versions = versions[:KEEP]
if not versions:
    sys.exit("no build-* release with an .ipa asset")
latest = versions[0]

description = (
    "Match origami paper to jelly bean flavours. Measure sheets and beans from photos, get the "
    "best sheet for every flavour, and split look-alike beans into groups, entirely on device.")
app = {
    "name": info.get("CFBundleDisplayName", "Beanbox"),
    "bundleIdentifier": info["CFBundleIdentifier"],
    "developerName": repo.split("/")[0],
    "subtitle": "Paper for every jelly bean",
    "localizedDescription": description,
    "iconURL": icon_url,
    "tintColor": TINT,
    "category": "utilities",
    "versions": versions,
    # Legacy fields for clients that predate `versions`.
    "version": latest["version"],
    "versionDate": latest["date"],
    "versionDescription": latest["localizedDescription"],
    "downloadURL": latest["downloadURL"],
    "size": latest["size"],
    "appPermissions": {
        "entitlements": [],
        "privacy": {k: v for k, v in sorted(info.items()) if k.startswith("NS") and k.endswith("UsageDescription")},
    },
}
source = {
    "name": "Beanbox (CI builds)",
    "identifier": f"{info['CFBundleIdentifier']}.source",
    "subtitle": "Automatic builds of the main branch",
    "iconURL": icon_url,
    "website": f"https://github.com/{repo}",
    "tintColor": TINT,
    "apps": [app],
    "news": [],
}
json.dump(source, sys.stdout, indent=2)
print()
