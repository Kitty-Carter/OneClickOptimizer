# Roadmap

- 0.1.0-alpha.1: import Positron, manifest, catalog, menu, fixture tests, public repository bootstrap. Preview only until CI and end-to-end validation pass.
- 0.1.0: actual Windows test matrix, guarded rollback tool, profile and custom-path regression, module release ZIP and SHA256; retain manual recovery until automated rollback is verified.
- 0.2: extract shared discovery/config/backup/log interfaces once a second real module validates common needs.
- 0.3: second software module (candidate Rayburst), preference presets and benchmark methodology; no dummy modules.
- 0.5: versioned presets, safe config migration, reproducible release packaging, independent module downloads.
- 1.0: stable only after multi-environment validation, recovery tests, transparent limitations and documentation. GUI optional, not a release gate in preview.

Branch strategy: main for reviewed snapshots, feature/<module> for development, fix/<issue> for fixes. Public repository as explicitly approved by owner. Protect main and require successful Windows CI when available.

Clash focused preview 1.1: configuration optimization, safe missing-only merge, repeatable node screening and evidence-bound native candidate groups. Real-time hardware/network monitoring and native client modification are out of scope. Pending: independent live network recovery, DNS/TLS/UDP and TUN/MTU comparisons, broader compatibility, sustained performance, authenticated service and multi-machine validation. No stable claim.
