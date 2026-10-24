#!/usr/bin/env bash
# Checks that an installed Sulsul can still find and verify its next update.
#
# It fetches the same feed the app reads, downloads the update it advertises and verifies, with the
# public key shipped in Info.plist, that the EdDSA signature matches the downloaded bytes. It also
# checks that the latest GitHub release is the version the feed advertises and carries both assets.
# A failure here means installed apps silently stop seeing updates.
#
# Environment (all optional):
#   REPO         owner/name, default qaws81877/sulsul
#   FEED_URL     feed to read, default the latest release's appcast.xml
#   PUBLIC_KEY   base64 Ed25519 public key; default SUPublicEDKey from Info.plist on main
#   EXPECTED_TAG tag the latest release must have; default v<short version in the feed>
#   OPENSSL      openssl 3.x binary, default openssl
#   GITHUB_TOKEN used for the GitHub API when set, to avoid anonymous rate limits

set -uo pipefail

REPO="${REPO:-qaws81877/sulsul}"
FEED_URL="${FEED_URL:-https://github.com/$REPO/releases/latest/download/appcast.xml}"
OPENSSL="${OPENSSL:-openssl}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

failures=0
ok() { printf 'ok    %s\n' "$1"; }
bad() {
    printf 'FAIL  %s\n' "$1"
    failures=$((failures + 1))
}
finish() {
    if [[ $failures -eq 0 ]]; then
        echo "Update feed is healthy."
        exit 0
    fi
    echo "Update feed check failed: $failures problem(s)."
    exit 1
}

fetch() { # fetch <url> <output file> <max seconds>
    curl --fail --silent --show-error --location --retry 3 --retry-delay 5 \
        --max-time "$3" --max-filesize 209715200 --output "$2" "$1"
}

# 1. The feed itself
if fetch "$FEED_URL" "$WORK/appcast.xml" 60; then
    ok "feed downloaded from $FEED_URL"
else
    bad "feed is not reachable: $FEED_URL"
    finish
fi

# 2. The newest item, as tab-separated validated fields
fields="$(python3 -I - "$WORK/appcast.xml" "$WORK" 2>&1 <<'PY'
import base64, os, re, sys
import xml.etree.ElementTree as ET

feed, work = sys.argv[1], sys.argv[2]
ns = {"s": "http://www.andymatuschak.org/xml-namespaces/sparkle"}
raw = open(feed, "rb").read()
# A real appcast never declares a DTD or entities; refuse one instead of expanding it.
if b"<!DOCTYPE" in raw.upper() or b"<!ENTITY" in raw.upper():
    sys.exit("feed declares a DOCTYPE or entity, which a Sparkle appcast does not need")
try:
    items = ET.fromstring(raw).findall("./channel/item")
except ET.ParseError as error:
    sys.exit(f"feed is not valid XML: {error}")
if not items:
    sys.exit("feed has no <item>")

def text(item, tag):
    node = item.find(f"s:{tag}", ns)
    return (node.text or "").strip() if node is not None else ""

# Sparkle offers the highest build number.
newest = max(items, key=lambda item: int(text(item, "version") or 0))
build, short = text(newest, "version"), text(newest, "shortVersionString")
enclosure = newest.find("enclosure")
if enclosure is None:
    sys.exit("newest item has no <enclosure>")
url = enclosure.get("url", "")
length = enclosure.get("length", "")
signature = enclosure.get("{%s}edSignature" % ns["s"], "")

problems = []
if not re.fullmatch(r"[0-9]+", build):
    problems.append(f"build number is not an integer: {build!r}")
if not re.fullmatch(r"[0-9]+(\.[0-9]+)+", short):
    problems.append(f"short version looks wrong: {short!r}")
if not url.startswith("https://"):
    problems.append(f"enclosure url is not https: {url!r}")
if not re.fullmatch(r"[0-9]+", length):
    problems.append(f"enclosure length is not an integer: {length!r}")
try:
    raw_signature = base64.b64decode(signature, validate=True)
    if len(raw_signature) != 64:
        problems.append(f"edSignature is {len(raw_signature)} bytes, expected 64")
    else:
        with open(os.path.join(work, "signature.bin"), "wb") as handle:
            handle.write(raw_signature)
