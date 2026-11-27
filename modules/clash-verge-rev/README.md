# Clash Verge Rev 一键配置 · 1.4.0-rc.1

**正式推荐交付仅一个文件：Clash-OneClick-Config.bat。** 无需 Python、Rust、Node、额外 PowerShell 模块或其他下载。只依赖 Windows 自带 PowerShell 5.1 与已安装的官方 Clash。历史 1.3.x 源码和测试保留在仓库，不进入新发布文件。

## 使用

1. 安装官方 Clash Verge Rev 2.5.10（内置 Mihomo 1.19.33），启动一次初始化配置，正常退出托盘客户端。
2. 下载并双击 BAT：C 只读检查，A 一键配置（输入 APPLY 确认），R 恢复，Q 退出。非默认安装位置可能需要输入 clash-verge.exe 完整路径。
3. 启动 Clash，导入或重新激活自己的订阅，手动选 AI-固定出口节点；按需自行开启系统代理、TUN，确认联网。
4. 若异常，正常退出客户端，运行同一 BAT 选 R，选择原备份。若官方客户端或用户后来重写了文件导致字节哈希不同，程序拒绝覆盖，请使用本机备份人工核对恢复。

## 配置范围与边界

- 当前公共 Merge 与 Script.js：TCP 并发、store-selected、store-fake-ip、Fake-IP/ARC、公共 DoH 和回退、去除完全重复规则、原有健康检查调整、26条 AI 专用域名优先规则及手动选择组。不自动选节点。
- 原生设置：warning 日志、规则模式、关闭 IPv6/LAN、unified-delay、自动轻量10分钟、关闭流量图/内存显示/悬停导航/自动延迟检测、内置增强。预置 gVisor、MTU9000、auto-route、auto-detect-interface 和 strict-route=false，不自动开启 TUN 或系统代理。
- 不复制私人订阅、节点、密码、controller secret、账号、机器路径、订阅专属扩展、选中节点、原始运行时 YAML。既有 per-profile DNS 配置或自定义全局 Merge/Script 存在冲突时拒绝写入。新安装使用全局 Merge DNS，关闭独立 DNS 覆盖开关；因此不是逐字克隆全部私人设置。自定义订阅后置增强仍可能改变结果，请在实际激活后检查。
- 保留本机端口、密钥、配置文件中其他字段；不写运行时生成文件、DNS 专属文件、订阅列表。DNS 和 MTU 方案来自维护者当前配置，不保证适合任何网络。AI 规则为域名匹配，不等同所有共享登录域名、IP流量或完整应用登录覆盖。
- 写入仅在客户端与内核退出后执行，备份及哈希校验、文件级原子替换、重复运行无变化、拒绝覆盖后来编辑。备份位于 %LOCALAPPDATA%/OCO-Clash-Share-Backups，包含本机原配置，勿分享。退出码0=检查/无变更/恢复/自检；2=已暂存待重新启动激活；1=失败或冲突。仅限标准 APPDATA 数据目录与已验证版本，未知版本不写。
- 单文件候选版经过 Windows 隔离测试和公共预设核对；未在第二台真实全新电脑上完整激活和验证恢复，不宣称稳定版或普遍提速。无监视器、无驻留服务、无新节点扫描。

CLI: Clash-OneClick-Config.bat --check / --apply / --restore / --self-test. 历史 ZIP、Rust 节点工具、旧 PowerShell 诊断/优化脚本及研究记录继续保留，仅用于追溯，不属于当前正式交付。
