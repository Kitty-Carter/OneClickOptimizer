"""Build two user ZIPs from an explicit tracked-file allowlist."""
from pathlib import Path
from zipfile import ZipFile, ZipInfo, ZIP_DEFLATED
import hashlib
import subprocess

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "dist"
OUT.mkdir(exist_ok=True)
MODULE = "modules/positron/"
module_names = ["Optimize-Positron.ps1", "manifest.json", "一键优化.bat",
                "仅检查不修改.bat", "使用说明.md", "START-HERE.txt"]
full = ["LICENSE", "README.md", "README.zh-CN.md", "START-HERE.txt",
        "启动全家桶.bat", "OneClickOptimizer.ps1", "core/ModuleCatalog.psm1",
        "AGENTS.md", "CHANGELOG.md", "CONTRIBUTING.md", "tests/Test-Positron.ps1",
        "docs/MODULE-CONTRACT.md", "docs/ROADMAP.md", "docs/VALIDATION.md",
        "docs/assets/banner.svg", "docs/assets/logo.svg",
        "docs/RELEASE-NOTES-v0.1.0-alpha.1.md"] + [MODULE+n for n in module_names]
tracked = set(subprocess.check_output(
    ["git", "ls-tree", "-r", "-z", "--name-only", "HEAD"], cwd=ROOT
).decode("utf-8").split("\x00"))

def build(name, mapping):
    path = OUT / name
    with ZipFile(path, "w", compression=ZIP_DEFLATED, compresslevel=9) as z:
        for src, dst in sorted(mapping):
            if src not in tracked:
                raise RuntimeError(f"Not tracked: {src}")
            info = ZipInfo(dst, date_time=(2026, 11, 26, 0, 0, 0))
            info.compress_type = ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            z.writestr(info, (ROOT / src).read_bytes(), compresslevel=9)
    with ZipFile(path) as z:
        assert z.testzip() is None
        assert set(z.namelist()) == {dst for _, dst in mapping}
        for src, dst in mapping:
            assert z.read(dst) == (ROOT / src).read_bytes()
    print(f"Verified {name}: {len(mapping)} files")
    return path

packages = [
    build("OneClickOptimizer-Windows.zip", [(n,n) for n in full]),
    build("Positron-Optimizer-Windows.zip", [(MODULE+n,n) for n in module_names]+[("LICENSE","LICENSE")]),
]
with (OUT / "SHA256SUMS.txt").open("w", encoding="ascii", newline="\n") as f:
    f.write("".join(f"{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}\n" for p in packages))
