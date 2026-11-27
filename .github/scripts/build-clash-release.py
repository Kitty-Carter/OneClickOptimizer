import pathlib,subprocess,hashlib,zipfile,sys,argparse
p=argparse.ArgumentParser();p.add_argument("--ref",required=True);p.add_argument("--output",required=True);a=p.parse_args()
root=pathlib.Path(__file__).resolve().parents[2]
module="modules/clash-verge-rev/"
files=["Check.bat","Optimize.bat","SelfTest.bat","Monitor.bat","Monitor-Lite.bat","Optimize-Clash.ps1","Monitor-Clash.ps1","Monitor.cs","manifest.json","README.md","START-HERE.txt","presets/Merge.yaml","presets/Script.js","tests/test-presets.js"]
out=pathlib.Path(a.output);out.mkdir(parents=True,exist_ok=True)
name="Clash-Verge-Rev-OneClick-Optimizer-Windows.zip";zip_path=out/name
assert not zip_path.exists(),"Refuse to overwrite existing ZIP"
def blob(path):return subprocess.check_output(["git","show",a.ref+":"+path],cwd=root)
with zipfile.ZipFile(zip_path,"w",compression=zipfile.ZIP_DEFLATED) as z:
 for f in files+["LICENSE"]:
  data=blob("LICENSE" if f=="LICENSE" else module+f)
  info=zipfile.ZipInfo(f,date_time=(2026,1,1,0,0,0));info.compress_type=zipfile.ZIP_DEFLATED;z.writestr(info,data)
with zipfile.ZipFile(zip_path) as z:
 assert z.testzip() is None and set(z.namelist())==set(files+["LICENSE"])
 for f in z.namelist():assert z.read(f)==blob("LICENSE" if f=="LICENSE" else module+f)
(out/"SHA256SUMS.txt").write_text(hashlib.sha256(zip_path.read_bytes()).hexdigest()+"  "+name+"\n",encoding="ascii")
print("ALLOWLIST ZIP verified",len(files)+1,"files",zip_path.stat().st_size,"bytes")
