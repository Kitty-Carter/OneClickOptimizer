"""One-time migration of the first preview's public asset names."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile

REPO = "Kitty-Carter/OneClickOptimizer"
TAG = "v0.1.0-alpha.1"
RELEASE_ID = 458819565
TITLE = "Positron 一键优化工具 v0.1.0-alpha.1 | Windows Preview"
ROOT = Path(__file__).resolve().parents[2]
spec = [
    (793782042, "Positron-Optimizer-Windows.zip", "Positron-一键优化工具-Windows.zip",
     "e2d49b424b17b133499cda407a53bcc9352e618ed115f23ca025554cec7d9484"),
    (793782038, "OneClickOptimizer-Windows.zip", "OneClickOptimizer-全家桶预览版-Windows.zip",
     "0a08c700efe49057b23042b0ee3ecc4456b4f4652f1d6611def18f5c58723ffd"),
]
OLD_CHECKSUM_ID = 793782040
STAGED = "SHA256SUMS-pos-preview.tmp.txt"
OLD_NAME = "SHA256SUMS-before-rename.txt"
CHECKSUM = "SHA256SUMS.txt"

def gh(*args):
    return subprocess.check_output(["gh", *args], text=True, encoding="utf-8")

def api(suffix, *args):
    return json.loads(gh("api", f"repos/{REPO}/{suffix}", *args))

def assets():
    return api(f"releases/{RELEASE_ID}/assets?per_page=100")

def rename(asset_id, name):
    a = api(f"releases/assets/{asset_id}", "--method", "PATCH", "-f", f"name={name}")
    if a["name"] != name:
        raise RuntimeError(f"Asset name differs from requested name: {a['name']}")
    return a

def sha(data):
    return hashlib.sha256(data).hexdigest()

def download(name, directory):
    gh("release", "download", TAG, "--repo", REPO, "--pattern", name, "--dir", str(directory))
    return (directory / name).read_bytes()

assert os.environ.get("GITHUB_REPOSITORY") == REPO
r = api(f"releases/tags/{TAG}")
assert r["id"] == RELEASE_ID and r["prerelease"] and not r["draft"] and not r.get("immutable")
expected = "".join(f"{digest}  {new}\n" for _, _, new, digest in spec).encode("utf-8")
with tempfile.TemporaryDirectory() as temp:
    d = Path(temp)
    before = {a["id"]: a for a in assets()}
    # Verify the actual published ZIP bytes before any changes.
    for asset_id, old, new, digest in spec:
        a = before[asset_id]
        assert a["name"] in (old, new)
        assert sha(download(a["name"], d)) == digest
    existing = {a["name"]: a for a in before.values()}
    current = existing.get(CHECKSUM)
    canonical = current and current["id"] != OLD_CHECKSUM_ID
    if canonical:
        assert download(CHECKSUM, d) == expected
        new_id = current["id"]
    else:
        staged = existing.get(STAGED)
        if not staged:
            (d / STAGED).write_bytes(expected)
            gh("release", "upload", TAG, str(d / STAGED), "--repo", REPO)
            staged = next(a for a in assets() if a["name"] == STAGED)
            (d / STAGED).unlink()
        assert download(STAGED, d) == expected
        new_id = staged["id"]
    # Rename existing ZIP objects; no re-upload and no ZIP byte changes.
    for asset_id, old, new, digest in spec:
        a = {a["id"]: a for a in assets()}[asset_id]
        if a["name"] != new:
            rename(asset_id, new)
        assert {a["id"]: a for a in assets()}[asset_id]["name"] == new
    if not canonical:
        old = {a["id"]: a for a in assets()}.get(OLD_CHECKSUM_ID)
        if old and old["name"] == CHECKSUM:
            rename(OLD_CHECKSUM_ID, OLD_NAME)
        rename(new_id, CHECKSUM)
    with tempfile.TemporaryDirectory() as verify_temp:
        vd = Path(verify_temp)
        assert download(CHECKSUM, vd) == expected
        for asset_id, old, new, digest in spec:
            assert sha(download(new, vd)) == digest
    gh("release", "edit", TAG, "--repo", REPO, "--title", TITLE,
       "--notes-file", str(ROOT / "docs/RELEASE-NOTES-v0.1.0-alpha.1.md"), "--prerelease")
    # Remove only the superseded checksum, after verification of the replacement.
    old = {a["id"]: a for a in assets()}.get(OLD_CHECKSUM_ID)
    if old:
        assert old["name"] == OLD_NAME
        gh("api", f"repos/{REPO}/releases/assets/{OLD_CHECKSUM_ID}", "--method", "DELETE")
    final = assets()
    assert {a["name"] for a in final} == {spec[0][2], spec[1][2], CHECKSUM}
    assert api(f"releases/tags/{TAG}")["name"] == TITLE
    print("Release title, three asset names and downloaded ZIP/checksum bytes verified.")
