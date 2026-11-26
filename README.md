<p align="center"><img src="docs/assets/banner.svg" alt="OneClickOptimizer — Your apps. Your workflow." width="100%"></p>

<h1 align="center">OneClickOptimizer</h1>
<p align="center"><strong>Make every app work the way you want.</strong></p>
<p align="center">
  <a href="https://github.com/Kitty-Carter/OneClickOptimizer/actions/workflows/windows-test.yml"><img alt="Windows validation" src="https://github.com/Kitty-Carter/OneClickOptimizer/actions/workflows/windows-test.yml/badge.svg?branch=main"></a>
  <a href="LICENSE"><img alt="MIT license" src="https://img.shields.io/badge/license-MIT-50c9ae?style=flat-square"></a>
  <img alt="Windows 10 and 11" src="https://img.shields.io/badge/Windows-10%20%2F%2011-3776bd?style=flat-square">
  <img alt="PowerShell 5.1" src="https://img.shields.io/badge/PowerShell-5.1-526f9b?style=flat-square">
  <img alt="Development preview" src="https://img.shields.io/badge/version-0.1.0--alpha.1-c58c43?style=flat-square">
</p>

<p align="center">
<a href="https://github.com/Kitty-Carter/OneClickOptimizer/releases"><strong>⬇ Download releases</strong></a> &nbsp;·&nbsp;
<a href="modules/positron">Positron module</a> &nbsp;·&nbsp;
<a href="docs/ROADMAP.md">Roadmap</a> &nbsp;·&nbsp;
<a href="README.zh-CN.md">简体中文</a>
</p>

---

OneClickOptimizer is an offline, open-source toolkit for configuring Windows applications through small, independently maintained modules. It finds installed software, checks settings, backs up changes, applies a workflow preset and verifies the resulting configuration.

> [!NOTE]
> **Development preview · v0.1.0-alpha.1** — Positron is the only implemented module. Choose a user ZIP under Assets on the Releases page. This is a preview, not a stable release. This is not a universal PC speed booster.

## Why OneClickOptimizer?

| Find & inspect | Back up & apply | Verify & maintain |
| :--- | :--- | :--- |
| Discover common and custom installation paths; inspect before changing settings. | Keep unrelated configuration intact. Back up existing settings before a write. | Read back changes, report partial support, and keep modules independently testable. |

## Available modules

| Application | Status | What it does |
| :--- | :--- | :--- |
| **[Positron](modules/positron)** | Preview · 7 setting goals | Quarto outline, editor rulers and zoom, R package installer, notebook execution and diagnostics. |

[Read the Positron guide →](modules/positron/使用说明.md)

## Get started

Only need Positron? Select `Positron-Optimizer-Windows.zip` under Assets. Beginners need not download Source code. If the release is not available yet, developers can [download the main snapshot](https://github.com/Kitty-Carter/OneClickOptimizer/archive/refs/heads/main.zip).

1. [Download OneClickOptimizer-Windows.zip](https://github.com/Kitty-Carter/OneClickOptimizer/releases) and extract the **entire** folder on Windows 10/11 with Windows PowerShell 5.1.
2. Double-click **`启动全家桶.bat`**.
3. Choose Positron → **Check only**. Save your work, then choose Optimize if you accept the changes.
4. Restart Positron yourself. For manual recovery or standalone launchers, see the [module guide](modules/positron/使用说明.md).

> [!IMPORTANT]
> The Positron preset reflects a particular workflow. Turning off R diagnostics may hide useful warnings, and choosing the base installer is not a proven speed improvement. Workspace and profile settings may override user settings. Arbitrary custom paths may need explicit input. Automatic rollback and cross-machine acceptance are not complete.

## Built for extension

```text
OneClickOptimizer/
├── core/                 Module catalog and dispatch
├── modules/
│   └── positron/         First independent module
├── tests/                Isolated Windows tests
├── docs/                 Contracts, evidence and roadmap
└── 启动全家桶.bat         One-click entry
```

| Milestone | Scope |
| :--- | :--- |
| **0.1.0-alpha.1 · now** | Positron preview, module catalog, Windows validation workflow |
| 0.1.0 | Recovery, regression tests, release packaging |
| 0.2.0–0.3.0 | Shared infrastructure and a second real module |
| 1.0.0 | Broader compatibility and verified recovery before stable release |

[Full roadmap](docs/ROADMAP.md) · [Validation evidence](docs/VALIDATION.md) · [Windows CI](https://github.com/Kitty-Carter/OneClickOptimizer/actions)

## Safety and contribution

User-level, offline-first. No forced app shutdown, administrator privileges by default, system-wide security policy changes, or credential collection. Configuration verification is not a live UI or speed benchmark.

[Module contract](docs/MODULE-CONTRACT.md) · [Contributing](CONTRIBUTING.md) · [AI maintenance rules](AGENTS.md) · [Changelog](CHANGELOG.md)

---

<p align="center">MIT licensed · Independent community project, not affiliated with Posit.<br>Made for people who care about their workflow.</p>

