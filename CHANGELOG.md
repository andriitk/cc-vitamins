# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-10-25

### Added
- `version` segment at the end of line 1: the running Claude Code version
  (`cc v2.1.296`), dim. Remove `version` from `CC_VITAMINS_LINE1` to hide it.

### Project
- Releases are automated: merging a PR that bumps `VERSION` tags and
  publishes the release. Added `SECURITY.md` and Dependabot for Actions.

## [0.1.0] - 2026-10-25

### Added
- Initial release of cc-vitamins, a two-line Claude Code status line.
- Plan-aware output: Pro/Max 5h/7d windows with a reset countdown (`↻2h10m`),
  `≈` on dollar figures for subscribers (API-equivalent estimate, not a bill),
  gateway spend limit with percentage fallback and period.
- Rows wrap between segments to fit `COLUMNS`.
- Locale-independent number formatting (works under de_DE, uk_UA, etc.).
- Line 1 ("where am I"): vim mode, directory, git branch + dirty marker,
  worktree, agent, session name, model, effort, fast mode, duration, +/- lines.
- Line 2 ("what it costs"): context bar with per-turn delta, prompt cache hit
  ratio and warm/cold state with time-to-expiry, active-session count, session
  cost (today vs all-time), today's cost across all sessions via ccusage
  (cached, stale-while-revalidate, opt-in npx fallback), spend limit, and
  5h/7d rate limits.
- Single-pass stdin parsing: one jq invocation emits shell-quoted assignments.
- Configuration via `${XDG_CONFIG_HOME}/cc-vitamins/config` and `CC_VITAMINS_*`
  environment variables, including per-line segment toggles and ordering.
- `install.sh` with `--dry-run`, `--uninstall`, `--force`, and `--help`; backs
  up `settings.json`, preserves all other keys via an atomic jq write, sets
  `refreshInterval: 60`, and keeps the original statusLine across re-installs.
- Portable across macOS (BSD) and Linux (GNU); `#!/bin/sh`, shellcheck-clean.
- `NO_COLOR` support, test suite, and CI on ubuntu-latest and macos-latest.
