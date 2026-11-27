use std::time::{Duration, Instant};

fn rate(old: u64, new: u64, seconds: f64) -> Option<f64> {
    if !seconds.is_finite() || !(0.001..=30.0).contains(&seconds) {
        return None;
    }
    new.checked_sub(old).map(|n| n as f64 / seconds)
}
fn accumulated(total: u64, old: u64, new: u64, seconds: f64) -> u64 {
    if rate(old, new, seconds).is_some() {
        total.saturating_add(new - old)
    } else {
        total
    }
}
fn cpu(old: [u64; 3], new: [u64; 3]) -> Option<f64> {
    let idle = new[0].checked_sub(old[0])?;
    let kernel = new[1].checked_sub(old[1])?;
    let user = new[2].checked_sub(old[2])?;
    let total = kernel.checked_add(user)?;
    if total == 0 || idle > total {
        return None;
    }
    Some(100.0 * (total - idle) as f64 / total as f64)
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn normal_rate() {
        assert_eq!(rate(100, 1100, 2.0), Some(500.0));
    }
    #[test]
    fn idle_rate() {
        assert_eq!(rate(5, 5, 1.0), Some(0.0));
    }
    #[test]
    fn reset() {
        assert_eq!(rate(100, 1, 2.0), None);
    }
    #[test]
    fn invalid_interval() {
        for x in [0.0, -1.0, 31.0, f64::NAN, f64::INFINITY] {
            assert_eq!(rate(0, 10, x), None);
        }
    }
    #[test]
    fn cpu_delta() {
        assert_eq!(cpu([0, 0, 0], [25, 50, 50]), Some(75.0));
    }
    #[test]
    fn cpu_invalid() {
        assert_eq!(cpu([0, 0, 0], [5, 2, 2]), None);
        assert_eq!(cpu([0, 0, 0], [0, 0, 0]), None);
        assert_eq!(cpu([1, 0, 0], [0, 0, 0]), None);
    }
    #[test]
    fn session_accumulator() {
        assert_eq!(accumulated(100, 200, 400, 2.0), 300);
        assert_eq!(accumulated(100, 200, 1, 2.0), 100);
        assert_eq!(accumulated(100, 200, 400, 31.0), 100);
        assert_eq!(accumulated(u64::MAX - 1, 0, 10, 2.0), u64::MAX);
    }
    #[test]
    fn large_counters() {
        assert_eq!(rate(u64::MAX - 100, u64::MAX, 2.0), Some(50.0));
    }
}

