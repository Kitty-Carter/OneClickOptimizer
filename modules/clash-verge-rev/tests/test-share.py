"""Verify only public payloads, without reading user data."""
import pathlib, re, base64, hashlib, json, subprocess
p = pathlib.Path(__file__).resolve().parents[1] / "Clash-OneClick-Config.bat"
s = p.read_text(encoding="utf-8")
assert not re.search(r"[A-Za-z]:\\Users\\|zyp31|private-download-candidate", s)
def payload(n):
    return base64.b64decode(re.search(r"\$"+n+r"=\[Convert\]::FromBase64String\('([^']+)'\)",s)[1],validate=True)
m=payload("merge");j=payload("script")
assert s.count("FromBase64String(")==2
assert hashlib.sha256(m).hexdigest()=="49da5e3bd61cde526919741fafdf4ded79f508ecf01dd32db35aec1ccac88208"
assert hashlib.sha256(j).hexdigest()=="5d26fc29b2032cfa77dd9fec24b60534dc8a2e3e7d30bef47cc24736ba99d917"
js=r"""
const fs=require('fs'),vm=require('vm');
const code=fs.readFileSync(0,'utf8'),c={};vm.createContext(c);vm.runInContext(code,c);
const src={proxies:[{name:'sample',type:'socks5',server:'127.0.0.1',port:1}], 'proxy-groups':[{name:'ordinary',type:'select',proxies:['sample']}], rules:['MATCH,ordinary','MATCH,ordinary'],dns:{'enhanced-mode':'fake-ip'}};
const ai='AI-\u56fa\u5b9a\u51fa\u53e3',out=c.main(src,'synthetic');
if(out.rules.length!==27||out.rules.slice(0,26).some(x=>!x.endsWith(','+ai)))throw Error('AI prefix');
const domains=out.rules.slice(0,26).map(x=>x.split(',')[1]);if(new Set(domains).size!==26||domains.includes('google.com')||domains.includes('googleapis.com'))throw Error('AI domain scope');
for(const d of ['chatgpt.com','claude.ai','anthropic.com','gemini.google.com','generativelanguage.googleapis.com','notebooklm.google.com','githubcopilot.com'])if(!domains.includes(d))throw Error('missing '+d);
if(out['proxy-groups'][0].name!==ai||out['proxy-groups'][0]['empty-fallback']!=='REJECT'||out['proxy-groups'][0].proxies.join()!=='sample')throw Error('AI group');
if(JSON.stringify(out)!==JSON.stringify(c.main(out,'synthetic')))throw Error('non-idempotent');
console.log('PUBLIC PAYLOAD AI RULES 26/26; idempotent');
"""
subprocess.run(["node","-e",js],input=j,check=True)
print("PUBLIC PAYLOAD HASHES AND PRIVACY ALLOWLIST PASS")
