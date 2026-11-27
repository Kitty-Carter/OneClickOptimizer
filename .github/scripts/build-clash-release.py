import pathlib,subprocess,hashlib,zipfile,argparse,tempfile,os,json
p=argparse.ArgumentParser();p.add_argument("--ref",required=True);p.add_argument("--output",required=True);a=p.parse_args()
root=pathlib.Path(__file__).resolve().parents[2]
module="modules/clash-verge-rev/"
files=["Check.bat","Optimize.bat","SelfTest.bat","Monitor.bat","Monitor-Lite.bat","Native-Monitor.bat","Native-Monitor-Lite.bat","Restore.bat","Diagnose.bat","Inspect-Exit.bat","Diagnose-Clash.ps1","Optimize-Clash.ps1","Monitor-Clash.ps1","Monitor.cs","manifest.json","README.md","START-HERE.txt","presets/Merge.yaml","presets/Script.js","tests/test-presets.js","native-monitor/Cargo.toml","native-monitor/Cargo.lock","native-monitor/src/main.rs","native-monitor/.gitignore"]
out=pathlib.Path(a.output).resolve();out.mkdir(parents=True,exist_ok=True)
name="Clash-Verge-Rev-OneClick-Optimizer-Windows.zip";zip_path=out/name
if zip_path.exists():raise SystemExit("Refuse to overwrite existing ZIP")
def blob(path):return subprocess.check_output(["git","show",a.ref+":"+path],cwd=root)
payload={f:blob(module+f) for f in files}
payload["LICENSE"]=blob("LICENSE")
with tempfile.TemporaryDirectory(prefix="oco-native-build-") as tmp:
 t=pathlib.Path(tmp)
 for f,data in payload.items():
  if f.startswith("native-monitor/"):
   dest=t/f;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(data)
 crate=t/"native-monitor"
 env=os.environ.copy();env["CARGO_TARGET_DIR"]=str(t/"target")
 subprocess.run(["cargo","build","--release","--locked","--target","x86_64-pc-windows-msvc"],cwd=crate,env=env,check=True)
 binary=t/"target/x86_64-pc-windows-msvc/release/oco-clash-monitor.exe"
 if not binary.is_file():raise RuntimeError("Native build output missing")
 payload["bin/oco-clash-monitor.exe"]=binary.read_bytes()
 meta=json.loads(subprocess.check_output(["cargo","metadata","--locked","--format-version","1"],cwd=crate,env=env))
 for pkg in meta["packages"]:
  if pkg["name"]=="oco-clash-monitor":continue
  dep=pathlib.Path(pkg["manifest_path"]).parent
  licenses=[x for x in dep.iterdir() if x.is_file() and x.name.upper().startswith(("LICENSE","COPYING","NOTICE"))]
  if not licenses:raise RuntimeError("Missing license for "+pkg["name"])
  for f in licenses:payload["third-party/"+pkg["name"]+"-"+pkg["version"]+"/"+f.name]=f.read_bytes()
with zipfile.ZipFile(zip_path,"x",compression=zipfile.ZIP_DEFLATED) as z:
 for f,data in sorted(payload.items()):
  info=zipfile.ZipInfo(f,date_time=(2026,1,1,0,0,0));info.compress_type=zipfile.ZIP_DEFLATED;z.writestr(info,data)
with zipfile.ZipFile(zip_path) as z:
 assert z.testzip() is None and set(z.namelist())==set(payload)
 for f,data in payload.items():assert z.read(f)==data
(out/"SHA256SUMS.txt").write_text(hashlib.sha256(zip_path.read_bytes()).hexdigest()+"  "+name+"\n",encoding="ascii")
print("ALLOWLIST ZIP verified",len(payload),"files",zip_path.stat().st_size,"bytes")
