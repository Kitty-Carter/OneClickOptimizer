
// OCO policy candidate extension. No rules modified by this wrapper.
// Groups are conditional on exact node object fingerprints. No trust or performance guarantee.
function ocoCanonical(x,depth) {
  if(depth>20)throw new Error("depth");
  function str(v){let t="s";for(let i=0;i<v.length;i++)t+=("0000"+v.charCodeAt(i).toString(16)).slice(-4);return t+";";}
  if(x===null)return "z;";
  if(typeof x==="string")return str(x);
  if(typeof x==="boolean")return x?"b1;":"b0;";
  if(typeof x==="number"&&Number.isSafeInteger(x))return "n"+String(x)+";";
  if(Array.isArray(x))return "a["+x.map(v=>ocoCanonical(v,depth+1)).join("")+"]";
  if(x&&typeof x==="object"){
    return "m{"+Object.keys(x).sort().map(k=>str(k)+ocoCanonical(x[k],depth+1)).join("")+"}";
  }
  throw new Error("unsupported");
}
function ocoSha256(s){
  const K=[0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2];
  let h=[0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19], b=[];
  if(s.length>1048576)throw new Error("large");
  for(let i=0;i<s.length;i++){let n=s.charCodeAt(i);if(n>127)throw new Error("not ascii");b.push(n);}
  const bits=b.length*8;b.push(128);while(b.length%64!==56)b.push(0);
  b.push(0,0,0,0,(bits>>>24)&255,(bits>>>16)&255,(bits>>>8)&255,bits&255);
  const R=(x,n)=>(x>>>n)|(x<<(32-n));
  for(let off=0;off<b.length;off+=64){
    let w=new Array(64);
    for(let j=0;j<16;j++){let i=off+j*4;w[j]=(b[i]<<24)|(b[i+1]<<16)|(b[i+2]<<8)|b[i+3];}
    for(let j=16;j<64;j++){let a=w[j-15],z=w[j-2];w[j]=(w[j-16]+(R(a,7)^R(a,18)^(a>>>3))+w[j-7]+(R(z,17)^R(z,19)^(z>>>10)))|0;}
    let [a,c,d,e,f,g,i,j]=h;
    for(let t=0;t<64;t++){let t1=(j+(R(f,6)^R(f,11)^R(f,25))+((f&g)^((~f)&i))+K[t]+w[t])|0;
      let t2=((R(a,2)^R(a,13)^R(a,22))+((a&c)^(a&d)^(c&d)))|0;
      j=i;i=g;g=f;f=(e+t1)|0;e=d;d=c;c=a;a=(t1+t2)|0;}
    let v=[a,c,d,e,f,g,i,j];h=h.map((x,k)=>(x+v[k])|0);
  }
  return h.map(x=>("00000000"+(x>>>0).toString(16)).slice(-8)).join("");
}
function main(config, profileName) {
  // The original v2.3 base is used verbatim except for its function name.
  config=ocoBaseMain(config,profileName);
  if(!config||!Array.isArray(config.proxies)||!Array.isArray(config["proxy-groups"]))return config;
  if(Date.now()<OCO_POLICY.created*1000||Date.now()>OCO_POLICY.expires*1000)return config;
  const groups=config["proxy-groups"], nodes=config.proxies;
  const parent=groups.filter(g=>g&&g.name===OCO_POLICY.parent);
  if(parent.length!==1||parent[0].type!=="select"||!Array.isArray(parent[0].proxies)||parent[0].proxies.length===0)return config;
  const used=new Set(groups.map(g=>g&&g.name).concat(nodes.map(p=>p&&p.name),Object.keys(config["proxy-providers"]||{})));
  // If any collision exists, fail closed instead of overriding foreign groups.
  if(OCO_POLICY.groups.some(g=>used.has(g.name)))return config;
  const valid=new Set();
  for(const item of OCO_POLICY.nodes){
    const matches=nodes.filter(n=>n&&n.name===item[0]);
    if(matches.length!==1)continue;
    try{if(ocoSha256(ocoCanonical(matches[0],0))===item[1])valid.add(item[0]);}catch(_){}
  }
  const additions=[];
  for(const g of OCO_POLICY.groups){
    const members=g.proxies.filter(n=>valid.has(n));
    if(members.length===0||(g.type==="url-test"&&members.length<2))continue;
    additions.push(Object.assign({},g,{proxies:members}));
  }
  if(!additions.length)return config;
  for(const g of additions)groups.push(g);
  parent[0].proxies=parent[0].proxies.concat(additions.map(g=>g.name).filter(n=>!parent[0].proxies.includes(n)));
  return config;
}
