import argparse, hashlib, pathlib, subprocess
p = argparse.ArgumentParser()
p.add_argument("--ref", required=True)
p.add_argument("--output", required=True)
a = p.parse_args()
root = pathlib.Path(__file__).resolve().parents[2]
name = "Clash-OneClick-Config.bat"
data = subprocess.check_output(["git", "show", a.ref + ":modules/clash-verge-rev/" + name], cwd=root)
out = pathlib.Path(a.output).resolve()
out.mkdir(parents=True, exist_ok=True)
with (out / name).open("xb") as f:
    f.write(data)
assert (out / name).read_bytes() == data
print("Single BAT", len(data), "bytes", hashlib.sha256(data).hexdigest())
