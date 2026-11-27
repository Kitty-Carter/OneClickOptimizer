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

## Integrated cycle 0.4.0-alpha.1 (2026-11-27)

Observed: 6/6 actual subscription/runtime candidate validation (simulated merge + JS, unchanged node objects, idempotence, core -t); no live configuration rewrite. Detached timer fixture restored, cancelled and rejected later edits; not service/route rollback. Isolated ABBA 3 blocks: each old/new 12/12 HTTPS 204 and 12/12 1 MiB downloads; pooled medians 850 vs 702 ms and 1.091 vs 1.098 MB/s, inconsistent block effect, main TUN still active. Retain old core. Native node screening initial real test 3/6 two-pass candidates; temporary directories and isolated processes cleaned. Native GPU estimate returned data after warm-up, split sampler source-build short WS 26.97/27.69 MiB Lite/balanced, 20.12/20.16 s, normalized CPU 0.032/0.019%. Ten live path rounds 30/30 expected HTTP. Private configured named pipe unavailable; no controller port opened. Upstream source cloned, pnpm and SDK found, full build not attempted under 868 MiB available memory. Long-run, full recovery, smart policy execution, DNS leak and native integration not accepted. These are limited observations and not a full-plan PASS.

## Focused Clash 1.1.0-alpha.1 (2026-11-27)

Scope reset removes monitoring from current source and package; earlier monitoring evidence is historical. Local Windows 11: original v2.2/v2.3 preset bytes unchanged; seven key live configuration files compared byte-for-byte and official processes unchanged. Conservative merge: explicit false, unknown fields, custom JS, idempotence, fixture fault rollback, restore and private ACL checks passed. Batch 6-node recommendation: 3/6 with 3/3 HTTPS, 2/6 with 2/2 downloads. New automatic screening: 69 eligible nodes, 57 with 3/3 HTTPS (three worker cores); top six retested 18/18 expected 204 and 12/12 exact 1 MiB downloads, 0.302?1.341 MB/s, median 0.7805 MB/s. No abandoned core or temp directory after normal completion. Both candidate configurations accepted by bundled Mihomo -t. Generated script validated in Node for exact SHA256 vectors, unchanged original rules/nodes, parent prefix, idempotence, node mutation exclusion, duplicate/collision refusal, expiration; simulated 5 actual subscription inputs for the batch candidate produced groups only on the matching subscription. Full-auto candidate JS produced 3 groups with 6 members each, accepted by core -t. Read-only staging plan accepted; no live stage/activation, no actual speedup claim. No independent DNS/TLS/UDP/TUN failure or clean-machine acceptance. Raw private reports and node fingerprints are not committed.

## Clash 1.2.0-rc.1 (2026-11-27)

Local Windows 11: actual child exits 77 after first replacement, journal WRITING survives, new transaction blocked and recovery restores both original byte streams. Cross-process mutex, wrong target refusal, prior tamper/later-edit/rollback/merge fixtures, blank YAML missing-only and package tamper/path traversal fixtures passed. Generated runtime checks 19/19; five real subscriptions simulated merge plus bundled Mihomo -t 5/5, proxy data unchanged; prior seven live baseline files byte-identical. No fresh live apply or actual network loss recovery in this run. Experimental policy staging removed from regular menu; candidate generation retained. Local/CI tests don't establish universal stability.

## Clash 1.3.0-rc.1 (2026-11-27)

Baseline 9474241, 2.5.10/1.19.33, 69 inline nodes, 522 rules, 51 skip-cert-verify; independent worktree, seven private config snapshots, eight experience snapshots. Upstream exact source config/config.go, enhance/merge.rs, enhance/mod.rs, enhance/field.rs and utils/dirs.rs reviewed: global merge lowercases top keys, DNS shallow overlay, hosts replace, authoritative control-plane/TUN/DNS reapplied. Five real subscription copies simulated only known global merge/JS, original node/rule invariants and core -t 5/5; not actual full profile-chain activation. Generated 19/19, current structural audit no detected duplicates, missing members/providers, cycle residual, missing recognized rule targets or unparsed forms. Repeated child-exit recovery before/after first, after last, during restore; actual locked second file; original bytes, target identity and mutex fixtures. Rust 6 unit tests, fmt, clippy -D warnings and selftest; cancellation flag fixture not real Ctrl+C lifecycle. Full node scan 69/69, 54 3/3; six finalists 18/18 204, 12/12 exact downloads, measured 12582912 bytes, reserved 27328512, unknown 0, cap 37748736. Three groups x6 only candidate. Job cleanup observed; no IPPure request. TCP three ABBA blocks fixed VLESS+REALITY: A 15/18, B 17/18, medians 1013.35/1005.70 ms, 0.5587/0.5855 MB/s, retain A; successful response medians, no reliable P95. Synthetic loopback DNS ARC/LRU 180/180 each, cold 0.2785/0.2355ms warm 0.0485/0.0445ms, 60 upstream per state, retain ARC. Main TUN may affect TCP path. No real DNS leak, TLS identity, UDP/TUN/MTU or kernel-upgrade adoption. Independent watchdog fixtures 3/3 only. No actual nonempty native activation, recovery after genuine network loss, 30-minute complete cycles or second Windows client. Stable gate blocked. No monitor. Private logs/configs excluded from Git.

## Clash 1.3.1-rc.1 scope

Default application is deliberately restricted to the three missing global Merge fields. Explicit values and Script.js stay intact. Legacy presets remain as regression fixtures. The change does not establish a new data-plane performance result, network recovery or second-machine acceptance. Candidate only.


Clash 1.4.0-rc.1: exact single-BAT build, Windows temporary-file plan/apply/idempotence/restore and conflict fixtures, payload fingerprint and AI-rule checks; no second real fresh Windows activation or real disconnect recovery claim.