except Exception:
    problems.append("edSignature is missing or not base64")
if problems:
    sys.exit("; ".join(problems))
print("\t".join([build, short, url, length]))
PY
)" || {
    bad "feed content: $fields"
    finish
}
IFS=$'\t' read -r build short url length <<<"$fields"
ok "newest item is $short (build $build)"

# 3. The download URL is the one the release process produces
expected_url="https://github.com/$REPO/releases/download/v$short/Sulsul.dmg"
if [[ "$url" == "$expected_url" ]]; then
    ok "download url is $expected_url"
else
    bad "download url is $url, expected $expected_url"
fi

# 4. The update downloads and matches the advertised size
if fetch "$url" "$WORK/Sulsul.dmg" 300; then
    actual="$(wc -c <"$WORK/Sulsul.dmg" | tr -d '[:space:]')"
    if [[ "$actual" == "$length" ]]; then
        ok "download is $actual bytes, as advertised"
    else
        bad "download is $actual bytes, the feed says $length"
    fi
else
    bad "update is not downloadable: $url"
    finish
fi

# 5. The signature verifies with the key the app ships
public_key="${PUBLIC_KEY:-}"
if [[ -z "$public_key" ]]; then
    if fetch "https://raw.githubusercontent.com/$REPO/main/VoiceInk/Info.plist" "$WORK/Info.plist" 60; then
        public_key="$(python3 -I -c 'import plistlib,sys; print(plistlib.load(open(sys.argv[1],"rb")).get("SUPublicEDKey",""))' "$WORK/Info.plist")"
    fi
fi
if [[ -z "$public_key" ]]; then
    bad "could not read SUPublicEDKey"
elif ! python3 -I - "$public_key" "$WORK/public.der" <<'PY'
import base64, sys
key = base64.b64decode(sys.argv[1], validate=True)
if len(key) != 32:
    sys.exit("public key is not 32 bytes")
# DER prefix of an Ed25519 SubjectPublicKeyInfo
open(sys.argv[2], "wb").write(bytes.fromhex("302a300506032b6570032100") + key)
PY
then
    bad "SUPublicEDKey is not a valid Ed25519 public key"
elif "$OPENSSL" pkeyutl -verify -pubin -inkey "$WORK/public.der" -keyform DER -rawin \
    -in "$WORK/Sulsul.dmg" -sigfile "$WORK/signature.bin" >"$WORK/verify.log" 2>&1; then
    ok "EdDSA signature matches the download and the app's public key"
else
    bad "EdDSA signature does not verify: $(tr '\n' ' ' <"$WORK/verify.log")"
fi

# 6. The latest release is that version and carries both assets
api_headers=(--header "Accept: application/vnd.github+json")
[[ -n "${GITHUB_TOKEN:-}" ]] && api_headers+=(--header "Authorization: Bearer $GITHUB_TOKEN")
if curl --fail --silent --show-error --location --retry 3 --retry-delay 5 --max-time 60 \
    "${api_headers[@]}" --output "$WORK/release.json" \
    "https://api.github.com/repos/$REPO/releases/latest"; then
    release="$(python3 -I - "$WORK/release.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
names = ",".join(sorted(asset["name"] for asset in data.get("assets", [])))
print("\t".join([data.get("tag_name", ""), str(data.get("draft")), str(data.get("prerelease")), names]))
PY
)"
    IFS=$'\t' read -r tag draft prerelease assets <<<"$release"
    expected_tag="${EXPECTED_TAG:-v$short}"
    [[ "$tag" == "$expected_tag" ]] && ok "latest release is $tag" \
        || bad "latest release is $tag, the feed advertises $expected_tag"
    [[ "$draft" == "False" && "$prerelease" == "False" ]] && ok "latest release is a final release" \
        || bad "latest release is draft=$draft prerelease=$prerelease"
    [[ ",$assets," == *",Sulsul.dmg,"* && ",$assets," == *",appcast.xml,"* ]] \
        && ok "release has Sulsul.dmg and appcast.xml" \
        || bad "release assets are: $assets"
else
    bad "could not read the latest release from the GitHub API"
fi

finish
