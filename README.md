# OneClickOptimizer

**Windows software configuration, one module at a time.** | [简体中文](README.zh-CN.md)

Development preview `0.1.0-alpha.1`. OneClickOptimizer is an offline, user-level configuration toolkit, not a generic PC speed booster. It ships the Positron module only; other applications are future work. No claim of universal performance improvements.

[![Windows validation](https://github.com/Kitty-Carter/OneClickOptimizer/actions/workflows/windows-test.yml/badge.svg)](https://github.com/Kitty-Carter/OneClickOptimizer/actions/workflows/windows-test.yml)

## Quick start

1. Extract the whole package on Windows 10/11, with Windows PowerShell 5.1.
2. Open `启动全家桶.bat`, select Positron and choose check-only first.
3. Save your work; choose optimize if you accept the changes. The tool checks compatibility, backs up existing settings and verifies configuration after writing.
4. Restart Positron yourself. See [module instructions](modules/positron/使用说明.md) for independent BAT launchers and recovery.

| Module | Status | Capabilities |
|---|---|---|
| Positron | Preview | Locate installation, check, optimize, backup on write, self-test |

The seven settings represent a specific workflow preference. Disabling diagnostics may hide helpful warnings; selecting base R package installation is not a verified speed improvement. Workspace and profile settings can override user settings. Arbitrary custom paths may require explicit input. Runtime UI and package installation speed are not covered by file-level verification.

## Development

See [module contract](docs/MODULE-CONTRACT.md), [roadmap](docs/ROADMAP.md), [validation status](docs/VALIDATION.md), and [AGENTS.md](AGENTS.md). The Windows workflow runs parser and fixture tests, but must pass in GitHub before a stable release. No system-wide policy changes, no credential collection, no forced software shutdown.

MIT license. This project is independent of Posit and the applications it configures.
