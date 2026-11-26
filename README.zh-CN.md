<p align="center"><img src="docs/assets/banner.svg" alt="OneClickOptimizer — Your apps. Your workflow." width="100%"></p>

<h1 align="center">一键优化全家桶 · OneClickOptimizer</h1>
<p align="center"><strong>让每个软件都按照你的使用习惯工作。</strong></p>
<p align="center">
  <a href="https://github.com/Kitty-Carter/OneClickOptimizer/actions/workflows/windows-test.yml"><img alt="Windows validation" src="https://github.com/Kitty-Carter/OneClickOptimizer/actions/workflows/windows-test.yml/badge.svg?branch=main"></a>
  <a href="LICENSE"><img alt="MIT license" src="https://img.shields.io/badge/license-MIT-50c9ae?style=flat-square"></a>
  <img alt="Windows 10 and 11" src="https://img.shields.io/badge/Windows-10%20%2F%2011-3776bd?style=flat-square">
  <img alt="PowerShell 5.1" src="https://img.shields.io/badge/PowerShell-5.1-526f9b?style=flat-square">
  <img alt="Development preview" src="https://img.shields.io/badge/version-0.1.0--alpha.1-c58c43?style=flat-square">
</p>

<p align="center">
<a href="https://github.com/Kitty-Carter/OneClickOptimizer/archive/refs/heads/main.zip"><strong>⬇ 下载完整工具（ZIP）</strong></a> &nbsp;·&nbsp;
<a href="modules/positron">Positron 模块</a> &nbsp;·&nbsp;
<a href="docs/ROADMAP.md">路线图</a> &nbsp;·&nbsp;
<a href="README.md">English</a>
</p>

---

OneClickOptimizer 是一个开源、离线、按软件模块扩展的 Windows 配置工具。自动查找已安装的软件，检查现有设置，备份后应用优化方案，并回读验证配置。它不是万能电脑提速神器。

> [!NOTE]
> **开发预览版 · v0.1.0-alpha.1** — 目前仅实现 Positron 模块。上方 ZIP 是当前主分支源码快照，不是稳定版 Release。

## 为什么选择它？

| 自动定位与检查 | 先备份，再优化 | 验证与扩展 |
| :--- | :--- | :--- |
| 识别常见和自定义安装目录，先检查现状再决定是否修改。 | 写入前备份，尽量保留其他个性化配置。 | 回读验证、明确部分兼容情况；各模块独立维护与测试。 |

## 已支持的软件

| 软件 | 状态 | 优化内容 |
| :--- | :--- | :--- |
| **[Positron](modules/positron)** | 预览版 · 7 项配置目标 | Quarto 大纲、编辑器标尺与字体缩放、R 包安装器、Notebook 会话与诊断。 |

[查看 Positron 使用指南 →](modules/positron/使用说明.md)

## 快速开始

1. [下载完整 ZIP](https://github.com/Kitty-Carter/OneClickOptimizer/archive/refs/heads/main.zip)，在 Windows 10/11 解压**整个文件夹**，确保 Windows PowerShell 5.1 可用。
2. 双击 **`启动全家桶.bat`**。
3. 选择 Positron → **仅检查**；保存正在编辑的内容，确认接受修改后再选择优化。
4. 自行重启 Positron。独立 BAT 与手动恢复方法见[模块说明](modules/positron/使用说明.md)。

> [!IMPORTANT]
> 七项配置是特定工作流偏好，并非所有用户的最佳设置。关闭 R 诊断可能隐藏有效警告；base 安装器不保证提速。工作区及 Profile 可能覆盖用户设置。极端自定义路径需要手动指定。自动回退与跨电脑兼容性验收尚未完成。

## 模块化工程

```text
OneClickOptimizer/
├── core/                 模块目录与调度
├── modules/
│   └── positron/         首个独立模块
├── tests/                Windows 隔离测试
├── docs/                 规范、验证记录、路线图
└── 启动全家桶.bat         一键启动入口
```

| 里程碑 | 目标 |
| :--- | :--- |
| **0.1.0-alpha.1 · 当前** | Positron 预览模块、模块目录及 Windows 验证流程 |
| 0.1.0 | 恢复功能、回归测试、发布打包 |
| 0.2.0–0.3.0 | 公共基础设施与第二个真正的软件模块 |
| 1.0.0 | 完成更多环境兼容性和恢复验证后发布稳定版 |

[完整路线图](docs/ROADMAP.md) · [验证记录](docs/VALIDATION.md) · [自动化测试](https://github.com/Kitty-Carter/OneClickOptimizer/actions)

## 安全与贡献

默认以普通用户权限运行、优先离线。不强制关闭软件、不更改系统安全策略、不收集凭据。配置回读不等同于界面验收或性能基准测试。

[模块接口规范](docs/MODULE-CONTRACT.md) · [贡献指南](CONTRIBUTING.md) · [AI 维护规则](AGENTS.md) · [更新记录](CHANGELOG.md)

---

<p align="center">MIT 开源协议 · 独立社区项目，与 Posit 无官方隶属关系。<br>为每一位重视工作流的用户而设计。</p>

