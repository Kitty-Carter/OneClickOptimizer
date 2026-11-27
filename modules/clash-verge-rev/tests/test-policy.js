const assert=require("assert"),fs=require("fs"),vm=require("vm"),path=require("path"),crypto=require("crypto");
const template=fs.readFileSync(path.join(__dirname,"../rust-node-quality/src/policy-template.js"),"utf8");
const ctx={};vm.createContext(ctx);
vm.runInContext("function ocoBaseMain(c){return c;}\n"+template,ctx);
for(const s of ["","abc","a".repeat(1000)])assert.equal(ctx.ocoSha256(s),crypto.createHash("sha256").update(s).digest("hex"));
const a={name:"日本😀",type:"vless",server:"example.test",port:443,uuid:"synthetic",tls:true,opts:{z:[1,false,null],a:"abc"}};
const b={...a,name:"b",port:444};
const fingerprint=n=>crypto.createHash("sha256").update(ctx.ocoCanonical(n,0)).digest("hex");
const created=Math.floor(Date.now()/1000);
const spec={created,expires:created+86400,parent:"main",nodes:[[a.name,fingerprint(a)],[b.name,fingerprint(b)]],groups:[
 {name:"OCO-实测候选",type:"select",proxies:[a.name,b.name],"empty-fallback":"REJECT"},
 {name:"OCO-低延迟优选",type:"url-test",proxies:[a.name,b.name],url:"https://cp.cloudflare.com/generate_204",interval:1800,tolerance:100,lazy:true,"expected-status":204,"empty-fallback":"REJECT"},
 {name:"OCO-下载候选",type:"select",proxies:[b.name],"empty-fallback":"REJECT"}
]};
vm.runInContext("const OCO_POLICY="+JSON.stringify(spec),ctx);
const copy=x=>JSON.parse(JSON.stringify(x));
const cfg={proxies:[a,b],"proxy-groups":[{name:"main",type:"select",proxies:["DIRECT",a.name,b.name]},{name:"AI-固定出口",type:"select",proxies:[a.name]}],rules:["MATCH,main"]};
const out=ctx.main(copy(cfg));
assert.equal(out["proxy-groups"].length,5);
assert.deepEqual(out.rules,cfg.rules);assert.deepEqual(out.proxies,cfg.proxies);
assert.deepEqual(out["proxy-groups"][0].proxies.slice(0,3),cfg["proxy-groups"][0].proxies);
assert.deepEqual(out["proxy-groups"][1],cfg["proxy-groups"][1]);
assert.equal(JSON.stringify(ctx.main(copy(out))),JSON.stringify(out));
const mutate=copy(cfg);mutate.proxies[0].uuid="changed";
const result=ctx.main(mutate);assert.equal(result["proxy-groups"].length,4);
assert.ok(!result["proxy-groups"].some(g=>g.name==="OCO-低延迟优选"));
assert.ok(result["proxy-groups"].filter(g=>g.name.startsWith("OCO-")).every(g=>!g.proxies.includes(a.name)));
const duplicate=copy(cfg);duplicate.proxies.push(copy(a));assert.ok(ctx.main(duplicate)["proxy-groups"].filter(g=>g.name.startsWith("OCO-")).every(g=>!g.proxies.includes(a.name)));
const collision=copy(cfg);collision["proxy-groups"].push({name:"OCO-实测候选",type:"select",proxies:["DIRECT"]});
assert.equal(JSON.stringify(ctx.main(copy(collision))),JSON.stringify(collision));
vm.runInContext("OCO_POLICY.expires=1",ctx);
assert.equal(JSON.stringify(ctx.main(copy(cfg))),JSON.stringify(cfg));
console.log("POLICY_TEMPLATE_TESTS_PASS");
