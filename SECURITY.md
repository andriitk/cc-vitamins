# Security policy

cc-vitamins runs on every Claude Code status line render and edits
`settings.json` during install, so security reports are taken seriously.

## Reporting a vulnerability

Please report privately through GitHub:
**Security → Report a vulnerability** on this repository. Do not open a public
issue. You can expect a first response within a few days.

## Scope

- `bin/cc-vitamins` and `lib/`: anything that lets status line input (paths,
  branch or session names, model names) execute code or inject terminal
  escape sequences.
- `install.sh`: anything that could clobber or leak data in `settings.json`, or
  fetch code from somewhere other than this repository.

Only the latest release is supported.
