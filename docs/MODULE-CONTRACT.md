# Module contract v1

Each `modules/<id>` has a manifest.json (schemaVersion 1, id matching folder, name, version, status, entry filename, modes), standalone entry, usage docs, and tests. Manifest files are local trusted source code; never load executable modules from the network automatically. Catalog validates directory ID and simple entry filename. The current core handles discovery of modules and dispatch, not generic application discovery or configuration writes.

Implemented modes: check -> `-CheckOnly` (no user config write); selftest -> `-SelfTest` (temporary files only); optimize -> default invocation (back up, apply, verify). Preserve exit 0/1/2. In preview, independent launchers remain supported. A missing app must fail or be reported absent, never install implicitly. Any unsupported setting is reported, not fabricated. Future interface: Detect/Inspect/Plan/Backup/Optimize/Verify/Restore/Benchmark/SelfTest; don't declare capabilities before implementation.

Every module documents target settings, version evidence, assumptions and risks, scope, recovery instructions, exit behavior, and test evidence. Preserve unrelated config, refuse invalid inputs, and never use global policy bypass. Personal backups stay outside Git. Changes to auth, credentials, security policy, other users or network settings are prohibited without a specifically designed and explicitly authorized workflow.

Module-specific optional restore or on-demand diagnostic commands may remain standalone (not advertised as shared catalog modes until supported). A restore must verify backup digests and refuse later user edits. For release packaging, pin the source ref and dependency lockfile, test the extracted package, preserve historical tags/assets and verify public bytes. Record the observation, setpoint, action, guard and resulting deviation separately.

Standalone menu may dispatch module-specific capabilities without expanding the common catalog. Keep existing CLI/BAT compatibility. For private node data, isolate and restrict ACL, validate local listener ownership, bound requests and explicitly preserve the primary route. Fixture watchdog evidence is separate from live recovery; a preview may exclude all hazardous actions.

Clash 1.1: source module requires building the locked Rust node-quality binary before its complete selftest. Standalone ZIP includes it. Current optimizer excludes monitoring. Conditional native group staging must not alter existing routes or credentials, and must preserve later edits on recovery.

Clash 1.2 recovery manifests bind to the configuration directory and carry durable transaction state; refuse legacy unbound restores in the new tool. Old releases remain available for their own backups. Keep candidate generation separate from experimental write; generated-runtime checks are not network verification.

Clash 1.3: release BAT entry points require manifest, source development may invoke PowerShell explicitly. Recovery resumes original target-bound manifest after repeated interruption; progress journal is advisory and actual byte hashes authoritative. Nonstandard data directory is read-only for new optimization writes; native app path remains configurable. Policy writes disabled, proposal output only. Runtime graph audit is limited to structural references and recognized simple rules.


Clash minimal default (1.3.1-rc.1): only absent global Merge tcp-concurrent, profile.store-selected and profile.store-fake-ip. No blanket DNS/AI/script replacement, no policy generation menu. Structural verification is not live network proof. Existing values in subscription-level configuration can still be affected by global settings; review before applying.
