<p align="center"><img src="docs/assets/banner.svg" alt="OneClickOptimizer" width="100%"></p>

# OneClickOptimizer · 一键优化全家桶

**让软件优化，只需一键。** 面向 Windows 的开源模块化优化工具。检测、备份、应用、验证；不承诺普遍提速。

[English](README.md) · [全部发布](https://github.com/Kitty-Carter/OneClickOptimizer/releases) · [Windows CI](https://github.com/Kitty-Carter/OneClickOptimizer/actions/workflows/windows-test.yml) · [MIT](LICENSE)

## 选择要优化的软件

| Positron | Clash Verge Rev |
| :---: | :---: |
| **科研工作流配置优化** | **Clash 一键配置优化** |
| v0.1.0-alpha.1 · Windows 预览 | v1.4.0-rc.1 · Windows 候选版 |
| [![下载 Positron](docs/assets/download-positron.svg)](https://github.com/Kitty-Carter/OneClickOptimizer/releases/download/v0.1.0-alpha.1/Positron-OneClick-Optimizer-Windows.zip) | [![下载 Clash Verge Rev](docs/assets/download-clash.svg)](https://github.com/Kitty-Carter/OneClickOptimizer/releases/download/clash-v1.4.0-rc.1/Clash-OneClick-Config.bat) |
| [发布说明](https://github.com/Kitty-Carter/OneClickOptimizer/releases/tag/v0.1.0-alpha.1) · [模块指南](modules/positron) | [发布说明](https://github.com/Kitty-Carter/OneClickOptimizer/releases/tag/clash-v1.4.0-rc.1) · [模块指南](modules/clash-verge-rev) |
| 七项工作流配置、检查及备份 | 单个 BAT · 公共 DNS、AI 固定出口及轻量配置 |

## 快速开始

Positron 仍下载并完整解压原独立 ZIP。Clash 只下载单个 BAT：先启动支持版本一次，正常退出 Clash，双击 BAT 检查或应用。重新启动后导入/激活自己的订阅，并手动选择 AI 固定出口节点。

## 安全与兼容性

Clash 1.4.0-rc.1 面向 Windows 的 Clash Verge Rev 2.5.10 / 内置 Mihomo 1.19.33。复现公共 DNS、26条 AI 域名规则与轻量设置，不含私人订阅或凭据。发现自定义全局脚本或订阅专属 DNS 覆盖时拒绝写入。TUN、系统代理和 AI 节点选择仍需手动确认。备份及恢复在本机进行，不覆盖后续修改。新交付不含节点扫描或监视器，不保证提速；全新独立电脑实际激活及跨机恢复尚待验证。Positron 仍为独立预览版。

[源码 ZIP](https://github.com/Kitty-Carter/OneClickOptimizer/archive/refs/heads/main.zip) · [模块契约](docs/MODULE-CONTRACT.md) · [路线图](docs/ROADMAP.md) · [验证记录](docs/VALIDATION.md) · [更新记录](CHANGELOG.md)

MIT · 独立社区项目，与 Positron 或 Clash Verge Rev 官方无隶属关系。
