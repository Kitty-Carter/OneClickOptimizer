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
        Security::Cryptography::{BCryptGenRandom, BCRYPT_USE_SYSTEM_PREFERRED_RNG},
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
        m.get(&key(k))
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
                m.len() <= 128 && m.iter().all(|(k, v)| k.is_string() && plain(v, depth + 1))
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
        // Two per protocol, prioritize nodes without an explicit verification bypass.
        let mut chosen = Vec::new();
        for proto in ["anytls", "vless", "hysteria2"] {
            let mut group = out.iter().filter(|n| n.proto == proto).collect::<Vec<_>>();
            group.sort_by_key(|n| n.skip == Some(true));
            for n in group.into_iter().take(2) {
                chosen.push(n.index);
            }
        }
        Ok(out
            .into_iter()
            .filter(|n| chosen.contains(&n.index))
            .collect())
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
                || bytes < 4
                || bytes > 8 * 1024 * 1024
            {
                return false;
            }
            let mut b = vec![0u64; (bytes as usize + 7) / 8];
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
    fn probe(port: u16) -> Result<(bool, String, f64), String> {
        let proxy = format!("http://127.0.0.1:{port}");
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
            "65536",
            "--output",
            "NUL",
            "--write-out",
            "%{http_code}|%{time_total}",
            "https://cp.cloudflare.com/generate_204",
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
        let o = c.output().map_err(|_| "curl unavailable")?;
        let s = String::from_utf8_lossy(&o.stdout);
        let (h, t) = s.trim().split_once('|').ok_or("Invalid curl response")?;
        let elapsed = t
            .parse::<f64>()
            .ok()
            .filter(|x| x.is_finite() && *x >= 0.0)
            .ok_or("Invalid elapsed time")?;
        Ok((
            o.status.success() && h == "204",
            format!("HTTP {h} / curl {}", o.status.code().unwrap_or(-1)),
            elapsed,
        ))
    }
    fn test(node: &Node, exe: &Path) -> Result<Vec<(bool, String, f64)>, String> {
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
        for _ in 0..2 {
            if !owns(port, proc.0.id()) {
                return Err("Listener changed".into());
            }
            rows.push(probe(port)?);
        }
        Ok(rows)
    }
    pub fn run() -> Result<i32, String> {
        let a: Vec<_> = env::args_os().skip(1).collect();
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
            println!("NODE_QUALITY_SELFTEST_OK");
            return Ok(0);
        }
        if a.len() < 3 || a[0] != "--scan" {
            return Err(
                "Usage: --scan <runtime YAML> <verge-mihomo.exe> [--yes] | --selftest".into(),
            );
        }
        let config = PathBuf::from(&a[1]);
        let exe = PathBuf::from(&a[2]);
        if exe
            .file_name()
            .and_then(|x| x.to_str())
            .is_none_or(|s| !s.eq_ignore_ascii_case("verge-mihomo.exe"))
        {
            return Err("Explicit bundled core path required".into());
        }
        let v = Command::new(&exe)
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
        if fs::metadata(&config)
            .map_err(|_| "Config unavailable")?
            .len()
            > 8 * 1024 * 1024
        {
            return Err("Config too large".into());
        }
        let s = fs::read_to_string(&config).map_err(|_| "Config read failed")?;
        let nodes = select(
            serde_yaml_ng::from_str(s.trim_start_matches('\u{feff}'))
                .map_err(|_| "YAML parse failed (details hidden)")?,
        )?;
        if nodes.is_empty() {
            return Err("No eligible inline nodes".into());
        }
        println!("{} candidates, two Cloudflare HTTPS 204 requests each; response cap <= 768 KiB, excludes handshake and transport overhead. Main TUN remains active; not native-path or throughput proof.",nodes.len());
        if !a.get(3).is_some_and(|x| x == "--yes") {
            print!("Proceed? [Y/N] ");
            io::stdout().flush().map_err(|_| "Prompt failed")?;
            let mut yes = String::new();
            io::stdin()
                .read_line(&mut yes)
                .map_err(|_| "Input failed")?;
            if !yes.trim().eq_ignore_ascii_case("y") {
                println!("Cancelled");
                return Ok(0);
            }
        }
        println!(
            "Measurement start (Unix UTC seconds): {}",
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|x| x.as_secs())
                .unwrap_or(0)
        );
        let mut complete = 0;
        for n in &nodes {
            println!(
                "#{} {} [{}], configured skip-cert-verify: {:?}",
                n.index, n.name, n.proto, n.skip
            );
            match test(n, &exe) {
                Ok(rows) => {
                    let ok = rows.iter().filter(|x| x.0).count();
                    for (_, state, t) in &rows {
                        println!("  {state}; {:.1} ms", t * 1000.0)
                    }
                    let mut times = rows
                        .iter()
                        .filter(|x| x.0)
                        .map(|x| x.2 * 1000.0)
                        .collect::<Vec<_>>();
                    times.sort_by(f64::total_cmp);
                    if times.len() == 2 {
                        println!(
                            "  median successful total: {:.1} ms",
                            (times[0] + times[1]) / 2.0
                        );
                    }
                    let state = if ok == 2 && n.skip != Some(true) {
                        "INITIAL_CANDIDATE (no explicit verification bypass; authentication not proven)"
                    } else if ok == 2 {
                        "INITIAL_CANDIDATE_WITH_TLS_BYPASS (not trusted)"
                    } else {
                        "RETEST_OR_UNAVAILABLE"
                    };
                    println!("  {ok}/2 expected; {state}; no automatic selection");
                    if ok == 2 {
                        complete += 1;
                    }
                }
                Err(e) => println!("  UNAVAILABLE: {e}"),
            }
        }
        println!("{complete}/{} candidates passed both. No route changes. No IPPure batch requests. No report persisted.",nodes.len());
        Ok(if complete == nodes.len() { 0 } else { 2 })
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
