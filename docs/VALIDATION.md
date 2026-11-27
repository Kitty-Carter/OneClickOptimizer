# Validation status

The preceding Positron tool's core JSONC merge, invalid-input rejection, and atomic replacement primitives were tested under Windows PowerShell 5.1. On the original machine, Positron 2026.11.1, R 4.5.2 and bundled Quarto 1.11.9 were detected and the seven settings were written and read back; real UI behavior and package installation speed were not tested. These are historical observations, not validation of this exact new release.

New package: Windows integration test and GitHub Actions workflow supplied, but CI has not run as of initial import. Verify results before release. The isolated fixture uses a dummy copied executable, which is never launched; it is not a real Positron installation. It covers explicit paths, Chinese/space paths, check-only, backups, idempotence and invalid inputs, not real app detection or live UI behavior.

## 2026-11-26 observed Windows results

The revised module was transferred to a temporary directory and its SHA-256 matched the packaged source (f5872f2f3d7b00cc1d875a56e4861b052b5db29ed9ffc4c374e3ad879898017d). Windows PowerShell 5.1 self-test exited 0; real Positron 2026.11.1 check-only exited 0 with all seven goals recognized and zero changes. An equivalent isolated integration harness exercised explicit Chinese/space paths, check-only byte equality, backup creation, original SHA-256 equality, seven setting writes, idempotence and duplicate-key rejection; all assertions passed. No live settings were changed. Exact repository test runner, unified launcher, CI and cross-machine acceptance remain unverified. The remote console displayed Chinese text with an encoding mismatch; BAT display has not been interactively verified.

## Repository CI confirmed on 2026-11-26

- [Initial import](https://github.com/Kitty-Carter/OneClickOptimizer/actions/runs/45729819807): success.
- [README redesign](https://github.com/Kitty-Carter/OneClickOptimizer/actions/runs/45730571991): success; parser, catalog and isolated integration steps succeeded.
- These runs predate release packaging and the standalone confirmation change. The release workflow tests the exact extracted packages before publishing. No live GUI, automatic rollback, performance or cross-machine acceptance claim.

## Clash module 0.2.0-alpha.2 preview (2026-11-27)

Windows PS5.1: rate assertions 7/7; live NIC/system and optional disk/GPU/battery counters returned data; actual GUI smoke exit 0; hardware monitor observed max WS 155.9 MiB, private 115.8 MiB, normalized process CPU 0.129% over ~8 seconds. Memory budget not met; WMI provider overhead not included. Native integration, actual double-click interaction, cross-machine and long-run performance not established. This is not a performance improvement claim.

## Clash 0.3.0-alpha.1 (2026-11-27)

Rust 1.100.0 x86_64-pc-windows-msvc linker probe passed; windows-sys 0.61.2 pinned. Seven Rust counter/CPU tests passed, live two-sample NIC/CPU/RAM/battery and GUI three-tick smoke passed. Short native window process observation: 20.55 MiB max observed WS, 4.28 MiB private, CPU 0% measured over 2.03 s; only basic feature set, no long-run or equivalent hardware comparison. Optimizer fixture restore passed, corrupted backup and later edits refused; live check found both extension bytes already matching, no live writes. Bundled core reports 1.19.33. PowerShell 5.1 array handling initially failed then fixed. No new claim of DNS/TUN speed or leak protection.

## Clash 0.3.0-alpha.2 (2026-11-27)

Rust 8/8 unit tests; live PDH disk counters and PID-matched process fallback after warm-up; source-build native GUI 16.12 s / 9 observations, max sampled WS 26.77 MiB, private 10.87 MiB, normalized process CPU 0.04%, normal close. Isolated optimizer injected failure after first write: original bytes recovered; normal restore and refusal regression passed; current extensions match, no live write. Source audit of Mihomo v1.19.33 RawDNS and assignment confirms fallback-lazy-query is supported. No DNS leak or new network-speed claim. GPU and native client integration pending; same-feature long-run validation pending.

## Clash 0.3.0-alpha.3 (2026-11-27)

Offline diagnostic fixtures passed (expected response, HTTP other, transport error, nonfinite/malformed input, median, valid and malformed optional exit fields). Real Windows loopback port 7897 owned by verge-mihomo; two rounds 6/6 expected responses, successful median total elapsed Cloudflare 602.4 ms, GitHub 964.8 ms, ChatGPT 1453.3 ms. Not individual-node latency, throughput or authenticated app access. No IPPure live query performed; no network settings changed. Upstream v2.5.10 package.json declares pnpm@12.16.1, GPLv3 license confirmed.
