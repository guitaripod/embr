#!/usr/bin/env python3
"""Put the iOS 27 product page creative, the Header and the Search Results asset, on every localization of an
editable iOS version.

store/creative/<locale>/header.png (scripts/store-panels.py --creative) is the universal 5244x2950 image Apple
accepts for both placements. Each file is uploaded to the app's asset library once, then assigned to its
localization: an existing placement (a new version copies its predecessor's) is swapped for the new image, a missing
one is created. A locale without its own file shows the primary locale's. Every placement is read back and must be
active.

A run that stops part way (the asset library can take minutes to process a large image; raise ASC_UPLOAD_TIMEOUT)
picks up again with the locale it stopped at as the second argument.

Usage: python3 scripts/asc-creative.py <marketing-version> [first-locale]
"""
import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CREATIVE = os.path.join(ROOT, "store/creative")
APP = "6784940198"
KINDS = {"header": "PRODUCT_PAGE_HEADER_ASSET", "search": "APP_STORE_SEARCH_RESULTS_ASSET"}


def asc(*args):
    result = subprocess.run(["asc", *args, "--output", "json"], capture_output=True, text=True)
    if result.returncode != 0:
        sys.exit(f"asc {' '.join(args)} failed:\n{result.stdout[-1500:]}\n{result.stderr[-1500:]}")
    body = result.stdout[result.stdout.find("{"):]
    return json.loads(body) if body.strip().startswith("{") else {}


def version_id(marketing):
    for row in asc("versions", "list", "--app", APP, "--platform", "IOS").get("data", []):
        if row["attributes"]["versionString"] == marketing:
            return row["id"]
    sys.exit(f"no iOS version {marketing}")


def source_file(locale):
    """The locale's universal image, which serves the Header and the Search Results placement alike."""
    path = os.path.join(CREATIVE, locale, "header.png")
    return path if os.path.exists(path) else None


def main():
    if len(sys.argv) not in (2, 3):
        sys.exit("usage: asc-creative.py <marketing-version> [first-locale]")
    first = sys.argv[2] if len(sys.argv) == 3 else ""
    version = version_id(sys.argv[1])
    localizations = {row["attributes"]["locale"]: row["id"]
                     for row in asc("localizations", "list", "--version", version).get("data", [])}
    uploaded = {}
    failed = []
    for locale, localization in sorted(localizations.items()):
        if locale < first:
            continue
        for kind, placement_type in KINDS.items():
            path = source_file(locale)
            if path is None:
                print(f"  {locale} {kind}: no file, shows the primary locale's", flush=True)
                continue
            if path not in uploaded:
                receipt = asc("asset-library", "images", "upload", "--library-id", APP,
                              "--file", path, "--category", "CREATIVE_ASSETS")
                uploaded[path] = receipt["imageId"]
            image = uploaded[path]
            existing = [row for row in asc("localizations", "placements", "list",
                                           "--localization-id", localization).get("data", [])
                        if row["attributes"]["placementType"] == placement_type]
            if existing:
                asc("localizations", "placements", "swap", "--localization-id", localization,
                    "--image-id", image, "--placement-type", placement_type,
                    "--placement-id", existing[0]["id"], "--confirm")
                verb = "swapped"
            else:
                asc("localizations", "placements", "create", "--localization-id", localization,
                    "--image-id", image, "--placement-type", placement_type,
                    "--placement-group", "DEFAULT_PROFILE")
                verb = "created"
            now = [row for row in asc("localizations", "placements", "list",
                                      "--localization-id", localization).get("data", [])
                   if row["attributes"]["placementType"] == placement_type]
            if len(now) != 1 or now[0]["attributes"]["state"] != "ACTIVE":
                failed.append(f"{locale} {kind}: {len(now)} placements")
            print(f"  {locale} {kind}: {verb}", flush=True)
    if failed:
        sys.exit("!! " + "\n!! ".join(failed))
    print("all creative placements verified", flush=True)


if __name__ == "__main__":
    main()
