<!-- TRELLIS:START -->
# Trellis Instructions

These instructions are for AI assistants working in this project.

This project is managed by Trellis. The working knowledge you need lives under `.trellis/`:

- `.trellis/workflow.md` — development phases, when to create tasks, skill routing
- `.trellis/spec/` — package- and layer-scoped coding guidelines (read before writing code in a given layer)
- `.trellis/workspace/` — per-developer journals and session traces
- `.trellis/tasks/` — active and archived tasks (PRDs, research, jsonl context)

If a Trellis command is available on your platform (e.g. `/trellis:finish-work`, `/trellis:continue`), prefer it over manual steps. Not every platform exposes every command.

If you're using Codex or another agent-capable tool, additional project-scoped helpers may live in:
- `.agents/skills/` — reusable Trellis skills
- `.codex/agents/` — optional custom subagents

Managed by Trellis. Edits outside this block are preserved; edits inside may be overwritten by a future `trellis update`.

<!-- TRELLIS:END -->

## Private IPA signing

This fork signs its own builds through a Private IPA Signer deployment, via the
[`private-signer-ios`](https://github.com/nnnmdzz/private-signer-ios) package.
Integration guide:
https://github.com/nnnmdzz/private-signer-ios/blob/main/docs/client-integration-guide.zh-CN.md

- All application-specific signing values live in `Shared/ForkFeatures/PrivateSigningAdapter.swift`.
  Construct `SignerKeychainConfiguration`, `GitHubReleaseSource`, and `SelfUpdateCoordinator` there
  and nowhere else — `Tests/automation_and_private_updates_contract_test.sh` enforces this.
- The Worker URL and Signing Request Token are user configuration stored in the Keychain. Never
  write either into source, build settings, plists, tests, logs, or commit messages.
- `configurationAccessGroup` is the Stable Configuration Group. Changing its value strands every
  installed client's configuration. To change it, move the old value into `legacyAccessGroups`
  instead of replacing it. `keychainService` must likewise stay `com.paopaolabs.location-spoofer.private-update`.
- `requestSignedBuild` must always be called with an explicit `target:`. `.installedApp` upgrades
  the app; `.sideBySideClone` installs a second one.
- Pin the package with `exactVersion:` in `project.yml`. Do not widen it to a range.
- CI cannot verify that a signed build installs on a device. Do not report signing changes as
  verified without running the real-device checklist in §7 of the integration guide.
