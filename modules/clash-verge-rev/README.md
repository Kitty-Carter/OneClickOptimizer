# Clash Verge Rev · 配置优化预览（第一批）

独立模块，适用于已安装的 Windows Clash Verge Rev 2.5.10 / Mihomo 1.19.33（单机实测基线，不代表其他版本）。不安装客户端、不导入订阅、不上传数据、不强制关闭应用或切换节点。**面向中国大陆网络的 DNS 方案**，其他地区、企业网、校园网应审查后使用。非普适提速保证。

## 使用
1. 完整解压模块，双击 Check.bat，或运行 Optimize-Clash.ps1 -CheckOnly。默认寻找标准 AppData 目录，便携/自定义位置用 -DataPath 指定真实数据目录。
2. 阅读下列风险。已有非默认扩展时不会覆盖，请在原生订阅页面审查并手动合并 presets/Merge.yaml 与 Script.js。默认扩展可在正常退出 Clash 后双击 Optimize.bat，确认并输入安装 exe 路径；版本不匹配拒绝自动写入。自动写入只校验文件，不验证运行行为，返回 2。
3. 启动客户端，订阅页面「重新激活订阅」，检查 AI 固定出口、DNS、正常网站和代理访问。保留原有订阅及节点。原生界面中可关闭流量图、内核内存显示、悬停导航，开启 10 分钟自动轻量模式；这些是手动建议而非脚本强制项。需要监视时重新开启图表。原生测速 URL 可选 HTTPS 204；保留自定义探测需求。
4. 回滚：正常退出 Clash，确认当前扩展没有后续合法修改，按输出备份目录中的原始 Merge.yaml / Script.js 恢复至 profiles，再启动并重新激活。备份仅本机保存。建议另做原生备份。没有自动跨版本恢复。

## 方案依据与边界
- TCP 并发、持久化节点选择、Fake-IP/ARC、国内外 DNS 分流：针对上述版本与网络环境验证过配置生成；DNS 启动解析使用明文 UDP DNS，可能与本地网络策略冲突，不代表防泄漏已验证。
- 精确规则去重保持首个规则；管理的 AI 域名规则会置顶，改变这部分订阅分流；按需手动选择节点。空组 REJECT 已用独立内核行为测试；无合适节点/同名冲突时脚本不创建 AI 组，provider 也可能含直连类型，非全系统 kill switch。
- 原生 health-check 仅补充缺失/已知 HTTP 探测 URL；限制过长检测周期；保留 interval=0、自定义 URL；延迟不是吞吐量。
- 不自动关闭 TLS 验证，不调整 TUN/MTU、系统代理、GeoData、原始订阅、密钥或防火墙。轻量模式单机工作集快照曾明显降低（非严格基准）。多机、真实 BAT 双击、完整回滚、DNS 泄漏及新安装客户端自动应用尚未验收。
- 官方参考：https://github.com/clash-verge-rev/clash-verge-rev/tree/v2.5.10 和 https://github.com/MetaCubeX/mihomo/tree/v1.19.33

退出码：0 检查/自检完成或文件已匹配（不等于生效）；1 失败或取消；2 自定义、版本不匹配或已写入但需人工激活验证。

## 第二批：网络与电脑监视预览

双击 `Monitor.bat`（Windows PowerShell 5.1 + .NET Framework/WinForms，无需安装 Python、Node 或额外驱动）。窗口按默认 2 秒刷新；可勾选 Always on top 置顶。关闭窗口即退出采样。也可运行 `powershell.exe -NoProfile -STA -File Monitor-Clash.ps1 -Sample` 进行一次只读采样，`-SelfTest` 运行计数差分测试，`-SmokeTest` 自动关闭测试窗口。`-IntervalMs` 支持 1000–10000 ms。

显示整机 CPU、内存、Mihomo 进程工作集及 CPU，以及各网卡状态、链路速率、独立收发速率和本次会话内累计量。物理网卡依据 Get-NetAdapter -Physical 的 GUID 识别；Mihomo/Meta/Tunnel 仅标为隧道候选；其余不推断。连接断开、计数回退、采样间隔过长时速率标为不可用，避免虚假尖峰。物理网卡与 TUN 不相加；Mihomo 进程资源不是内核堆内存，网卡流量也不是订阅计费流量。当前累计量只覆盖有效采样区间，不写历史文件。

**功能边界：** 这是按需启动的只读辅助窗口，不是已经集成进 Clash 的新原生页面；尚无任务栏嵌入、Mihomo 私有接口流量、按进程流量、GPU/温度、持久化历史、自动诊断或 IPPure 自动检测。无网络请求、不读取订阅或控制密钥、不开放端口、不安装自启动、不改变代理设置。未验证 30 MiB 内存或 1% CPU 预算、多机兼容性、实际 GUI 像素布局。参考 TrafficMonitor 的显示思路，代码为本模块新编写，并未复制其源码。后续原生集成需独立构建并验收。

已执行：Windows PS5.1 编译、5 项速率差分断言、实机系统采样、窗口多次采样后自动退出冒烟测试；这些不代表长时间性能验收。

## 0.2.0-alpha.2: hardware and usability review

Monitor.bat now includes optional Windows hardware counters: physical disk non-idle percentage (100 minus _Total idle time), disk read/write rates, GPU busiest-engine estimate (aggregate per engine, then max; not total GPU utilization), and battery when available. Unavailable data = N/A. Hardware sampling runs at most once per 15 seconds and may take longer; base sampling defaults to 2 seconds, no overlapping jobs. Monitor-Lite.bat skips optional hardware queries. Counter timestamps are taken before hardware queries. No temperature, per-process network, daily history, taskbar or native Clash integration yet. No continuous external queries. Close the window to exit. See validation notes for limits.

Validation: Windows 11 / PS 5.1, 7 rate assertions passed; live sample returned disk, GPU and battery data; 20-second GUI smoke exited 0. Short hardware-mode process observation: max working set 155.9 MiB, private 115.8 MiB, process CPU normalized to whole machine 0.129% over ~8 seconds. These are not full system overhead or long-run guarantees; the 30 MiB budget is not met. Temperature, taskbar integration, native client integration, per-process traffic, and long-run acceptance remain pending.