#[cfg(windows)]
mod win {
    use super::*;
    use std::{
        cell::RefCell,
        collections::HashMap,
        fmt::Write as _,
        mem::{size_of, zeroed},
        ptr::{null, null_mut},
        sync::mpsc::{self, Receiver, TrySendError},
    };
    use windows_sys::Win32::{
        Foundation::{
            CloseHandle, FILETIME, HANDLE, HWND, INVALID_HANDLE_VALUE, LPARAM, LRESULT, WPARAM,
        },
        Graphics::Gdi::{GetStockObject, COLOR_WINDOW, DEFAULT_GUI_FONT},
        NetworkManagement::IpHelper::{FreeMibTable, GetIfTable2, MIB_IF_ROW2, MIB_IF_TABLE2},
        System::{
            Diagnostics::ToolHelp::{
                CreateToolhelp32Snapshot, Process32FirstW, Process32NextW, PROCESSENTRY32W,
                TH32CS_SNAPPROCESS,
            },
            LibraryLoader::GetModuleHandleW,
            Performance::{
                PdhAddEnglishCounterW, PdhCloseQuery, PdhCollectQueryData,
                PdhGetFormattedCounterValue, PdhOpenQueryW, PDH_FMT_COUNTERVALUE, PDH_FMT_DOUBLE,
                PDH_HCOUNTER, PDH_HQUERY,
            },
            Power::{GetSystemPowerStatus, SYSTEM_POWER_STATUS},
            ProcessStatus::{K32GetProcessMemoryInfo, PROCESS_MEMORY_COUNTERS_EX},
            SystemInformation::{GlobalMemoryStatusEx, MEMORYSTATUSEX},
            Threading::{
                GetProcessTimes, GetSystemTimes, OpenProcess, PROCESS_QUERY_LIMITED_INFORMATION,
                PROCESS_VM_READ,
            },
        },
        UI::WindowsAndMessaging::*,
    };
    fn wide(s: &str) -> Vec<u16> {
        s.encode_utf16().chain(Some(0)).collect()
    }
    fn ft(f: FILETIME) -> u64 {
        ((f.dwHighDateTime as u64) << 32) | f.dwLowDateTime as u64
    }
    fn name(s: &[u16]) -> String {
        String::from_utf16_lossy(&s[..s.iter().position(|x| *x == 0).unwrap_or(s.len())])
            .chars()
            .map(|c| if c.is_control() { ' ' } else { c })
            .collect()
    }
    #[derive(Clone)]
    struct Nic {
        key: u64,
        name: String,
        kind: &'static str,
        up: bool,
        rx: u64,
        tx: u64,
        mtu: u32,
        link: u64,
    }
    struct Table(*mut MIB_IF_TABLE2);
    impl Drop for Table {
        fn drop(&mut self) {
            unsafe {
                FreeMibTable(self.0.cast());
            }
        }
    }
    fn nics() -> Result<Vec<Nic>, u32> {
        unsafe {
            let mut p = null_mut();
            let code = GetIfTable2(&mut p);
            if code != 0 || p.is_null() {
                return Err(code);
            }
            let _guard = Table(p);
            let n = (*p).NumEntries as usize;
            if n > 65536 {
                return Err(13);
            }
            let rows =
                std::slice::from_raw_parts(std::ptr::addr_of!((*p).Table).cast::<MIB_IF_ROW2>(), n);
            Ok(rows
                .iter()
                .filter(|r| {
                    r.Type != 24
                        && r.InterfaceAndOperStatusFlags._bitfield & 2 == 0
                        && (r.OperStatus == 1 || r.InterfaceAndOperStatusFlags._bitfield & 1 != 0)
                })
                .map(|r| {
                    let alias = name(&r.Alias);
                    let kind = if r.Type == 131
                        || alias.eq_ignore_ascii_case("Mihomo")
                        || alias.eq_ignore_ascii_case("Meta")
                    {
                        "Tunnel candidate"
                    } else if r.InterfaceAndOperStatusFlags._bitfield & 1 != 0 {
                        "Physical"
                    } else {
                        "Other"
                    };
                    Nic {
                        key: r.InterfaceLuid.Value,
                        name: alias,
                        kind,
                        up: r.OperStatus == 1,
                        rx: r.InOctets,
                        tx: r.OutOctets,
                        mtu: r.Mtu,
                        link: r.ReceiveLinkSpeed,
                    }
                })
                .collect())
        }
    }
    fn fmt_rate(n: Option<f64>) -> String {
        match n {
            Some(v) if v >= 1e6 => format!("{:.2} MB/s", v / 1e6),
            Some(v) => format!("{:.1} KB/s", v / 1e3),
            None => "N/A".into(),
        }
    }
    fn percent(p: Option<f64>) -> String {
        p.map(|x| format!("{x:.1}%"))
            .unwrap_or_else(|| "N/A".into())
    }
    struct Handle(HANDLE);
    impl Drop for Handle {
        fn drop(&mut self) {
            unsafe {
                CloseHandle(self.0);
            }
        }
    }
    // Read only public process counters when service process handles are denied.
    struct CorePdh {
        query: PDH_HQUERY,
        pid: PDH_HCOUNTER,
        cpu: PDH_HCOUNTER,
        ws: PDH_HCOUNTER,
        private: PDH_HCOUNTER,
    }
    impl Drop for CorePdh {
        fn drop(&mut self) {
            unsafe {
                PdhCloseQuery(self.query);
            }
        }
    }
    impl CorePdh {
        fn new() -> Option<Self> {
            unsafe {
                let mut q = null_mut();
                if PdhOpenQueryW(null(), 0, &mut q) != 0 {
                    return None;
                }
                let mut d = Self {
                    query: q,
                    pid: null_mut(),
                    cpu: null_mut(),
                    ws: null_mut(),
                    private: null_mut(),
                };
                for (path, slot) in [
                    (r"\Process(verge-mihomo)\ID Process", &mut d.pid),
                    (r"\Process(verge-mihomo)\% Processor Time", &mut d.cpu),
                    (r"\Process(verge-mihomo)\Working Set", &mut d.ws),
                    (r"\Process(verge-mihomo)\Private Bytes", &mut d.private),
                ] {
                    if PdhAddEnglishCounterW(q, wide(path).as_ptr(), 0, slot) != 0 {
                        *slot = null_mut();
                    }
                }
                if d.pid.is_null() {
                    return None;
                }
                Some(d)
            }
        }
        fn sample(&mut self, pid: u32, logical: f64) -> (Option<f64>, Option<(u64, u64)>) {
            if unsafe { PdhCollectQueryData(self.query) } != 0
                || Disk::value(self.pid) != Some(pid as f64)
            {
                return (None, None);
            }
            let c = Disk::value(self.cpu).map(|x| (x / logical).clamp(0.0, 100.0));
            let m = Disk::value(self.ws)
                .zip(Disk::value(self.private))
                .map(|(w, p)| (w as u64, p as u64));
            (c, m)
        }
    }
    #[derive(Default)]
    struct CoreSampler {
        previous: HashMap<(u32, u64), u64>,
        tick: Option<Instant>,
        fallback: Option<CorePdh>,
        fallback_pid: Option<u32>,
        fallback_tick: Option<Instant>,
        fallback_data: (Option<f64>, Option<(u64, u64)>),
    }
    impl CoreSampler {
        fn sample(&mut self) -> String {
            unsafe {
                let snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
                if snapshot == INVALID_HANDLE_VALUE {
                    self.previous.clear();
                    self.tick = None;
                    self.fallback = None;
                    self.fallback_pid = None;
                    self.fallback_tick = None;
                    self.fallback_data = (None, None);
                    return "Mihomo: N/A (process snapshot)".into();
                }
                let _snapshot = Handle(snapshot);
                let mut row: PROCESSENTRY32W = zeroed();
                row.dwSize = size_of::<PROCESSENTRY32W>() as u32;
                if Process32FirstW(snapshot, &mut row) == 0 {
                    self.previous.clear();
                    self.tick = None;
                    self.fallback = None;
                    self.fallback_pid = None;
                    self.fallback_tick = None;
                    self.fallback_data = (None, None);
                    return "Mihomo: N/A (process enumeration)".into();
                }
                let now = Instant::now();
                let sec = self
                    .tick
                    .map(|t| now.duration_since(t).as_secs_f64())
                    .unwrap_or(0.0);
                let mut next = HashMap::new();
                let (mut count, mut readable, mut mem_count, mut matched) = (0, 0, 0, 0);
                let mut only_pid = 0;
                let (mut ws, mut private, mut delta) = (0u64, 0u64, 0u64);
                loop {
                    let exe = name(&row.szExeFile);
                    if exe.eq_ignore_ascii_case("verge-mihomo.exe") {
                        count += 1;
                        only_pid = row.th32ProcessID;
                        let h = OpenProcess(
                            PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_VM_READ,
                            0,
                            row.th32ProcessID,
                        );
                        let h = if h.is_null() {
                            OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, 0, row.th32ProcessID)
                        } else {
                            h
                        };
                        if !h.is_null() {
                            let _h = Handle(h);
                            let (mut created, mut exit, mut kernel, mut user) =
                                (zeroed(), zeroed(), zeroed(), zeroed());
                            if GetProcessTimes(h, &mut created, &mut exit, &mut kernel, &mut user)
                                != 0
                            {
                                readable += 1;
                                let key = (row.th32ProcessID, ft(created));
                                let t = ft(kernel).saturating_add(ft(user));
                                if let Some(d) =
                                    self.previous.get(&key).and_then(|o| t.checked_sub(*o))
                                {
                                    matched += 1;
                                    delta = delta.saturating_add(d);
                                }
                                next.insert(key, t);
                            }
                            let mut mem: PROCESS_MEMORY_COUNTERS_EX = zeroed();
                            mem.cb = size_of::<PROCESS_MEMORY_COUNTERS_EX>() as u32;
                            if K32GetProcessMemoryInfo(
                                h,
                                (&mut mem as *mut PROCESS_MEMORY_COUNTERS_EX).cast(),
                                mem.cb,
                            ) != 0
                            {
                                mem_count += 1;
                                ws = ws.saturating_add(mem.WorkingSetSize as u64);
                                private = private.saturating_add(mem.PrivateUsage as u64);
                            }
                        }
                    }
                    if Process32NextW(snapshot, &mut row) == 0 {
                        break;
                    }
                }
                self.previous = next;
                self.tick = Some(now);
                let logical = std::thread::available_parallelism()
                    .map(|n| n.get())
                    .unwrap_or(1) as f64;
                let mut pct = if count > 0
                    && readable == count
                    && matched == count
                    && (0.001..=30.0).contains(&sec)
                {
                    Some((100.0 * delta as f64 / 1e7 / sec / logical).clamp(0.0, 100.0))
                } else {
                    None
                };
                let mut memory = if count > 0 && mem_count == count {
                    Some((ws, private))
                } else {
                    None
                };
                let mut source = "handle";
                // Multiple same-name instances make legacy counter names ambiguous.
                if count == 1 && (pct.is_none() || memory.is_none()) {
                    if self.fallback_pid != Some(only_pid) {
                        self.fallback = None;
                        self.fallback_tick = None;
                        self.fallback_data = (None, None);
                        self.fallback_pid = Some(only_pid);
                    }
                    if self
                        .fallback_tick
                        .map(|t| t.elapsed() >= Duration::from_secs(4))
                        .unwrap_or(true)
                    {
                        if self.fallback.is_none() {
                            self.fallback = CorePdh::new();
                        }
                        self.fallback_data = self
                            .fallback
                            .as_mut()
                            .map(|q| q.sample(only_pid, logical))
                            .unwrap_or((None, None));
                        self.fallback_tick = Some(Instant::now());
                    }
                    if pct.is_none() {
                        pct = self.fallback_data.0;
                    }
                    if memory.is_none() {
                        memory = self.fallback_data.1;
                    }
                    source = "handle/PDH";
                } else {
                    self.fallback = None;
                    self.fallback_pid = None;
                    self.fallback_tick = None;
                    self.fallback_data = (None, None);
                }
                let memory = memory
                    .map(|(w, p)| {
                        format!(
                            "{:.1} MiB WS / {:.1} MiB private",
                            w as f64 / 1048576.0,
                            p as f64 / 1048576.0
                        )
                    })
                    .unwrap_or("N/A".into());
                format!(
                    "Mihomo: {count} process(es) | CPU {} | {memory} [{source}]",
                    percent(pct)
                )
            }
        }
    }
    struct Disk {
        query: PDH_HQUERY,
        idle: PDH_HCOUNTER,
        read: PDH_HCOUNTER,
        write: PDH_HCOUNTER,
    }
    impl Drop for Disk {
        fn drop(&mut self) {
            unsafe {
                PdhCloseQuery(self.query);
            }
        }
    }
    impl Disk {
        fn new() -> Option<Self> {
            unsafe {
                let mut q = null_mut();
                if PdhOpenQueryW(null(), 0, &mut q) != 0 {
                    return None;
                }
                let mut d = Self {
                    query: q,
                    idle: null_mut(),
                    read: null_mut(),
                    write: null_mut(),
                };
                for (path, slot) in [
                    (r"\PhysicalDisk(_Total)\% Idle Time", &mut d.idle),
                    (r"\PhysicalDisk(_Total)\Disk Read Bytes/sec", &mut d.read),
                    (r"\PhysicalDisk(_Total)\Disk Write Bytes/sec", &mut d.write),
                ] {
                    if PdhAddEnglishCounterW(q, wide(path).as_ptr(), 0, slot) != 0 {
                        *slot = null_mut();
                    }
                }
                if d.idle.is_null() && d.read.is_null() && d.write.is_null() {
                    return None;
                }
                Some(d)
            }
        }
        fn value(c: PDH_HCOUNTER) -> Option<f64> {
            if c.is_null() {
                return None;
            }
            unsafe {
                let mut v: PDH_FMT_COUNTERVALUE = zeroed();
                if PdhGetFormattedCounterValue(c, PDH_FMT_DOUBLE | 0x8000, null_mut(), &mut v) != 0
                    || v.CStatus > 1
                {
                    return None;
                }
                let x = v.Anonymous.doubleValue;
                (x.is_finite() && x >= 0.0).then_some(x)
            }
        }
        fn sample(&mut self) -> String {
            if unsafe { PdhCollectQueryData(self.query) } != 0 {
                return "Disk: N/A".into();
            }
            let busy = Self::value(self.idle)
                .filter(|x| *x <= 100.0)
                .map(|x| 100.0 - x);
            format!(
                "Disk _Total non-idle: {} | read {} | write {}",
                percent(busy),
                fmt_rate(Self::value(self.read)),
                fmt_rate(Self::value(self.write))
            )
        }
    }
    struct Sampler {
        prev_cpu: Option<[u64; 3]>,
        prev_nic: HashMap<u64, Nic>,
        tick: Option<Instant>,
        session: HashMap<u64, (u64, u64)>,
        core: CoreSampler,
        disk: Option<Disk>,
        disk_enabled: bool,
        disk_tick: Option<Instant>,
        disk_text: String,
    }
    impl Sampler {
        fn new(disk_enabled: bool) -> Self {
            Self {
                prev_cpu: None,
                prev_nic: HashMap::new(),
                tick: None,
                session: HashMap::new(),
                core: CoreSampler::default(),
                disk: None,
                disk_enabled,
                disk_tick: None,
                disk_text: "Disk: N/A (warming up)".into(),
            }
        }
        fn take(&mut self) -> (String, bool) {
            let mut out = String::new();
            let (cpu_now, mem, battery) = unsafe {
                let (mut i, mut k, mut u) = (zeroed(), zeroed(), zeroed());
                let c =
                    (GetSystemTimes(&mut i, &mut k, &mut u) != 0).then(|| [ft(i), ft(k), ft(u)]);
                let mut m: MEMORYSTATUSEX = zeroed();
                m.dwLength = size_of::<MEMORYSTATUSEX>() as u32;
                let m = (GlobalMemoryStatusEx(&mut m) != 0).then_some(m);
                let mut p: SYSTEM_POWER_STATUS = zeroed();
                let b = (GetSystemPowerStatus(&mut p) != 0 && p.BatteryLifePercent <= 100)
                    .then_some(p.BatteryLifePercent);
                (c, m, b)
            };
            let cpu_pct = self.prev_cpu.zip(cpu_now).and_then(|(a, b)| cpu(a, b));
            self.prev_cpu = cpu_now;
            let _ = writeln!(
                out,
                "CPU: {}    RAM: {}    Battery: {}",
                percent(cpu_pct),
                mem.map(|m| format!(
                    "{}% ({:.1}/{:.1} GiB used)",
                    m.dwMemoryLoad,
                    m.ullTotalPhys.saturating_sub(m.ullAvailPhys) as f64 / 1073741824.0,
                    m.ullTotalPhys as f64 / 1073741824.0
                ))
                .unwrap_or("N/A".into()),
                battery.map(|x| format!("{x}%")).unwrap_or("N/A".into())
            );
            let _ = writeln!(
                out,
                "\nActive and physical NICs | Physical and tunnel are NOT summed"
            );
            let rows = nics();
            let now = Instant::now();
            let seconds = self
                .tick
                .map(|x| now.duration_since(x).as_secs_f64())
                .unwrap_or(0.0);
            let ok = rows.is_ok();
            match rows {
                Ok(mut rows) => {
                    rows.sort_by_key(|x| (!x.up, x.kind, x.name.clone()));
                    let mut next = HashMap::new();
                    for n in rows {
                        let (rx, tx) = match self.prev_nic.get(&n.key) {
                            Some(o) if n.up && o.up && n.name == o.name => {
                                (rate(o.rx, n.rx, seconds), rate(o.tx, n.tx, seconds))
                            }
                            _ => (None, None),
                        };
                        let _ = writeln!(
                            out,
                            "\n{} [{}] {}",
                            n.name,
                            n.kind,
                            if n.up { "Up" } else { "Down / unavailable" }
                        );
                        let _ = writeln!(
                            out,
                            "  Down: {}   Up: {}   MTU: {}   RX link: {:.0} Mbps",
                            fmt_rate(rx),
                            fmt_rate(tx),
                            n.mtu,
                            n.link as f64 / 1e6
                        );
                        let total = self.session.entry(n.key).or_insert((0, 0));
                        if let Some(o) = self
                            .prev_nic
                            .get(&n.key)
                            .filter(|o| n.up && o.up && n.name == o.name)
                        {
                            total.0 = accumulated(total.0, o.rx, n.rx, seconds);
                            total.1 = accumulated(total.1, o.tx, n.tx, seconds);
                        }
                        let _ = writeln!(
                            out,
                            "  Session valid intervals: RX {:.2} MiB | TX {:.2} MiB",
                            total.0 as f64 / 1048576.0,
                            total.1 as f64 / 1048576.0
                        );
                        next.insert(n.key, n);
                    }
                    self.session.retain(|k, _| next.contains_key(k));
                    self.prev_nic = next;
                    self.tick = Some(now);
                }
                Err(code) => {
                    self.prev_nic.clear();
                    self.session.clear();
                    self.tick = None;
                    let _ = writeln!(out, "N/A (Win32 error {code})");
                }
            }
            let _ = writeln!(out, "\n{}", self.core.sample());
            if self.disk_enabled {
                if self
                    .disk_tick
                    .map(|t| t.elapsed() >= Duration::from_secs(6))
                    .unwrap_or(true)
                {
                    if self.disk.is_none() {
                        self.disk = Disk::new();
                    }
                    self.disk_text = self
                        .disk
                        .as_mut()
                        .map(|d| d.sample())
                        .unwrap_or("Disk: N/A (counter unavailable)".into());
                    self.disk_tick = Some(Instant::now());
                }
                let _ = writeln!(out, "{}", self.disk_text);
            } else {
                let _ = writeln!(out, "Disk: disabled (Lite mode)");
            }
            let _=writeln!(out,"\nRead-only / offline. NIC and CPU ~2 s; disk ~6 s. Session totals omit invalid intervals.\nMihomo CPU normalized by available logical CPUs. GPU: use hardware monitor.");
            (out, ok && cpu_now.is_some() && mem.is_some())
        }
    }
    struct Ui {
        rx: Receiver<(String, bool)>,
        started: Instant,
        edit: HWND,
        ticks: u32,
        good: u32,
        smoke: bool,
    }
    thread_local! {static UI:RefCell<Option<Ui>>=const{RefCell::new(None)};}
    unsafe extern "system" fn wnd(hwnd: HWND, msg: u32, w: WPARAM, l: LPARAM) -> LRESULT {
        unsafe {
            match msg {
                WM_SIZE => {
                    UI.with(|s| {
                        if let Some(u) = s.borrow().as_ref() {
                            if !u.edit.is_null() {
                                MoveWindow(
                                    u.edit,
                                    0,
                                    0,
                                    (l & 0xffff) as i32,
                                    ((l >> 16) & 0xffff) as i32,
                                    1,
                                );
                            }
                        }
                    });
                    0
                }
                WM_TIMER => {
                    let close = UI.with(|s| {
                        let mut b = s.borrow_mut();
                        let Some(u) = b.as_mut() else { return false };
                        if let Ok((text, ok)) = u.rx.try_recv() {
                            u.ticks += 1;
                            if ok {
                                u.good += 1;
                            }
                            SetWindowTextW(u.edit, wide(&text.replace('\n', "\r\n")).as_ptr());
                        }
                        u.smoke && (u.ticks >= 3 || u.started.elapsed() >= Duration::from_secs(20))
                    });
                    if close {
                        DestroyWindow(hwnd);
                    }
                    0
                }
                WM_DESTROY => {
                    KillTimer(hwnd, 1);
                    let code = UI.with(|s| {
                        s.borrow()
                            .as_ref()
                            .map(|u| if u.smoke && u.good < 3 { 1 } else { 0 })
                            .unwrap_or(1)
                    });
                    PostQuitMessage(code);
                    0
                }
                _ => DefWindowProcW(hwnd, msg, w, l),
            }
        }
    }
    fn gui(smoke: bool, disk: bool) -> Result<i32, String> {
        let (tx, rx) = mpsc::sync_channel(1);
        std::thread::spawn(move || {
            let mut sampler = Sampler::new(disk);
            loop {
                match tx.try_send(sampler.take()) {
                    Ok(()) | Err(TrySendError::Full(_)) => {}
                    Err(TrySendError::Disconnected(_)) => break,
                }
                std::thread::sleep(Duration::from_secs(2));
            }
        });
        unsafe {
            let inst = GetModuleHandleW(null());
            let class = wide("OCOClashNativeMonitor");
            let mut wc: WNDCLASSW = zeroed();
            wc.lpfnWndProc = Some(wnd);
            wc.hInstance = inst;
            wc.lpszClassName = class.as_ptr();
            wc.hbrBackground = (COLOR_WINDOW + 1) as _;
            wc.hCursor = LoadCursorW(null_mut(), IDC_ARROW);
            if RegisterClassW(&wc) == 0 {
                return Err("RegisterClassW failed".into());
            }
            let hwnd = CreateWindowExW(
                0,
                class.as_ptr(),
                wide("Clash Verge Rev - Native Monitor").as_ptr(),
                WS_OVERLAPPEDWINDOW,
                CW_USEDEFAULT,
                CW_USEDEFAULT,
                780,
                560,
                null_mut(),
                null_mut(),
                inst,
                null(),
            );
            if hwnd.is_null() {
                return Err("CreateWindowExW failed".into());
            }
            let edit = CreateWindowExW(
                WS_EX_CLIENTEDGE,
                wide("EDIT").as_ptr(),
                wide("Sampling...").as_ptr(),
                WS_CHILD
                    | WS_VISIBLE
                    | WS_VSCROLL
                    | ES_MULTILINE as u32
                    | ES_READONLY as u32
                    | ES_AUTOVSCROLL as u32,
                0,
                0,
                750,
                500,
                hwnd,
                null_mut(),
                inst,
                null(),
            );
            if edit.is_null() {
                DestroyWindow(hwnd);
                return Err("Edit creation failed".into());
            }
            SendMessageW(
                edit,
                WM_SETFONT,
                GetStockObject(DEFAULT_GUI_FONT) as usize,
                1,
            );
            UI.with(|s| {
                *s.borrow_mut() = Some(Ui {
                    rx,
                    started: Instant::now(),
                    edit,
                    ticks: 0,
                    good: 0,
                    smoke,
                })
            });
            if SetTimer(hwnd, 1, 250, None) == 0 {
                DestroyWindow(hwnd);
                return Err("SetTimer failed".into());
            }
            ShowWindow(hwnd, SW_SHOW);
            let mut msg: MSG = zeroed();
            loop {
                let n = GetMessageW(&mut msg, null_mut(), 0, 0);
                if n == 0 {
                    return Ok(msg.wParam as i32);
                }
                if n < 0 {
                    return Err("GetMessageW failed".into());
                }
                TranslateMessage(&msg);
                DispatchMessageW(&msg);
            }
        }
    }
    pub fn run() -> Result<i32, String> {
        let a: Vec<String> = std::env::args().skip(1).collect();
        let disk = !a.iter().any(|s| s == "--lite");
        match a.first().map(String::as_str) {
            None | Some("--gui") => gui(false, disk),
            Some("--smoke") => gui(true, disk),
            Some("--sample") | Some("--watch") => {
                let count = if a[0] == "--sample" {
                    2
                } else {
                    a.get(1)
                        .and_then(|x| x.parse::<u32>().ok())
                        .filter(|x| *x >= 2 && *x <= 600)
                        .ok_or("watch count must be 2..600")?
                };
                let mut s = Sampler::new(disk);
                let mut good = 0;
                for i in 0..count {
                    if i > 0 {
                        std::thread::sleep(Duration::from_secs(2));
                    }
                    let (t, ok) = s.take();
                    println!("SAMPLE {}\n{}", i + 1, t);
                    if ok {
                        good += 1;
                    }
                }
                Ok(if good == count { 0 } else { 1 })
            }
            _ => Err("Usage: --gui | --smoke | --sample | --watch 2..600 [--lite]".into()),
        }
    }
}
fn main() {
    #[cfg(windows)]
    match win::run() {
        Ok(code) => std::process::exit(code),
        Err(e) => {
            eprintln!("{e}");
            std::process::exit(1)
        }
    }
    #[cfg(not(windows))]
    {
        eprintln!("Windows only");
        std::process::exit(1);
    }
}
