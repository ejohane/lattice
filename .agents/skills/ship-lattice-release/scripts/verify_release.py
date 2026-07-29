#!/usr/bin/env python3

import argparse
import json
import subprocess
import sys
import urllib.request
import xml.etree.ElementTree as ElementTree
from pathlib import PurePosixPath
from urllib.parse import urlparse


REPOSITORY = "ejohane/lattice"
SPARKLE_NAMESPACE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
APPCASTS = {
    "lattice-macos-appcast-darwin-arm64.xml": "lattice-macos-app-darwin-arm64.zip",
    "lattice-macos-appcast-darwin-x64.xml": "lattice-macos-app-darwin-x64.zip",
}
REQUIRED_ASSETS = set(APPCASTS) | set(APPCASTS.values()) | {
    "lattice-macos-app-darwin-arm64.zip.sha256",
    "lattice-macos-app-darwin-x64.zip.sha256",
}


def command(*arguments):
    result = subprocess.run(
        arguments,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    return result.stdout.strip()


def fetch(url):
    request = urllib.request.Request(url, headers={"User-Agent": "lattice-release-verifier"})
    with urllib.request.urlopen(request, timeout=30) as response:
        return response.read()


def parse_appcast(data, expected_version, expected_archive):
    root = ElementTree.fromstring(data)
    version = root.findtext(f".//{{{SPARKLE_NAMESPACE}}}shortVersionString")
    enclosure = root.find(".//enclosure")
    if enclosure is None:
        raise ValueError("appcast has no enclosure")

    archive_url = enclosure.attrib.get("url", "")
    archive_name = PurePosixPath(urlparse(archive_url).path).name
    if version != expected_version:
        raise ValueError(f"appcast version {version!r} does not match {expected_version!r}")
    if archive_name != expected_archive:
        raise ValueError(f"appcast archive {archive_name!r} does not match {expected_archive!r}")

    return {"version": version, "archiveURL": archive_url}


def release_json(tag=None):
    arguments = [
        "gh",
        "release",
        "view",
    ]
    if tag:
        arguments.append(tag)
    arguments.extend(
        [
            "--repo",
            REPOSITORY,
            "--json",
            "tagName,name,publishedAt,url,body,isDraft,isPrerelease,assets",
        ]
    )
    return json.loads(command(*arguments))


def verify(tag, expected_commit):
    commit = command("git", "rev-list", "-n", "1", tag)
    if expected_commit and commit.lower() != expected_commit.lower():
        raise ValueError(f"tag {tag} points to {commit}, not {expected_commit}")

    release = release_json(tag)
    if release["tagName"] != tag:
        raise ValueError(f"GitHub returned {release['tagName']} for {tag}")
    if release["isDraft"] or release["isPrerelease"] or not release["publishedAt"]:
        raise ValueError(f"release {tag} is not a published stable release")

    assets = {asset["name"]: asset for asset in release["assets"]}
    missing_assets = sorted(REQUIRED_ASSETS - set(assets))
    if missing_assets:
        raise ValueError(f"release {tag} is missing assets: {', '.join(missing_assets)}")

    unavailable_assets = sorted(
        name for name in REQUIRED_ASSETS if assets[name].get("state") != "uploaded"
    )
    if unavailable_assets:
        raise ValueError(f"release {tag} has unavailable assets: {', '.join(unavailable_assets)}")

    version = tag.removeprefix("v")
    exact_appcasts = {}
    for appcast_name, archive_name in APPCASTS.items():
        exact_appcasts[appcast_name] = parse_appcast(
            fetch(assets[appcast_name]["url"]), version, archive_name
        )

    latest_release = release_json()
    latest_feed = {"tag": latest_release["tagName"], "status": "superseded"}
    if latest_release["tagName"] == tag:
        live_appcasts = {}
        for appcast_name, archive_name in APPCASTS.items():
            url = f"https://github.com/{REPOSITORY}/releases/latest/download/{appcast_name}"
            live_appcasts[appcast_name] = parse_appcast(fetch(url), version, archive_name)
        latest_feed = {"tag": tag, "status": "verified-current", "appcasts": live_appcasts}

    return {
        "version": version,
        "tag": tag,
        "commit": commit,
        "releaseURL": release["url"],
        "publishedAt": release["publishedAt"],
        "releaseNotes": release["body"],
        "assets": sorted(REQUIRED_ASSETS),
        "exactAppcasts": exact_appcasts,
        "liveUpdaterFeed": latest_feed,
    }


def main():
    parser = argparse.ArgumentParser(description="Verify a published Lattice macOS release")
    parser.add_argument("tag", help="release tag, for example v1.48.0")
    parser.add_argument("--commit", help="expected release commit SHA")
    arguments = parser.parse_args()

    try:
        result = verify(arguments.tag, arguments.commit)
    except (ValueError, OSError, subprocess.CalledProcessError, ElementTree.ParseError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
