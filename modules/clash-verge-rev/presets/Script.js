// Clash Verge global script v2.3 - conservative, idempotent.
function array(v) { return Array.isArray(v) ? v : []; }
function obj(v) { return v && typeof v === "object" && !Array.isArray(v) ? v : {}; }
function unique(v) { return Array.from(new Set(array(v).filter(x => typeof x === "string" && x.trim()))); }
function main(config, profileName) {
  if (!config || typeof config !== "object") return config;
  // First matching rule wins. Remove only exact repeated strings, keep order.
  if (Array.isArray(config.rules)) {
    const seenRules = new Set();
    config.rules = config.rules.filter(rule => {
      if (typeof rule !== "string") return true;
      if (seenRules.has(rule)) return false;
      seenRules.add(rule);
      return true;
    });
  }

  const dns = obj(config.dns);
  const policy = obj(dns["nameserver-policy"]);
  // Keep existing explicit policies; append missing defaults only.
  if (!Object.prototype.hasOwnProperty.call(policy, "geosite:cn"))
    policy["geosite:cn"] = ["https://dns.alidns.com/dns-query", "https://doh.pub/dns-query"];
  if (!Object.prototype.hasOwnProperty.call(policy, "geosite:geolocation-!cn"))
    policy["geosite:geolocation-!cn"] = ["https://cloudflare-dns.com/dns-query", "https://dns.google/dns-query"];
  dns["nameserver-policy"] = policy;
  const mode = dns["fake-ip-filter-mode"] || "blacklist";
  if (dns["enhanced-mode"] === "fake-ip" && mode === "blacklist") {
    dns["fake-ip-filter"] = unique(array(dns["fake-ip-filter"]).concat([
      "localhost", "+.localhost", "+.local", "+.lan", "+.home.arpa",
      "+.msftconnecttest.com", "+.msftncsi.com", "captive.apple.com",
      "time.windows.com", "time.apple.com", "+.pool.ntp.org"
    ]));
  }
  config.dns = dns;

  const groups = array(config["proxy-groups"]);
  const proxies = array(config.proxies);
  const providers = Object.keys(obj(config["proxy-providers"]));
  const AI = "AI-\u56fa\u5b9a\u51fa\u53e3";
  const TEST = "https://cp.cloudflare.com/generate_204";
  // Only normalize known HTTP 204 probes or missing probes; preserve custom URLs.
  const known = /^http:\/\/(?:www\.gstatic\.com|cp\.cloudflare\.com|connectivitycheck\.gstatic\.com)\/generate_204\/?$/i;
  for (const g of groups) {
    if (!g || (g.type !== "url-test" && g.type !== "fallback")) continue;
    if (!g.url || known.test(g.url)) {
      g.url = TEST;
      if (g["expected-status"] == null) g["expected-status"] = 204;
    }
    // Bound stale health information without aggressive polling.
    // Explicitly disabled checks (interval=0) and shorter intervals are preserved.
    const ceiling = g.type === "url-test" ? 3600 : 1800;
    if (!Number.isFinite(g.interval) || g.interval < 0) g.interval = ceiling;
    else if (g.interval > ceiling) g.interval = ceiling;
    if (typeof g.lazy !== "boolean") g.lazy = true;
    if (g.type === "url-test" && !Number.isFinite(g.tolerance)) g.tolerance = 100;
  }
  // Keep provider health-check settings intact.
  const reserved = new Set(["DIRECT", "REJECT", "REJECT-DROP", "PASS", "COMPATIBLE", "GLOBAL", AI]);
  const groupNames = new Set(groups.filter(Boolean).map(g => g.name));
  const info = /^(?:\s*[\u{1F300}-\u{1FAFF}\u2600-\u27BF\uFE0F]*\s*)(?:\u5269\u4f59\u6d41\u91cf|\u5957\u9910\u5230\u671f|\u8ddd\u79bb\u4e0b\u6b21\u91cd\u7f6e|\u6d41\u91cf\u91cd\u7f6e|\u5230\u671f\u65f6\u95f4|\u5269\u4f59\u5929\u6570|traffic remaining|expire date)\s*[:\uFF1A]/iu;
  const nonProxyTypes = new Set(["direct", "reject", "reject-drop", "pass", "pass-rule", "compatible"]);
  const nodes = unique(proxies.filter(p => p && !nonProxyTypes.has(String(p.type || "").toLowerCase())).map(p => p.name)).filter(n => !reserved.has(n) && !groupNames.has(n) && !info.test(n));
  // Never create an invalid group or fall back to DIRECT.
  if ((!nodes.length && !providers.length) || proxies.some(p => p && p.name === AI) || providers.includes(AI)) return config;
  // Do not modify a foreign, non-select group with the same name.
  let ai = groups.find(g => g && g.name === AI);
  if (ai && ai.type !== "select") return config;
  if (!ai) {
    ai = {name: AI, type: "select"};
    groups.unshift(ai);
  }
  if (nodes.length) ai.proxies = nodes; else delete ai.proxies;
  if (providers.length) ai.use = providers; else delete ai.use;
  // Never silently use the default COMPATIBLE route when the AI group is empty.
  ai["empty-fallback"] = "REJECT";
  delete ai["include-all"];
  delete ai["include-all-proxies"];
  delete ai["include-all-providers"];
  config["proxy-groups"] = groups;
  const domains = ["chatgpt.com", "openai.com", "oaistatic.com", "oaiusercontent.com", "oaistatsig.com", "cdn.openaimerge.com"];
  const added = domains.map(d => "DOMAIN-SUFFIX," + d + "," + AI);
  const addedSet = new Set(domains);
  config.rules = added.concat(array(config.rules).filter(r => {
    if (typeof r !== "string") return true;
    const parts = r.split(",").map(x => x.trim());
    return !(parts.length === 3 && parts[0].toUpperCase() === "DOMAIN-SUFFIX" &&
      addedSet.has(parts[1].toLowerCase()) && parts[2] === AI);
  }));
  return config;
}
