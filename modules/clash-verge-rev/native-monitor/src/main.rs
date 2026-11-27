use std::time::{Duration, Instant};

fn rate(old: u64, new: u64, seconds: f64) -> Option<f64> {
    if !seconds.is_finite() || !(0.001..=30.0).contains(&seconds) {
        return None;
    }
    new.checked_sub(old).map(|n| n as f64 / seconds)
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
    };
    use windows_sys::Win32::{
        Foundation::{FILETIME, HWND, LPARAM, LRESULT, WPARAM},
        Graphics::Gdi::{GetStockObject, COLOR_WINDOW, DEFAULT_GUI_FONT},
        NetworkManagement::IpHelper::{FreeMibTable, GetIfTable2, MIB_IF_ROW2, MIB_IF_TABLE2},
        System::{
            LibraryLoader::GetModuleHandleW,
            Power::{GetSystemPowerStatus, SYSTEM_POWER_STATUS},
            SystemInformation::{GlobalMemoryStatusEx, MEMORYSTATUSEX},
            Threading::GetSystemTimes,
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
    #[derive(Default)]
    struct Sampler {
        prev_cpu: Option<[u64; 3]>,
        prev_nic: HashMap<u64, Nic>,
        tick: Option<Instant>,
    }
    impl Sampler {
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
                        next.insert(n.key, n);
                    }
                    self.prev_nic = next;
                    self.tick = Some(now);
                }
                Err(code) => {
                    self.prev_nic.clear();
                    self.tick = None;
                    let _ = writeln!(out, "N/A (Win32 error {code})");
                }
            }
            let _=writeln!(out,"\nRead-only / offline / 2 s refresh. No subscription data.\nGPU, disk and Mihomo process metrics: use the hardware monitor.");
            (out, ok && cpu_now.is_some() && mem.is_some())
        }
    }
    struct Ui {
        sampler: Sampler,
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
                        let (text, ok) = u.sampler.take();
                        u.ticks += 1;
                        if ok {
                            u.good += 1;
                        }
                        SetWindowTextW(u.edit, wide(&text.replace('\n', "\r\n")).as_ptr());
                        u.smoke && u.ticks >= 3
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
    fn gui(smoke: bool) -> Result<i32, String> {
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
                wide("Clash Verge Rev - Native Lite Monitor").as_ptr(),
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
                    sampler: Sampler::default(),
                    edit,
                    ticks: 0,
                    good: 0,
                    smoke,
                })
            });
            if SetTimer(hwnd, 1, 2000, None) == 0 {
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
        match a.first().map(String::as_str) {
            None | Some("--gui") => gui(false),
            Some("--smoke") => gui(true),
            Some("--sample") | Some("--watch") => {
                let count = if a[0] == "--sample" {
                    2
                } else {
                    a.get(1)
                        .and_then(|x| x.parse::<u32>().ok())
                        .filter(|x| *x >= 2 && *x <= 600)
                        .ok_or("watch count must be 2..600")?
                };
                let mut s = Sampler::default();
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
            _ => Err("Usage: --gui | --smoke | --sample | --watch 2..600".into()),
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
