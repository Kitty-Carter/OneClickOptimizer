#[cfg(windows)]
mod app {
    use serde_yaml_ng::{Mapping, Value};
    use std::{
        collections::HashSet,
        env, fs,
        io::{self, Write},
        mem::{size_of, zeroed},
        net::TcpListener,
        os::windows::io::AsRawHandle,
        path::{Path, PathBuf},
        process::{Child, Command, Stdio},
        ptr::{null, null_mut},
        thread,
        time::{Duration, Instant},
    };
    use windows_sys::Win32::{
        Foundation::{CloseHandle, HANDLE},
        NetworkManagement::IpHelper::{
            GetExtendedTcpTable, MIB_TCPROW_OWNER_PID, MIB_TCPTABLE_OWNER_PID,
            TCP_TABLE_OWNER_PID_LISTENER,
        },
        Security::Cryptography::{
            BCryptGenRandom, BCryptHash, BCRYPT_SHA256_ALG_HANDLE, BCRYPT_USE_SYSTEM_PREFERRED_RNG,
        },
        System::JobObjects::{
            AssignProcessToJobObject, CreateJobObjectW, JobObjectExtendedLimitInformation,
            SetInformationJobObject, JOBOBJECT_EXTENDED_LIMIT_INFORMATION,
            JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE,
        },
    };
    fn key(k: &str) -> Value {
        Value::String(k.into())
    }
    fn get<'a>(m: &'a Mapping, k: &str) -> Option<&'a Value> {
        m.get(key(k))
    }
    fn safe_text(s: &str) -> String {
        s.chars().filter(|c| !c.is_control()).take(120).collect()
    }
    fn plain(v: &Value, depth: u32) -> bool {
        if depth > 20 {
            return false;
        }
        match v {
            Value::Tagged(_) => false,
            Value::Sequence(a) => a.len() <= 1024 && a.iter().all(|x| plain(x, depth + 1)),
            Value::Mapping(m) => {
                m.len() <= 128
                    && m.iter()
                        .all(|(k, v)| k.as_str().is_some_and(|k| k != "<<") && plain(v, depth + 1))
            }
            _ => true,
        }
    }
    struct Node {
        index: usize,
        name: String,
        proto: String,
        skip: Option<bool>,
        data: Mapping,
    }
    fn select(v: Value) -> Result<Vec<Node>, String> {
        let root = v.as_mapping().ok_or("Invalid YAML root")?;
        let ps = get(root, "proxies")
            .and_then(Value::as_sequence)
            .ok_or("No inline proxies (provider-only not supported)")?;
        if ps.len() > 4096 {
            return Err("Too many nodes".into());
        }
        let mut names = HashSet::new();
        let mut dup = HashSet::new();
        for n in ps {
            if let Some(n) = n
                .as_mapping()
                .and_then(|m| get(m, "name"))
                .and_then(Value::as_str)
            {
                if !names.insert(n) {
                    dup.insert(n);
                }
            }
        }
        let mut out = vec![];
        for (i, v) in ps.iter().enumerate() {
            let Some(m) = v.as_mapping() else { continue };
            let Some(name) = get(m, "name").and_then(Value::as_str) else {
                continue;
            };
            let Some(proto) = get(m, "type").and_then(Value::as_str) else {
                continue;
            };
            if dup.contains(name)
                || !matches!(proto, "anytls" | "vless" | "hysteria2")
                || !plain(v, 0)
            {
                continue;
            }
            if [
                "dialer-proxy",
                "interface-name",
                "routing-mark",
                "proxy",
                "certificate",
                "private-key",
            ]
            .iter()
            .any(|k| get(m, k).is_some_and(|x| !x.is_null()))
            {
                continue;
            }
            if !get(m, "server").and_then(Value::as_str).is_some_and(|x| {
                !x.is_empty() && x.len() <= 253 && !x.chars().any(char::is_whitespace)
            }) {
                continue;
            }
            if !get(m, "port")
                .and_then(Value::as_u64)
                .is_some_and(|x| (1..=65535).contains(&x))
            {
                continue;
            }
            out.push(Node {
                index: i + 1,
                name: safe_text(name),
                proto: proto.into(),
                skip: get(m, "skip-cert-verify").and_then(Value::as_bool),
                data: m.clone(),
            });
        }
        // Preserve subscription order so the numbered batches cover all eligible nodes.
        Ok(out)
    }
    fn read_bounded(path: &Path) -> Result<String, String> {
        use std::io::Read;
        let f = fs::File::open(path).map_err(|_| "YAML file unavailable")?;
        let mut raw = Vec::new();
        f.take(8 * 1024 * 1024 + 1)
            .read_to_end(&mut raw)
            .map_err(|_| "YAML read failed")?;
        if raw.len() > 8 * 1024 * 1024 {
            return Err("YAML file too large".into());
        }
        String::from_utf8(raw).map_err(|_| "YAML UTF-8 read failed".into())
    }
    fn read_yaml(path: &Path) -> Result<Value, String> {
        let text = read_bounded(path)?;
        serde_yaml_ng::from_str(text.trim_start_matches('\u{feff}'))
            .map_err(|_| "YAML parse failed (details hidden)".into())
    }
    fn parse_merge(text: &str) -> Result<Value, String> {
        // Conservative refusal: any anchor/alias indicator, even within text or comments.
        // Not a general YAML lexer. This avoids silently expanding aliases in a user edit.
        if text.contains(['&', '*']) {
            return Err("Potential anchor/alias; missing-only merge refused".into());
        }
        serde_yaml_ng::from_str(text.trim_start_matches('\u{feff}'))
            .map_err(|_| "YAML parse failed (details hidden)".into())
    }
    // Only add absent settings. Never overwrite explicit values or merge DNS.
    // Generated runtime observation only. Never claim that file bytes prove packet routing.
    fn runtime_checks(v: &Value) -> Vec<(&'static str, bool)> {
        let base: Value = serde_yaml_ng::from_str(include_str!("../../presets/Merge.yaml"))
            .expect("embedded preset");
        let mut result = vec![(
            "tcp-concurrent",
            v.get("tcp-concurrent") == Some(&Value::Bool(true)),
        )];
        for (name, k) in [
            ("profile.store-selected", "store-selected"),
            ("profile.store-fake-ip", "store-fake-ip"),
        ] {
            result.push((
                name,
                v.get("profile").and_then(|x| x.get(k)) == Some(&Value::Bool(true)),
            ));
        }
        for k in [
            "enable",
            "enhanced-mode",
            "fake-ip-range",
            "cache-algorithm",
            "prefer-h3",
            "use-hosts",
            "use-system-hosts",
            "respect-rules",
            "default-nameserver",
            "proxy-server-nameserver",
            "nameserver",
            "fallback",
            "fallback-filter",
            "fallback-lazy-query",
        ] {
            let actual = v.get("dns").and_then(|d| d.get(k));
            let expected = base.get("dns").and_then(|d| d.get(k));
            result.push((k, actual.is_some() && actual == expected));
        }
        let ai = "AI-固定出口";
        let groups = v.get("proxy-groups").and_then(Value::as_sequence);
        let g = groups
            .map(|x| {
                x.iter()
                    .filter(|g| g.get("name").and_then(Value::as_str) == Some(ai))
                    .collect::<Vec<_>>()
            })
            .unwrap_or_default();
        let inline = v.get("proxies").and_then(Value::as_sequence);
        let good = if g.len() == 1 {
            let g = g[0];
            let members = g.get("proxies").and_then(Value::as_sequence);
            g.get("type").and_then(Value::as_str) == Some("select")
                && g.get("empty-fallback").and_then(Value::as_str) == Some("REJECT")
                && g.get("use")
                    .and_then(Value::as_sequence)
                    .is_none_or(|x| x.is_empty())
                && [
                    "include-all",
                    "include-all-proxies",
                    "include-all-providers",
                ]
                .iter()
                .all(|k| g.get(*k).is_none_or(|x| x == &Value::Bool(false)))
                && members.is_some_and(|ms| {
                    !ms.is_empty()
                        && ms.iter().all(|x| {
                            let Some(n) = x.as_str() else { return false };
                            if [
                                "DIRECT",
                                "REJECT",
                                "REJECT-DROP",
                                "PASS",
                                "COMPATIBLE",
                                "GLOBAL",
                                ai,
                            ]
                            .contains(&n)
                            {
                                return false;
                            }
                            inline.is_some_and(|nodes| {
                                let found = nodes
                                    .iter()
                                    .filter(|p| p.get("name").and_then(Value::as_str) == Some(n))
                                    .collect::<Vec<_>>();
                                found.len() == 1
                                    && found[0].get("type").and_then(Value::as_str).is_some_and(
                                        |t| {
                                            ![
                                                "direct",
                                                "reject",
                                                "reject-drop",
                                                "pass",
                                                "pass-rule",
                                                "compatible",
                                            ]
                                            .contains(&t.to_ascii_lowercase().as_str())
                                        },
                                    )
                            })
                        })
                })
        } else {
            false
        };
        result.push(("AI inline selector/no direct fallback", good));
        let domains = [
            "chatgpt.com",
            "openai.com",
            "oaistatic.com",
            "oaiusercontent.com",
            "oaistatsig.com",
            "cdn.openaimerge.com",
        ];
        let rules = v.get("rules").and_then(Value::as_sequence);
        result.push((
            "AI first-match rule prefix",
            rules.is_some_and(|r| {
                r.len() >= domains.len()
                    && domains.iter().enumerate().all(|(i, d)| {
                        r[i].as_str() == Some(format!("DOMAIN-SUFFIX,{d},{ai}").as_str())
                    })
            }),
        ));
        result
    }
    #[derive(Default, Debug, PartialEq, Eq)]
    struct GraphAudit {
        duplicates: usize,
        missing_member: usize,
        missing_provider: usize,
        cycles: usize,
        missing_simple_rule_target: usize,
        unknown_rule_forms: usize,
    }
    fn audit_graph(v: &Value) -> Result<GraphAudit, String> {
        if !v.is_mapping() || v.get("rules").and_then(Value::as_sequence).is_none() {
            return Err("Runtime mapping or rule sequence missing".into());
        }
        let mut out = GraphAudit::default();
        let mut known = HashSet::new();
        let reserved = [
            "DIRECT",
            "REJECT",
            "REJECT-DROP",
            "PASS",
            "COMPATIBLE",
            "GLOBAL",
        ];
        let mut edges = std::collections::HashMap::<String, Vec<String>>::new();
        for key in ["proxies", "proxy-groups"] {
            if let Some(a) = v.get(key) {
                let a = a.as_sequence().ok_or("Proxy/group list is not sequence")?;
                if a.len() > 4096 {
                    return Err("Graph exceeds audit bound".into());
                }
                for p in a {
                    let n = p
                        .get("name")
                        .and_then(Value::as_str)
                        .ok_or("Missing proxy/group name")?;
                    if reserved.contains(&n) || !known.insert(n.to_owned()) {
                        out.duplicates += 1;
                    }
                    if key == "proxy-groups" {
                        edges.entry(n.to_owned()).or_default();
                    }
                }
            }
        }
        let providers = v.get("proxy-providers").and_then(Value::as_mapping);
        if let Some(gs) = v.get("proxy-groups").and_then(Value::as_sequence) {
            for g in gs {
                let n = g.get("name").and_then(Value::as_str).ok_or("Group name")?;
                if let Some(ps) = g.get("proxies") {
                    for member in ps.as_sequence().ok_or("Group proxies not sequence")? {
                        let p = member.as_str().ok_or("Non-string member")?;
                        if !known.contains(p) && !reserved.contains(&p) {
                            out.missing_member += 1
                        }
                        if edges.contains_key(p) {
                            edges.get_mut(n).unwrap().push(p.to_owned())
                        }
                    }
                }
                if let Some(ps) = g.get("use") {
                    for member in ps.as_sequence().ok_or("Group use not sequence")? {
                        if providers.is_none_or(|p| !p.contains_key(member)) {
                            out.missing_provider += 1;
                        }
                    }
                }
            }
        }
        // Kahn topological elimination; residual vertices include cycles and dependants.
        let mut indegree = edges
            .keys()
            .map(|n| (n.clone(), 0usize))
            .collect::<std::collections::HashMap<_, _>>();
        for es in edges.values() {
            for e in es {
                *indegree.get_mut(e).unwrap() += 1;
            }
        }
        let mut q = indegree
            .iter()
            .filter(|(_, d)| **d == 0)
            .map(|(n, _)| n.clone())
            .collect::<Vec<_>>();
        let mut removed = 0;
        while let Some(n) = q.pop() {
            removed += 1;
            for e in &edges[&n] {
                let d = indegree.get_mut(e).unwrap();
                *d -= 1;
                if *d == 0 {
                    q.push(e.clone())
                }
            }
        }
        out.cycles = edges.len() - removed;
        if let Some(r) = v.get("rules").and_then(Value::as_sequence) {
            for line in r {
                let Some(line) = line.as_str() else {
                    out.unknown_rule_forms += 1;
                    continue;
                };
                let p = line.split(',').map(str::trim).collect::<Vec<_>>();
                let typ = p.first().copied().unwrap_or("");
                let target = if typ == "MATCH" && p.len() == 2 {
                    Some(p[1])
                } else if [
                    "DOMAIN",
                    "DOMAIN-SUFFIX",
                    "DOMAIN-KEYWORD",
                    "GEOIP",
                    "GEOSITE",
                    "IP-CIDR",
                    "IP-CIDR6",
                    "SRC-IP-CIDR",
                    "DST-PORT",
                    "SRC-PORT",
                    "PROCESS-NAME",
                    "PROCESS-PATH",
                    "RULE-SET",
                ]
                .contains(&typ)
                    && (p.len() == 3 || (p.len() == 4 && p[3] == "no-resolve"))
                {
                    Some(p[2])
                } else {
                    None
                };
                match target {
                    Some(t) if !known.contains(t) && !reserved.contains(&t) => {
                        out.missing_simple_rule_target += 1
                    }
                    None => out.unknown_rule_forms += 1,
                    _ => {}
                }
            }
        }
        Ok(out)
    }
    fn merge_safe(v: &Value) -> Result<(Value, usize), String> {
        if !plain(v, 0) {
            return Err("Unsupported YAML structure".into());
        }
        let mut out = v.clone();
        let m = out
            .as_mapping_mut()
            .ok_or("Merge YAML root must be mapping")?;
        // The upstream global merge lowercases top-level keys. Refuse aliases/case
        // collisions instead of treating an explicit setting as missing.
        let mut folded = HashSet::new();
        for k in m.keys().filter_map(Value::as_str) {
            let low = k.to_ascii_lowercase();
            if !folded.insert(low.clone())
                || (["tcp-concurrent", "profile"].contains(&low.as_str()) && low != k)
            {
                return Err("Case-ambiguous top-level key; merge refused".into());
            }
        }
        let mut count = 0;
        if !m.contains_key(key("tcp-concurrent")) {
            m.insert(key("tcp-concurrent"), Value::Bool(true));
            count += 1;
        }
        if !m.contains_key(key("profile")) {
            m.insert(key("profile"), Value::Mapping(Mapping::new()));
        }
        let profile = m
            .get_mut(key("profile"))
            .and_then(Value::as_mapping_mut)
            .ok_or("Existing profile is not mapping; refused")?;
        for k in ["store-selected", "store-fake-ip"] {
            if profile
                .keys()
                .filter_map(Value::as_str)
                .any(|n| n.eq_ignore_ascii_case(k) && n != k)
            {
                return Err("Case-ambiguous profile key; merge refused".into());
            }
            if !profile.contains_key(key(k)) {
                profile.insert(key(k), Value::Bool(true));
                count += 1;
            }
        }
        Ok((out, count))
    }
    fn create_yaml(path: &Path, v: &Value) -> Result<(), String> {
        let text = serde_yaml_ng::to_string(v).map_err(|_| "YAML encode failed")?;
        let round: Value = serde_yaml_ng::from_str(&text).map_err(|_| "YAML roundtrip failed")?;
        if round != *v {
            return Err("YAML roundtrip changed data".into());
        }
        let mut f = fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(path)
            .map_err(|_| "Output must be a new file")?;
        f.write_all(text.as_bytes())
            .map_err(|_| "Output write failed")?;
        f.sync_all().map_err(|_| "Output sync failed".to_string())
    }
    fn group(name: &str, kind: &str, names: &[String]) -> Value {
        let mut g = Mapping::new();
        g.insert(key("name"), key(name));
        g.insert(key("type"), key(kind));
        g.insert(
            key("proxies"),
            Value::Sequence(names.iter().map(|n| key(n)).collect()),
        );
        g.insert(key("empty-fallback"), key("REJECT"));
        if kind == "url-test" {
            g.insert(key("url"), key("https://cp.cloudflare.com/generate_204"));
            g.insert(key("expected-status"), Value::Number(204.into()));
            g.insert(key("interval"), Value::Number(1800.into()));
            g.insert(key("tolerance"), Value::Number(100.into()));
            g.insert(key("lazy"), Value::Bool(true));
        }
        Value::Mapping(g)
    }
    fn policy_groups(ranked: &[(String, f64, Option<f64>)]) -> Value {
        let mut v = ranked.to_vec();
        v.sort_by(|a, b| a.1.total_cmp(&b.1));
        let mut groups = Vec::new();
        if !v.is_empty() {
            let names = v.iter().map(|r| r.0.clone()).collect::<Vec<_>>();
            groups.push(group("OCO-实测候选", "select", &names));
            if names.len() >= 2 {
                groups.push(group("OCO-低延迟优选", "url-test", &names));
            }
        }
        v.retain(|r| r.2.is_some());
        v.sort_by(|a, b| b.2.unwrap().total_cmp(&a.2.unwrap()));
        if !v.is_empty() {
            groups.push(group(
                "OCO-下载候选",
                "select",
                &v.iter().map(|r| r.0.clone()).collect::<Vec<_>>(),
            ));
        }
        Value::Sequence(groups)
    }
    fn policy_candidate(config: &Value, groups: &Value) -> Result<Value, String> {
        let mut out = config.clone();
        let m = out.as_mapping_mut().ok_or("Runtime YAML root")?;
        let mut used = HashSet::<String>::new();
        for k in ["proxies", "proxy-groups"] {
            if let Some(seq) = get(m, k).and_then(Value::as_sequence) {
                for item in seq {
                    if let Some(n) = item
                        .as_mapping()
                        .and_then(|m| get(m, "name"))
                        .and_then(Value::as_str)
                    {
                        used.insert(n.to_owned());
                    }
                }
            }
        }
        if let Some(p) = get(m, "proxy-providers").and_then(Value::as_mapping) {
            for k in p.keys() {
                if let Some(n) = k.as_str() {
                    used.insert(n.to_owned());
                }
            }
        }
        let new = groups.as_sequence().ok_or("Groups missing")?;
        for g in new {
            let name = g
                .as_mapping()
                .and_then(|m| get(m, "name"))
                .and_then(Value::as_str)
                .ok_or("Missing group name")?;
            if used.contains(name) {
                return Err("Group name collision; no output".into());
            }
            used.insert(name.to_owned());
        }
        let old = m
            .get_mut(key("proxy-groups"))
            .and_then(Value::as_sequence_mut)
            .ok_or("Runtime groups not a sequence")?;
        old.extend(new.iter().cloned());
        Ok(out)
    }
    fn now() -> u64 {
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|x| x.as_secs())
            .unwrap_or(0)
    }
    fn hash(bytes: &[u8]) -> Result<String, String> {
        let mut out = [0u8; 32];
        if bytes.len() > 16 * 1024 * 1024 {
            return Err("Hash input too large".into());
        }
        if unsafe {
            BCryptHash(
                BCRYPT_SHA256_ALG_HANDLE,
                null(),
                0,
                bytes.as_ptr(),
                bytes.len() as u32,
                out.as_mut_ptr(),
                32,
            )
        } != 0
        {
            return Err("SHA256 unavailable".into());
        }
        Ok(out.iter().map(|b| format!("{b:02x}")).collect())
    }
    fn quote(s: &str) -> String {
        format!(
            "\"{}\"",
            s.encode_utf16()
                .map(|u| format!("\\u{u:04x}"))
                .collect::<String>()
        )
    }
    fn canon(v: &Value, depth: u32) -> Result<String, String> {
        if depth > 20 {
            return Err("Fingerprint depth".into());
        }
        let cs = |s: &str| {
            format!(
                "s{};",
                s.encode_utf16()
                    .map(|u| format!("{u:04x}"))
                    .collect::<String>()
            )
        };
        let t = match v {
            Value::Null => "z;".into(),
            Value::Bool(b) => {
                if *b {
                    "b1;".into()
                } else {
                    "b0;".into()
                }
            }
            Value::String(s) => cs(s),
            Value::Number(n) => {
                let n = n
                    .as_i64()
                    .filter(|x| (-9007199254740991..=9007199254740991).contains(x))
                    .ok_or("Non-integral or unsafe numeric node field")?;
                format!("n{n};")
            }
            Value::Sequence(a) => {
                let mut t = String::from("a[");
                for x in a {
                    t.push_str(&canon(x, depth + 1)?);
                }
                t.push(']');
                t
            }
            Value::Mapping(m) => {
                let mut a = m
                    .iter()
                    .map(|(k, v)| Ok((k.as_str().ok_or("Non-string key")?, v)))
                    .collect::<Result<Vec<_>, &str>>()?;
                a.sort_by(|a, b| a.0.encode_utf16().cmp(b.0.encode_utf16()));
                let mut t = String::from("m{");
                for (k, v) in a {
                    t.push_str(&cs(k));
                    t.push_str(&canon(v, depth + 1)?);
                }
                t.push('}');
                t
            }
            _ => return Err("Unsupported fingerprint value".into()),
        };
        if t.len() > 1048576 {
            return Err("Fingerprint too large".into());
        }
        Ok(t)
    }
    fn compose(
        runtime: &Value,
        proposal: &Value,
        parent: &str,
        created: u64,
    ) -> Result<String, String> {
        let m = runtime.as_mapping().ok_or("Invalid runtime")?;
        if parent == "AI-固定出口" || parent.starts_with("OCO-") {
            return Err("AI or OCO parent prohibited".into());
        }
        let pg = get(m, "proxy-groups")
            .and_then(Value::as_sequence)
            .ok_or("No groups")?;
        let parents = pg
            .iter()
            .filter_map(Value::as_mapping)
            .filter(|g| get(g, "name").and_then(Value::as_str) == Some(parent))
            .collect::<Vec<_>>();
        if parents.len() != 1
            || get(parents[0], "type").and_then(Value::as_str) != Some("select")
            || get(parents[0], "proxies")
                .and_then(Value::as_sequence)
                .is_none_or(|s| s.is_empty())
        {
            return Err("Choose a non-AI existing select group with explicit members".into());
        }
        let eligible = select(runtime.clone())?;
        let mut js_groups = Vec::new();
        let mut fps = std::collections::BTreeMap::new();
        let groups = proposal.as_sequence().ok_or("Invalid proposal groups")?;
        if groups.is_empty() || groups.len() > 3 {
            return Err("Invalid group count".into());
        }
        let mut names = HashSet::new();
        for g in groups {
            let g = g.as_mapping().ok_or("Invalid proposal group")?;
            let name = get(g, "name")
                .and_then(Value::as_str)
                .ok_or("Missing name")?;
            let kind = match name {
                "OCO-实测候选" | "OCO-下载候选" => "select",
                "OCO-低延迟优选" => "url-test",
                _ => return Err("Unexpected candidate name".into()),
            };
            if !names.insert(name) {
                return Err("Duplicate group".into());
            }
            let members = get(g, "proxies")
                .and_then(Value::as_sequence)
                .ok_or("Missing members")?;
            if members.is_empty() || members.len() > 6 || (kind == "url-test" && members.len() < 2)
            {
                return Err("Invalid members".into());
            }
            let mut ms = Vec::new();
            let mut used = HashSet::new();
            for n in members {
                let name = n.as_str().ok_or("Invalid member")?;
                if !used.insert(name) {
                    return Err("Duplicate member".into());
                }
                let node = eligible
                    .iter()
                    .find(|x| get(&x.data, "name").and_then(Value::as_str) == Some(name))
                    .ok_or("Candidate not in current nodes")?;
                let fp = hash(canon(&Value::Mapping(node.data.clone()), 0)?.as_bytes())?;
                fps.insert(name.to_string(), fp);
                ms.push(name.to_string());
            }
            if Value::Mapping(g.clone()) != group(name, kind, &ms) {
                return Err("Proposal settings changed".into());
            }
            let members = ms.iter().map(|x| quote(x)).collect::<Vec<_>>().join(",");
            let extra = if kind == "url-test" {
                ",\"url\":\"https://cp.cloudflare.com/generate_204\",\"expected-status\":204,\"interval\":1800,\"tolerance\":100,\"lazy\":true"
            } else {
                ""
            };
            js_groups.push(format!(
                "{{\"name\":{},\"type\":{},\"proxies\":[{}],\"empty-fallback\":\"REJECT\"{}}}",
                quote(name),
                quote(kind),
                members,
                extra
            ));
        }
        // Reject collision in runtime now; template independently checks again at reload.
        policy_candidate(runtime, proposal)?;
        let pairs = fps
            .iter()
            .map(|(n, h)| format!("[{},{}]", quote(n), quote(h)))
            .collect::<Vec<_>>()
            .join(",");
        let base = include_str!("../../presets/Script.js").replacen(
            "function main(",
            "function ocoBaseMain(",
            1,
        );
        let template = include_str!("policy-template.js");
        Ok(format!("{base}\nconst OCO_POLICY = {{created:{created},expires:{},parent:{},nodes:[{}],groups:[{}]}};\n{template}",created+86400,quote(parent),pairs,js_groups.join(",")))
    }
    fn policy_envelope(groups: Value, raw: &str) -> Result<Value, String> {
        let mut m = Mapping::new();
        m.insert(key("format"), key("oco-policy-v1"));
        m.insert(key("created"), Value::Number(now().into()));
        m.insert(key("runtime-sha256"), key(&hash(raw.as_bytes())?));
        m.insert(key("proxy-groups"), groups);
        Ok(Value::Mapping(m))
    }
    fn check_core(exe: &Path) -> Result<(), String> {
        if exe
            .file_name()
            .and_then(|x| x.to_str())
            .is_none_or(|s| !s.eq_ignore_ascii_case("verge-mihomo.exe"))
        {
            return Err("Explicit bundled core path required".into());
        }
        let v = Command::new(exe)
            .arg("-v")
            .output()
            .map_err(|_| "Core version unavailable")?;
        if !v.status.success()
            || !String::from_utf8_lossy(&v.stdout)
                .split_whitespace()
                .any(|w| w == "v1.19.33")
        {
            return Err("Only bundled Mihomo 1.19.33 validated".into());
        }
        Ok(())
    }
    fn validate_candidate(
        config: &Path,
        exe: &Path,
        runtime: &Value,
        candidate: &Value,
    ) -> Result<(), String> {
        // Full runtime copy is sensitive; never write it outside the protected temporary directory.
        let temp = private_temp()?;
        let cf = temp.0.join("candidate.yaml");
        create_yaml(&cf, candidate)?;
        // Core -t validation only; copy existing GeoData files to avoid network lookup where available.
        for n in ["geoip.dat", "geosite.dat", "Country.mmdb", "ASN.mmdb"] {
            let f = config.parent().ok_or("Config parent")?.join(n);
            if f.is_file() {
                fs::copy(f, temp.0.join(n)).map_err(|_| "GeoData copy failed")?;
            }
        }
        // No provider fetch or external data download during validation.
        let m = runtime.as_mapping().ok_or("Runtime mapping")?;
        for k in ["proxy-providers", "rule-providers"] {
            if get(m, k)
                .and_then(Value::as_mapping)
                .is_some_and(|m| !m.is_empty())
            {
                return Err("Provider-based validation not supported".into());
            }
        }
        for n in ["geoip.dat", "geosite.dat", "Country.mmdb", "ASN.mmdb"] {
            if !temp.0.join(n).is_file() {
                return Err("GeoData missing; no candidate output".into());
            }
        }
        let job = Job::new()?;
        let mut proc = Core(
            Command::new(exe)
                .arg("-t")
                .arg("-d")
                .arg(&temp.0)
                .arg("-f")
                .arg(&cf)
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .spawn()
                .map_err(|_| "Core validation start failed")?,
        );
        if !job.attach(&proc.0) {
            return Err("Core validation job failed".into());
        }
        let started = Instant::now();
        loop {
            if let Some(status) = proc
                .0
                .try_wait()
                .map_err(|_| "Core validation status failed")?
            {
                if !status.success() {
                    return Err("Core rejected candidate".into());
                }
                break;
            }
            if started.elapsed() > Duration::from_secs(20) {
                return Err("Core validation timeout".into());
            }
            thread::sleep(Duration::from_millis(100));
        }
        Ok(())
    }
    fn compose_from_files(
        runtime: &Path,
        exe: &Path,
        proposal: &Path,
        parent: &str,
        dest: &Path,
    ) -> Result<(), String> {
        let raw = fs::read_to_string(runtime).map_err(|_| "Runtime unavailable")?;
        let v = read_yaml(runtime)?;
        let p = read_yaml(proposal)?;
        let m = p.as_mapping().ok_or("Proposal invalid")?;
        let created = get(m, "created")
            .and_then(Value::as_u64)
            .ok_or("No creation time")?;
        if get(m, "format").and_then(Value::as_str) != Some("oco-policy-v1")
            || now() < created
            || now() - created > 3600
            || get(m, "runtime-sha256").and_then(Value::as_str)
                != Some(hash(raw.as_bytes())?.as_str())
        {
            return Err("Stale or mismatched runtime proposal; retest".into());
        }
        if fs::read_to_string(runtime).map_err(|_| "Runtime reread failed")? != raw {
            return Err("Runtime changed".into());
        }
        check_core(exe)?;
        let groups = get(m, "proxy-groups").ok_or("Missing groups")?;
        let script = compose(&v, groups, parent, created)?;
        let mut candidate = policy_candidate(&v, groups)?;
        let seq = candidate
            .get_mut("proxy-groups")
            .and_then(Value::as_sequence_mut)
            .ok_or("Groups missing")?;
        let selected = seq
            .iter_mut()
            .find(|x| x.get("name").and_then(Value::as_str) == Some(parent))
            .ok_or("Parent missing")?;
        let members = selected
            .get_mut("proxies")
            .and_then(Value::as_sequence_mut)
            .ok_or("Parent members missing")?;
        for g in groups.as_sequence().ok_or("Groups invalid")? {
            members.push(g.get("name").ok_or("Name missing")?.clone());
        }
        validate_candidate(runtime, exe, &v, &candidate)?;
        if fs::read_to_string(runtime).map_err(|_| "Runtime reread failed")? != raw {
            return Err("Runtime changed during validation".into());
        }
        let mut f = fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(dest)
            .map_err(|_| "Output must be new file")?;
        f.write_all(script.as_bytes())
            .map_err(|_| "Script output failed")?;
        Ok(())
    }
    fn batch_range(count: usize, batch: usize) -> Option<std::ops::Range<usize>> {
        let start = batch.checked_sub(1)?.checked_mul(6)?;
        if start >= count {
            return None;
        }
        Some(start..start.saturating_add(6).min(count))
    }
    fn isolated(node: &Node, port: u16) -> Result<String, String> {
        let mut c:Mapping=serde_yaml_ng::from_str("mode: rule\nbind-address: 127.0.0.1\nallow-lan: false\nipv6: false\nlog-level: error\ntun:\n  enable: false\ndns:\n  enable: false\nprofile:\n  store-selected: false\n  store-fake-ip: false\nrules:\n  - MATCH,NODE\n").map_err(|_|"Internal config error")?;
        c.insert(key("mixed-port"), Value::Number(port.into()));
        let mut p = node.data.clone();
        p.insert(key("name"), key("NODE"));
        c.insert(key("proxies"), Value::Sequence(vec![Value::Mapping(p)]));
        serde_yaml_ng::to_string(&c).map_err(|_| "Config serialization failed".into())
    }
    struct Job(HANDLE);
    impl Drop for Job {
        fn drop(&mut self) {
            unsafe {
                CloseHandle(self.0);
            }
        }
    }
    impl Job {
        fn new() -> Result<Self, String> {
            unsafe {
                let h = CreateJobObjectW(null(), null());
                if h.is_null() {
                    return Err("Job object unavailable".into());
                }
                let job = Self(h);
                let mut info: JOBOBJECT_EXTENDED_LIMIT_INFORMATION = zeroed();
                info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
                if SetInformationJobObject(
                    h,
                    JobObjectExtendedLimitInformation,
                    (&info as *const JOBOBJECT_EXTENDED_LIMIT_INFORMATION).cast(),
                    size_of::<JOBOBJECT_EXTENDED_LIMIT_INFORMATION>() as u32,
                ) == 0
                {
                    return Err("Job policy unavailable".into());
                }
                Ok(job)
            }
        }
        fn attach(&self, c: &Child) -> bool {
            unsafe { AssignProcessToJobObject(self.0, c.as_raw_handle().cast()) != 0 }
        }
    }
    struct Core(Child);
    impl Drop for Core {
        fn drop(&mut self) {
            let _ = self.0.kill();
            let _ = self.0.wait();
        }
    }
    struct Temp(PathBuf);
    impl Drop for Temp {
        fn drop(&mut self) {
            if fs::remove_dir_all(&self.0).is_err() {
                eprintln!("Temporary private config could not be removed; remove local OCO-Quality directory manually.")
            }
        }
    }
    fn sys(n: &str) -> Result<PathBuf, String> {
        Ok(
            PathBuf::from(env::var_os("SystemRoot").ok_or("SystemRoot missing")?)
                .join("System32")
                .join(n),
        )
    }
    fn private_temp() -> Result<Temp, String> {
        let mut rnd = [0u8; 16];
        if unsafe {
            BCryptGenRandom(
                null_mut(),
                rnd.as_mut_ptr(),
                rnd.len() as u32,
                BCRYPT_USE_SYSTEM_PREFERRED_RNG,
            )
        } != 0
        {
            return Err("Random generation failed".into());
        }
        let suffix = rnd.iter().map(|x| format!("{x:02x}")).collect::<String>();
        let d = PathBuf::from(env::var_os("LOCALAPPDATA").ok_or("LOCALAPPDATA missing")?)
            .join(format!("OCO-Quality-{suffix}"));
        fs::create_dir(&d).map_err(|_| "Private directory creation failed")?;
        let guard = Temp(d);
        let who = Command::new(sys("whoami.exe")?)
            .args(["/user", "/fo", "csv", "/nh"])
            .output()
            .map_err(|_| "SID query failed")?;
        let body = String::from_utf8_lossy(&who.stdout);
        let sid = body
            .split(|c: char| c == '"' || c == ',' || c.is_whitespace())
            .find(|s| {
                s.starts_with("S-1-")
                    && s.chars()
                        .all(|c| c == 'S' || c == '-' || c.is_ascii_digit())
            })
            .ok_or("SID unavailable")?;
        if !who.status.success() {
            return Err("SID query failed".into());
        }
        let user = format!("*{sid}:(OI)(CI)F");
        let a = Command::new(sys("icacls.exe")?)
            .arg(&guard.0)
            .args([
                "/inheritance:r",
                "/grant:r",
                &user,
                "*S-1-5-18:(OI)(CI)F",
                "*S-1-5-32-544:(OI)(CI)F",
            ])
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()
            .map_err(|_| "ACL command failed")?;
        if !a.success() {
            return Err("Private ACL failed; no config written".into());
        }
        Ok(guard)
    }
    fn owns(port: u16, pid: u32) -> bool {
        unsafe {
            let mut bytes = 0u32;
            if GetExtendedTcpTable(
                null_mut(),
                &mut bytes,
                0,
                2,
                TCP_TABLE_OWNER_PID_LISTENER,
                0,
            ) != 122
                || !(4..=8 * 1024 * 1024).contains(&bytes)
            {
                return false;
            }
            let mut b = vec![0u64; (bytes as usize).div_ceil(8)];
            if GetExtendedTcpTable(
                b.as_mut_ptr().cast(),
                &mut bytes,
                0,
                2,
                TCP_TABLE_OWNER_PID_LISTENER,
                0,
            ) != 0
            {
                return false;
            }
            let t = b.as_ptr().cast::<MIB_TCPTABLE_OWNER_PID>();
            let n = (*t).dwNumEntries as usize;
            if n > (b.len() * 8 - 4) / size_of::<MIB_TCPROW_OWNER_PID>() {
                return false;
            }
            let rows = std::slice::from_raw_parts(
                std::ptr::addr_of!((*t).table).cast::<MIB_TCPROW_OWNER_PID>(),
                n,
            );
            let selected: Vec<_> = rows
                .iter()
                .filter(|r| u16::from_be(r.dwLocalPort as u16) == port)
                .collect();
            selected.len() == 1
                && selected[0].dwOwningPid == pid
                && selected[0].dwLocalAddr.to_ne_bytes() == [127, 0, 0, 1]
        }
    }
    use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
    static CANCELLED: AtomicBool = AtomicBool::new(false);
    static RESERVED: AtomicU64 = AtomicU64::new(0);
    static RECEIVED: AtomicU64 = AtomicU64::new(0);
    static UNKNOWN_BYTES: AtomicU64 = AtomicU64::new(0);
    static STOP_BUDGET: AtomicBool = AtomicBool::new(false);
    static DEADLINE: std::sync::OnceLock<Instant> = std::sync::OnceLock::new();
    const LIMIT: u64 = 36 * 1024 * 1024;
    unsafe extern "system" fn console_cancel(code: u32) -> i32 {
        if code == 0 || code == 1 {
            CANCELLED.store(true, Ordering::Relaxed);
            1
        } else {
            0
        }
    }
    fn stopped() -> bool {
        CANCELLED.load(Ordering::Relaxed)
            || STOP_BUDGET.load(Ordering::Relaxed)
            || DEADLINE
                .get()
                .is_some_and(|t| t.elapsed() >= Duration::from_secs(1800))
    }
    fn reserve(counter: &AtomicU64, cap: u64, limit: u64) -> bool {
        let mut old = counter.load(Ordering::Acquire);
        loop {
            let Some(next) = old.checked_add(cap).filter(|v| *v <= limit) else {
                return false;
            };
            match counter.compare_exchange_weak(old, next, Ordering::AcqRel, Ordering::Acquire) {
                Ok(_) => return true,
                Err(current) => old = current,
            }
        }
    }
    fn report_budget() {
        println!(
            "RESPONSE_BYTES measured={} reserved_upper_bound={} unknown_probe_count={} cap={}",
            RECEIVED.load(Ordering::Relaxed),
            RESERVED.load(Ordering::Relaxed),
            UNKNOWN_BYTES.load(Ordering::Relaxed),
            LIMIT
        );
    }
    fn check_curl() -> Result<(), String> {
        let o = Command::new(sys("curl.exe")?)
            .arg("--version")
            .output()
            .map_err(|_| "curl version unavailable")?;
        let t = String::from_utf8_lossy(&o.stdout);
        let v = t.split_whitespace().nth(1).ok_or("curl version invalid")?;
        let mut n = v.split('.');
        let major = n
            .next()
            .and_then(|x| x.parse::<u32>().ok())
            .ok_or("curl major version invalid")?;
        let minor = n
            .next()
            .and_then(|x| x.parse::<u32>().ok())
            .ok_or("curl minor version invalid")?;
        if !o.status.success() || (major, minor) < (8, 4) {
            return Err("curl >=8.4 required for streaming max-filesize; no probes sent".into());
        }
        Ok(())
    }
    struct Probe {
        label: &'static str,
        ok: bool,
        http: u16,
        exit: i32,
        sec: f64,
        bytes: f64,
        speed: f64,
    }
    impl Probe {
        fn line(&self) -> String {
            let state = if self.ok {
                "EXPECTED"
            } else if self.exit != 0 {
                "TRANSFER_ERROR"
            } else {
                "HTTP_OR_SIZE_OTHER"
            };
            format!(
                "  {}: {} HTTP {} / curl {} / {:.1} ms / {:.3} MB/s / {:.0} bytes",
                self.label,
                state,
                self.http,
                self.exit,
                self.sec * 1000.0,
                self.speed / 1e6,
                self.bytes
            )
        }
    }
    fn parse_probe(
        label: &'static str,
        raw: &str,
        exit: i32,
        expected: u16,
        exact: Option<u64>,
    ) -> Result<Probe, String> {
        let a: Vec<_> = raw.trim().split('|').collect();
        if a.len() != 4 {
            return Err("Invalid curl response".into());
        }
        let http = a[0]
            .parse::<u16>()
            .ok()
            .filter(|x| *x <= 599)
            .ok_or("Invalid HTTP")?;
        let number = |x: &str| {
            x.parse::<f64>()
                .ok()
                .filter(|v| v.is_finite() && *v >= 0.0)
                .ok_or("Invalid numeric response")
        };
        let sec = number(a[1])?;
        let bytes = number(a[2])?;
        let speed = number(a[3])?;
        Ok(Probe {
            label,
            ok: exit == 0 && http == expected && exact.is_none_or(|x| bytes == x as f64),
            http,
            exit,
            sec,
            bytes,
            speed,
        })
    }
    fn probe(
        port: u16,
        label: &'static str,
        url: &str,
        expected: u16,
        cap: u64,
        exact: Option<u64>,
    ) -> Result<Probe, String> {
        if stopped() {
            return Err("CANCELLED_OR_BUDGET".into());
        }
        if !reserve(&RESERVED, cap, LIMIT) {
            STOP_BUDGET.store(true, Ordering::Relaxed);
            return Err("Response budget exhausted".into());
        }
        let proxy = format!("http://127.0.0.1:{port}");
        let cap = cap.to_string();
        let mut c = Command::new(sys("curl.exe")?);
        c.args([
            "-q",
            "--silent",
            "--show-error",
            "--proxy",
            &proxy,
            "--noproxy",
            "oco-no-bypass.invalid",
            "--proto",
            "=https",
            "--connect-timeout",
            "4",
            "--max-time",
            "10",
            "--max-filesize",
            &cap,
            "--output",
            "NUL",
            "--write-out",
            "%{http_code}|%{time_total}|%{size_download}|%{speed_download}",
            url,
        ]);
        for k in [
            "NO_PROXY",
            "no_proxy",
            "CURL_CA_BUNDLE",
            "SSL_CERT_FILE",
            "SSL_CERT_DIR",
        ] {
            c.env_remove(k);
        }
        let parsed = c
            .output()
            .map_err(|_| "curl unavailable".to_string())
            .and_then(|o| {
                parse_probe(
                    label,
                    &String::from_utf8_lossy(&o.stdout),
                    o.status.code().unwrap_or(-1),
                    expected,
                    exact,
                )
            });
        match parsed {
            Ok(p) => {
                RECEIVED.fetch_add(p.bytes as u64, Ordering::Relaxed);
                if p.bytes > cap.parse::<u64>().unwrap_or(0) as f64 {
                    STOP_BUDGET.store(true, Ordering::Relaxed);
                    return Err("Response cap exceeded".into());
                }
                Ok(p)
            }
            Err(e) => {
                UNKNOWN_BYTES.fetch_add(1, Ordering::Relaxed);
                STOP_BUDGET.store(true, Ordering::Relaxed);
                Err(e)
            }
        }
    }

    fn auto_screen(nodes: &[Node], exe: &Path) -> Vec<(usize, f64)> {
        use std::sync::atomic::{AtomicUsize, Ordering};
        let next = AtomicUsize::new(0);
        let results = std::sync::Mutex::new(Vec::new());
        thread::scope(|scope| {
            for _ in 0..3 {
                let next = &next;
                let results = &results;
                scope.spawn(move || loop {
                    if stopped() {
                        break;
                    }
                    let i = next.fetch_add(1, Ordering::Relaxed);
                    if i >= nodes.len() {
                        break;
                    }
                    let n = &nodes[i];
                    match test(n, exe, false, true, false) {
                        Ok(rows) => {
                            let mut ms = rows
                                .iter()
                                .filter(|r| r.label == "204" && r.ok)
                                .map(|r| r.sec * 1000.0)
                                .collect::<Vec<_>>();
                            if ms.len() == 3 {
                                ms.sort_by(f64::total_cmp);
                                results.lock().unwrap().push((i, ms[1]));
                            }
                            println!("SCREEN #{} {}/3 expected", n.index, ms.len());
                        }
                        Err(_) => println!("SCREEN #{} UNAVAILABLE", n.index),
                    }
                });
            }
        });
        let mut r = results.into_inner().unwrap();
        r.sort_by(|a, b| a.1.total_cmp(&b.1).then(a.0.cmp(&b.0)));
        r
    }
    fn test(
        node: &Node,
        exe: &Path,
        deep: bool,
        recommend: bool,
        recommend_download: bool,
    ) -> Result<Vec<Probe>, String> {
        if stopped() {
            return Err("CANCELLED_OR_BUDGET".into());
        }
        let tmp = private_temp()?;
        let port = TcpListener::bind("127.0.0.1:0")
            .and_then(|s| s.local_addr())
            .map_err(|_| "Port allocation failed")?
            .port();
        let config = tmp.0.join("config.yaml");
        fs::write(&config, isolated(node, port)?).map_err(|_| "Config write failed")?;
        let job = Job::new()?;
        let mut proc = Core(
            Command::new(exe)
                .arg("-d")
                .arg(&tmp.0)
                .arg("-f")
                .arg(&config)
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .spawn()
                .map_err(|_| "Core start failed")?,
        );
        if !job.attach(&proc.0) {
            return Err("Job assignment failed; no probes sent".into());
        }
        let start = Instant::now();
        while !owns(port, proc.0.id()) {
            if start.elapsed() > Duration::from_secs(5)
                || proc
                    .0
                    .try_wait()
                    .map_err(|_| "Core status unavailable")?
                    .is_some()
            {
                return Err("Isolated loopback listener unavailable".into());
            }
            thread::sleep(Duration::from_millis(100));
        }
        let mut rows = Vec::new();
        for _ in 0..if recommend { 3 } else { 2 } {
            if !owns(port, proc.0.id()) {
                return Err("Listener changed".into());
            }
            rows.push(probe(
                port,
                "204",
                "https://cp.cloudflare.com/generate_204",
                204,
                65536,
                None,
            )?);
        }
        if recommend && recommend_download && rows.iter().all(|r| r.ok) {
            for _ in 0..2 {
                if !owns(port, proc.0.id()) {
                    return Err("Listener changed".into());
                }
                rows.push(probe(
                    port,
                    "Download",
                    "https://speed.cloudflare.com/__down?bytes=1048576",
                    200,
                    1048576,
                    Some(1048576),
                )?);
            }
        }
        if deep && rows.iter().all(|r| r.ok) {
            for (label, url, expected, cap, exact) in [
                (
                    "Download",
                    "https://speed.cloudflare.com/__down?bytes=1048576",
                    200,
                    1048576,
                    Some(1048576),
                ),
                ("ChatGPT HTTP", "https://chatgpt.com/", 200, 2097152, None),
            ] {
                if !owns(port, proc.0.id()) {
                    return Err("Listener changed".into());
                }
                match probe(port, label, url, expected, cap, exact) {
                    Ok(r) => rows.push(r),
                    Err(e) => eprintln!("  {label}: UNAVAILABLE ({e})"),
                }
            }
        }
        Ok(rows)
    }
    pub fn run() -> Result<i32, String> {
        let a: Vec<_> = env::args_os().skip(1).collect();
        if a.first().is_some_and(|x| x == "--audit-runtime") {
            if a.len() != 2 {
                return Err("Usage: --audit-runtime runtime".into());
            }
            let g = audit_graph(&read_yaml(Path::new(&a[1]))?)?;
            println!("GRAPH_AUDIT duplicates={} missing_members={} missing_providers={} cycle_or_dependent_vertices={} missing_simple_rule_targets={} unparsed_rule_forms={}",g.duplicates,g.missing_member,g.missing_provider,g.cycles,g.missing_simple_rule_target,g.unknown_rule_forms);
            println!("Read-only structural audit; provider contents, complex rules and data plane not verified.");
            return Ok(
                if g.duplicates
                    + g.missing_member
                    + g.missing_provider
                    + g.cycles
                    + g.missing_simple_rule_target
                    == 0
                    && g.unknown_rule_forms == 0
                {
                    0
                } else {
                    2
                },
            );
        }
        if a.first().is_some_and(|x| x == "--mixed-port") {
            if a.len() != 2 {
                return Err("Usage: --mixed-port runtime".into());
            }
            let c = read_yaml(Path::new(&a[1]))?;
            let p = c
                .get("mixed-port")
                .and_then(Value::as_u64)
                .filter(|p| (1..=65535).contains(p))
                .ok_or("No valid mixed-port")?;
            println!("{p}");
            return Ok(0);
        }
        if a.first().is_some_and(|x| x == "--verify-runtime") {
            if a.len() != 2 {
                return Err("Usage: --verify-runtime runtime".into());
            }
            let c = read_yaml(Path::new(&a[1]))?;
            let checks = runtime_checks(&c);
            let mut pass = 0;
            for (k, ok) in &checks {
                if *ok {
                    pass += 1;
                }
                println!("{} {}", if *ok { "MATCH" } else { "DIFF_OR_UNVERIFIED" }, k);
            }
            println!("{pass}/{} generated-runtime checks matched. No packet, DNS leak, authenticated access, or selected-node proof.",checks.len());
            return Ok(if pass == checks.len() { 0 } else { 2 });
        }
        if a.first().is_some_and(|x| x == "--compose-policy") {
            if a.len() != 6 {
                return Err(
                    "Usage: --compose-policy runtime core proposal parent new-script".into(),
                );
            }
            compose_from_files(
                Path::new(&a[1]),
                Path::new(&a[2]),
                Path::new(&a[3]),
                a[4].to_str().ok_or("Parent encoding")?,
                Path::new(&a[5]),
            )?;
            println!("POLICY_SCRIPT_CREATED: core validated; stage only, no live change");
            return Ok(0);
        }
        if a.first().is_some_and(|x| x == "--parents") {
            if a.len() != 2 {
                return Err("Usage: --parents runtime".into());
            }
            let c = read_yaml(Path::new(&a[1]))?;
            if let Some(gs) = c.get("proxy-groups").and_then(Value::as_sequence) {
                for g in gs.iter().filter_map(Value::as_mapping) {
                    let n = get(g, "name").and_then(Value::as_str).unwrap_or("");
                    if !n.is_empty()
                        && n != "AI-固定出口"
                        && !n.starts_with("OCO-")
                        && get(g, "type").and_then(Value::as_str) == Some("select")
                        && get(g, "proxies")
                            .and_then(Value::as_sequence)
                            .is_some_and(|s| !s.is_empty())
                    {
                        println!("{}", safe_text(n))
                    }
                }
            }
            return Ok(0);
        }
        if a.first().is_some_and(|x| x == "--merge-safe") {
            if a.len() != 3 {
                return Err("Usage: --merge-safe <source> <new destination>".into());
            }
            let src = parse_merge(&read_bounded(Path::new(&a[1]))?)?;
            let (v, n) = merge_safe(&src)?;
            if n == 0 {
                println!("NO_CHANGE");
                return Ok(3);
            }
            create_yaml(Path::new(&a[2]), &v)?;
            println!("ADDED {n} missing settings; no existing values changed. Comments/format not preserved.");
            return Ok(0);
        }
        if a.first().is_some_and(|x| x == "--selftest") {
            let fixture:Value=serde_yaml_ng::from_str("proxies:\n- {name: valid, type: anytls, server: example.test, port: 443, password: synthetic}\n- {name: direct, type: direct, server: example.test, port: 443}\n- {name: chained, type: vless, server: example.test, port: 443, dialer-proxy: x}\n- {name: dup, type: anytls, server: example.test, port: 443}\n- {name: dup, type: anytls, server: example.test, port: 443}\n").map_err(|_|"Fixture parse")?;
            let s = select(fixture)?;
            if s.len() != 1 {
                return Err("Selection assertion".into());
            }
            let c: Value = serde_yaml_ng::from_str(&isolated(&s[0], 43210)?)
                .map_err(|_| "Fixture serialize")?;
            let m = c.as_mapping().ok_or("Fixture mapping")?;
            if get(m, "external-controller").is_some()
                || get(m, "allow-lan").and_then(Value::as_bool) != Some(false)
                || get(m, "tun")
                    .and_then(Value::as_mapping)
                    .and_then(|x| get(x, "enable"))
                    .and_then(Value::as_bool)
                    != Some(false)
            {
                return Err("Isolation assertion".into());
            }
            assert_eq!(batch_range(69, 12), Some(66..69));
            assert_eq!(batch_range(69, 13), None);
            assert_eq!(batch_range(69, 0), None);
            assert!(parse_probe("204", "204|0.5|0|0", 0, 204, None)?.ok);
            assert!(!parse_probe("HTTP", "403|0.5|20|40", 0, 200, None)?.ok);
            assert!(!parse_probe("download", "200|1|1024|1024", 0, 200, Some(1048576))?.ok);
            assert!(parse_probe("invalid", "200|NaN|1|2", 0, 200, None).is_err());
            let old:Value=serde_yaml_ng::from_str("dns: {enable: false}\nprofile: {store-selected: false, extra: 42}\nother: [1, 2]\n").map_err(|_|"Fixture")?;
            let (merged, n) = merge_safe(&old)?;
            assert_eq!(n, 2);
            assert_eq!(merged["dns"], old["dns"]);
            assert_eq!(merged["other"], old["other"]);
            assert_eq!(merged["profile"]["store-selected"], Value::Bool(false));
            assert_eq!(merged["profile"]["extra"], old["profile"]["extra"]);
            assert_eq!(merge_safe(&merged)?.1, 0);
            assert!(merge_safe(&serde_yaml_ng::from_str("profile: false").unwrap()).is_err());
            let groups = policy_groups(&[
                ("a".into(), 100.0, Some(1.0)),
                ("b".into(), 90.0, Some(2.0)),
                ("c".into(), 200.0, None),
            ]);
            assert_eq!(groups[1]["proxies"][0], key("b"));
            assert_eq!(groups[2]["proxies"][0], key("b"));
            let fixture:Value=serde_yaml_ng::from_str("proxies: [{name: a},{name: b},{name: c}]\nproxy-groups: []\nrules: [MATCH,DIRECT]\n").unwrap();
            let candidate = policy_candidate(&fixture, &groups)?;
            assert_eq!(candidate["rules"], fixture["rules"]);
            assert_eq!(candidate["proxies"], fixture["proxies"]);
            assert!(policy_candidate(&candidate, &groups).is_err());
            assert_eq!(
                hash(b"abc")?,
                "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
            );
            assert_eq!(canon(&key("A"), 0)?, "s0041;");
            let mut cfg: Value =
                serde_yaml_ng::from_str(include_str!("../../presets/Merge.yaml")).unwrap();
            cfg["proxies"] = serde_yaml_ng::from_str("[{name: fixture, type: vless}]").unwrap();
            cfg["proxy-groups"] = serde_yaml_ng::from_str(
                "[{name: 'AI-固定出口',type: select,proxies: [fixture],empty-fallback: REJECT}]",
            )
            .unwrap();
            cfg["rules"] = Value::Sequence(
                [
                    "chatgpt.com",
                    "openai.com",
                    "oaistatic.com",
                    "oaiusercontent.com",
                    "oaistatsig.com",
                    "cdn.openaimerge.com",
                ]
                .iter()
                .map(|d| key(&format!("DOMAIN-SUFFIX,{d},AI-固定出口")))
                .collect(),
            );
            assert!(runtime_checks(&cfg).iter().all(|x| x.1));
            cfg["proxy-groups"][0]["proxies"] = serde_yaml_ng::from_str("[DIRECT]").unwrap();
            assert_eq!(runtime_checks(&cfg).iter().filter(|x| !x.1).count(), 1);
            cfg["rules"][0] = key("MATCH,DIRECT");
            assert_eq!(runtime_checks(&cfg).iter().filter(|x| !x.1).count(), 2);
            for input in [
                "foo: &x 1\nbar: *x",
                "foo: 1\nfoo: 2",
                "profile: !custom {}",
            ] {
                let value = parse_merge(input);
                assert!(value.is_err() || merge_safe(&value.unwrap()).is_err());
            }
            let a = AtomicU64::new(0);
            assert!(reserve(&a, 6, 10));
            assert!(!reserve(&a, 5, 10));
            assert!(reserve(&a, 4, 10));
            assert_eq!(a.load(Ordering::Relaxed), 10);
            println!("NODE_QUALITY_SELFTEST_OK");
            return Ok(0);
        }
        if a.len() < 3 || (a[0] != "--scan" && a[0] != "--list") {
            return Err(
                "Usage: --list <runtime YAML> <core> | --scan <runtime YAML> <core> --batch N [--deep] [--yes] | --selftest".into(),
            );
        }
        let config = PathBuf::from(&a[1]);
        let exe = PathBuf::from(&a[2]);
        check_core(&exe)?;
        let s = read_bounded(&config)?;
        let runtime: Value = serde_yaml_ng::from_str(s.trim_start_matches('\u{feff}'))
            .map_err(|_| "YAML parse failed (details hidden)")?;
        let nodes = select(runtime.clone())?;
        if nodes.is_empty() {
            return Err("No eligible inline nodes".into());
        }
        let count = nodes.len();
        let total = runtime
            .get("proxies")
            .and_then(Value::as_sequence)
            .map_or(0, Vec::len);
        println!(
            "COVERAGE eligible={count} inline_total={total} excluded={}",
            total.saturating_sub(count)
        );
        let batches = count.div_ceil(6);
        if a[0] == "--list" {
            println!("{count} eligible inline nodes / {batches} batches; unsupported/chained/duplicate nodes are excluded.");
            for (i, n) in nodes.iter().enumerate() {
                println!(
                    "Batch {} | #{} {} [{}] | TLS bypass: {:?}",
                    i / 6 + 1,
                    n.index,
                    n.name,
                    n.proto,
                    n.skip
                );
            }
            return Ok(0);
        }
        let mut batch = 1usize;
        let mut deep = false;
        let mut all = false;
        let mut auto = false;
        let mut yes = false;
        let mut proposal: Option<PathBuf> = None;
        let mut i = 3;
        while i < a.len() {
            if a[i] == "--batch" {
                i += 1;
                batch = a
                    .get(i)
                    .and_then(|x| x.to_str())
                    .and_then(|s| s.parse().ok())
                    .ok_or("Invalid batch")?;
            } else if a[i] == "--auto" {
                auto = true;
            } else if a[i] == "--all" {
                all = true;
            } else if a[i] == "--deep" {
                deep = true;
            } else if a[i] == "--recommend" {
                i += 1;
                proposal = Some(PathBuf::from(a.get(i).ok_or("Missing proposal output")?));
            } else if a[i] == "--yes" {
                yes = true;
            } else {
                return Err("Unknown argument".into());
            }
            i += 1;
        }
        if auto && (proposal.is_none() || all || deep || count > 120) {
            return Err("Auto recommendation requires --recommend and <=120 eligible nodes".into());
        }
        if proposal.is_some() && (all || deep) {
            return Err("Recommendation mode is batch-only, not deep/all".into());
        }
        let range = if auto {
            0..count
        } else if all {
            if deep || count > 120 {
                return Err("All-node screening limited to 120 eligible nodes and no deep mode; use batches".into());
            }
            0..count
        } else {
            batch_range(count, batch).ok_or("Batch out of range")?
        };
        let nodes = &nodes[range];
        if auto {
            println!("AUTO: up to 120 nodes, 3 worker cores and 3 HTTPS requests each, then repeat top 6 with two downloads. Max 36 MiB response cap; no automatic switching.");
        } else if all {
            println!("All {} eligible nodes: two 204 requests each, sequential, response cap <=15 MiB (protocol overhead excluded). May take many minutes.",nodes.len());
        } else {
            println!("Batch {batch}/{batches}: {} nodes, two 204 requests each. Deep mode adds <=3 MiB per successful node; total response cap <=19 MiB.",nodes.len());
        }
        if proposal.is_some() && !auto {
            println!("Recommendation: 3 small requests + 2 x 1 MiB downloads per successful node, max 13.125 MiB response budget per batch; no service-specific or trust guarantee. Writes a private candidate file only.");
        }
        println!("Main TUN may affect path. No automatic route change.");
        if !yes {
            print!("Proceed? [Y/N] ");
            io::stdout().flush().map_err(|_| "Prompt failed")?;
            let mut input = String::new();
            io::stdin()
                .read_line(&mut input)
                .map_err(|_| "Input failed")?;
            if !input.trim().eq_ignore_ascii_case("y") {
                println!("CANCELLED: no probes sent");
                return Ok(0);
            }
        }
        check_curl()?;
        if unsafe {
            windows_sys::Win32::System::Console::SetConsoleCtrlHandler(Some(console_cancel), 1)
        } == 0
        {
            return Err("Cancellation handler unavailable; no probes sent".into());
        }
        let _ = DEADLINE.set(Instant::now());
        println!("Ctrl+C stops new probes; active requests finish within their timeout. 30-minute admission deadline.");
        println!(
            "Measurement start (Unix UTC seconds): {}",
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|x| x.as_secs())
                .unwrap_or(0)
        );
        let selected;
        let nodes = if auto {
            let ranked = auto_screen(nodes, &exe);
            println!("AUTO_SCREEN {} / {} passed 3/3", ranked.len(), nodes.len());
            selected = ranked
                .into_iter()
                .take(6)
                .map(|(i, _)| &nodes[i])
                .collect::<Vec<_>>();
            selected
        } else {
            nodes.iter().collect::<Vec<_>>()
        };
        let mut complete = 0;
        let mut fully = 0;
        let mut ranking = Vec::new();
        let mut evidence = Vec::new();
        for n in &nodes {
            if stopped() {
                break;
            }
            println!(
                "#{} {} [{}], configured skip-cert-verify: {:?}",
                n.index, n.name, n.proto, n.skip
            );
            match test(n, &exe, deep, proposal.is_some(), true) {
                Ok(rows) => {
                    for r in &rows {
                        println!("{}", r.line());
                    }
                    let small = rows
                        .iter()
                        .filter(|r| r.label == "204" && r.ok)
                        .collect::<Vec<_>>();
                    let ok = small.len();
                    if proposal.is_some() {
                        if ok == 3 {
                            let mut times =
                                small.iter().map(|r| r.sec * 1000.0).collect::<Vec<_>>();
                            times.sort_by(f64::total_cmp);
                            let mut downloads = rows
                                .iter()
                                .filter(|r| r.label == "Download" && r.ok)
                                .map(|r| r.speed / 1e6)
                                .collect::<Vec<_>>();
                            downloads.sort_by(f64::total_cmp);
                            let d = if downloads.len() == 2 {
                                Some((downloads[0] + downloads[1]) / 2.0)
                            } else {
                                None
                            };
                            let exact_name = get(&n.data, "name")
                                .and_then(Value::as_str)
                                .ok_or("Missing exact name")?
                                .to_string();
                            evidence.push((exact_name, times[1], d));
                        }
                        println!("  {ok}/3 expected, recommendation evidence only");
                        continue;
                    }
                    let median = if ok == 2 {
                        Some((small[0].sec + small[1].sec) * 500.0)
                    } else {
                        None
                    };
                    let download = rows
                        .iter()
                        .find(|r| r.label == "Download" && r.ok && r.bytes == 1048576.0)
                        .map(|r| r.speed / 1e6);
                    let app = rows
                        .iter()
                        .find(|r| r.label == "ChatGPT HTTP")
                        .map(|r| r.ok);
                    let state = if ok == 2 && n.skip == Some(false) {
                        "INITIAL_CANDIDATE (explicit TLS verification; not independent identity proof)"
                    } else if ok == 2 && n.skip == Some(true) {
                        "INITIAL_CANDIDATE_WITH_TLS_BYPASS"
                    } else if ok == 2 {
                        "INITIAL_CANDIDATE (TLS config unspecified; identity unproven)"
                    } else {
                        "RETEST_OR_UNAVAILABLE"
                    };
                    println!("  {ok}/2 expected; {state}");
                    if let Some(m) = median {
                        complete += 1;
                        ranking.push((n.index, m, download, app, n.skip));
                        if !deep || (download.is_some() && app == Some(true)) {
                            fully += 1;
                        }
                    }
                }
                Err(e) => println!("  UNAVAILABLE: {e}"),
            }
        }
        report_budget();
        if stopped() {
            println!(
                "PARTIAL: cancelled, budget exhausted or deadline reached; no proposal emitted"
            );
            return Ok(2);
        }
        if let Some(path) = proposal {
            if evidence.is_empty() {
                println!("No sufficiently available nodes, no proposal");
                return Ok(2);
            }
            if read_bounded(&config)? != s {
                return Err("Runtime changed during testing, no proposal".into());
            }
            let groups = policy_groups(&evidence);
            let candidate = policy_candidate(&runtime, &groups)?;
            validate_candidate(&config, &exe, &runtime, &candidate)?;
            // Output only group fragment, not credentials or full runtime. User must review before integration.
            create_yaml(&path, &policy_envelope(groups, &s)?)?;
            println!("{} / {} nodes passed 3 small probes; {} passed 2 downloads. Core accepted additive groups in isolated runtime. Proposal only; do not replace entire Merge.yaml with this fragment.",evidence.len(),nodes.len(),evidence.iter().filter(|r|r.2.is_some()).count());
            return Ok(0);
        }
        ranking.sort_by(|a, b| a.1.total_cmp(&b.1));
        println!("Initial candidates ranked by successful median total latency, NOT trust or long-term throughput:");
        for (id, ms, down, http, tls) in ranking {
            println!("  #{id} | {ms:.1} ms | download MB/s {down:?} | app HTTP expected {http:?} | skip-cert-verify {tls:?}");
        }
        println!("{complete}/{} passed both small requests; {fully}/{} met requested test scope. No node switching, no IPPure batch, no persistent report.",nodes.len(),nodes.len());
        Ok(if fully == nodes.len() { 0 } else { 2 })
    }
    #[cfg(test)]
    mod tests {
        use super::*;
        #[test]
        fn cancellation_flag_stops_admission() {
            assert!(!CANCELLED.load(Ordering::Relaxed));
            assert_eq!(unsafe { console_cancel(0) }, 1);
            assert!(stopped());
            CANCELLED.store(false, Ordering::Relaxed);
        }
        #[test]
        fn budget_is_atomic_and_bounded() {
            let n = AtomicU64::new(0);
            thread::scope(|s| {
                for _ in 0..8 {
                    s.spawn(|| {
                        for _ in 0..100 {
                            reserve(&n, 1, 123);
                        }
                    });
                }
            });
            assert_eq!(n.load(Ordering::Relaxed), 123);
        }
        #[test]
        fn duplicate_and_alias_refusal() {
            assert!(parse_merge("x: 1\nx: 2").is_err());
            assert!(parse_merge("x: &a 1\ny: *a").is_err());
        }
        #[test]
        fn case_alias_is_refused() {
            for t in [
                "TCP-Concurrent: false",
                "Profile: {}",
                "x: 1\nX: 2",
                "profile: {Store-Selected: false}",
            ] {
                assert!(merge_safe(&parse_merge(t).unwrap()).is_err());
            }
        }
        #[test]
        fn graph_mutations_detected() {
            let v:Value=serde_yaml_ng::from_str("proxies: [{name: p}]\nproxy-groups: [{name: a, proxies: [b, missing], use: [unknown]}, {name: b, proxies: [a]}]\nrules: ['DOMAIN,example.test,not-found','MATCH,a']").unwrap();
            let a = audit_graph(&v).unwrap();
            assert_eq!(
                (
                    a.missing_member,
                    a.missing_provider,
                    a.cycles,
                    a.missing_simple_rule_target
                ),
                (1, 1, 2, 1)
            );
        }
        #[test]
        fn merge_preserves_explicit() {
            let v = parse_merge(
                "profile: {store-selected: false}\ntcp-concurrent: false\nextra: [1,2]",
            )
            .unwrap();
            let (m, n) = merge_safe(&v).unwrap();
            assert_eq!(n, 1);
            assert_eq!(m["extra"], v["extra"]);
            assert_eq!(m["tcp-concurrent"], v["tcp-concurrent"]);
            assert_eq!(
                m["profile"]["store-selected"],
                v["profile"]["store-selected"]
            );
        }
    }
}
fn main() {
    #[cfg(windows)]
    match app::run() {
        Ok(c) => std::process::exit(c),
        Err(e) => {
            eprintln!("{e}");
            std::process::exit(1)
        }
    }
    #[cfg(not(windows))]
    {
        eprintln!("Windows only");
        std::process::exit(1)
    }
}
