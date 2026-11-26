<p align="center"><img src="docs/assets/banner.svg" alt="OneClickOptimizer — Software optimization, one click away." width="100%"></p>

<h1 align="center">OneClickOptimizer</h1>
<p align="center"><strong>Featured module · Positron Optimizer</strong><br>Software optimization, one click away.</p>
<p align="center">
  <a href="https://github.com/Kitty-Carter/OneClickOptimizer/actions/workflows/windows-test.yml"><img alt="Windows validation" src="https://github.com/Kitty-Carter/OneClickOptimizer/actions/workflows/windows-test.yml/badge.svg?branch=main"></a>
  <a href="LICENSE"><img alt="MIT license" src="https://img.shields.io/badge/license-MIT-50c9ae?style=flat-square"></a>
  <img alt="Windows 10 and 11" src="https://img.shields.io/badge/Windows-10%20%2F%2011-3776bd?style=flat-square">
  <img alt="PowerShell 5.1" src="https://img.shields.io/badge/PowerShell-5.1-526f9b?style=flat-square">
  <img alt="Development preview" src="https://img.shields.io/badge/version-0.1.0--alpha.1-c58c43?style=flat-square">
</p>

<p align="center">
<a href="https://github.com/Kitty-Carter/OneClickOptimizer/releases/download/v0.1.0-alpha.1/Positron-OneClick-Optimizer-Windows.zip"><img src="docs/assets/download-positron.svg" alt="Download Positron Optimizer (ZIP)" width="300"></a><br>
<a href="https://github.com/Kitty-Carter/OneClickOptimizer/releases/tag/v0.1.0-alpha.1"><strong>Release & downloads</strong></a> &nbsp;·&nbsp;
<a href="modules/positron">Positron module</a> &nbsp;·&nbsp;
<a href="docs/ROADMAP.md">Roadmap</a> &nbsp;·&nbsp;
<a href="README.zh-CN.md">简体中文</a>
</p>

---

OneClickOptimizer is an open-source, offline-first, modular one-click optimization toolkit for Windows applications. It turns curated optimization presets with documented rationale, applicability and risks into automated tools: detect the application, check compatibility, back up existing settings, apply the preset and verify the result. The focus is applying optimization presets, not cloning or syncing personal configurations. No universal speed improvement is promised.

> [!NOTE]
> **Development preview · v0.1.0-alpha.1** — Positron is the only implemented module. Choose a user ZIP under Assets on the Releases page. This is a preview, not a stable release. This is not a universal PC speed booster.

## Featured module | Positron Optimizer

**Only need Positron? Choose the standalone ZIP. No full toolkit required.**

| Download | Best for |
| :--- | :--- |
| **[Positron-OneClick-Optimizer-Windows.zip](https://github.com/Kitty-Carter/OneClickOptimizer/releases/tag/v0.1.0-alpha.1)** | Recommended · Positron users; extract and double-click the BAT |
| [OneClickOptimizer-Toolkit-Preview-Windows.zip](https://github.com/Kitty-Carter/OneClickOptimizer/releases/tag/v0.1.0-alpha.1) | Users who want the unified toolkit entry point |

Choose the corresponding asset on the release page. Both previews contain the same Positron configuration functionality.

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

1. Open the [Positron release](https://github.com/Kitty-Carter/OneClickOptimizer/releases/tag/v0.1.0-alpha.1), choose the recommended standalone ZIP `Positron-OneClick-Optimizer-Windows.zip` and extract everything. Requires an installed Positron, Windows 10/11 and Windows PowerShell 5.1.
2. Double-click **`仅检查不修改.bat`** (check only) to inspect paths and changes.
3. Save your work, run **`一键优化.bat`** (optimize) and confirm Y.
4. Restart Positron yourself. See the included guide for manual recovery.

For the full toolkit ZIP, run `启动全家桶.bat` and select Positron → check → optimize. Developers can [download the main source snapshot](https://github.com/Kitty-Carter/OneClickOptimizer/archive/refs/heads/main.zip).

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

<p align="center">MIT licensed · Independent community project, not affiliated with Posit.<br>Software optimization, one click away.</p>

