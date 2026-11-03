# Accounts: several Claude logins, one Claude Code

> Status: implemented in cc-vitamins 0.3.0 (`bin/ccv`, `lib/accounts.sh`).

## Goal

Some people have more than one Claude subscription, for example a company
Team/Enterprise seat and a personal Pro/Max plan. They want to:

1. pick an account per folder by default (company repos → work, the rest →
   personal);
2. switch account at any moment, in any folder, **inside the running
   session**, for example when a usage limit is close;
3. see in the status line which account is active right now;
4. change **nothing else**. Skills, plugins, MCP servers, hooks, settings,
   memory, `CLAUDE.md`, transcripts and history stay the same. Only the
   account that the model requests are billed to changes.

Non-goals: hot-swapping credentials inside a live process (Claude Code has no
API for that), managing API keys or cloud providers, bypassing any
organization policy.

## How Claude Code separates accounts

From the official docs:

- `CLAUDE_CONFIG_DIR` moves the whole config directory. "Each directory has its
  own settings, session history, and claude.ai login"
  ([authentication](https://code.claude.com/docs/en/authentication)).
- On macOS the Keychain entry is keyed to that directory, so two directories
  never see each other's login.
- `.claude.json` (login identity, org caches, user MCP servers, per-project
  state) moves into the directory too
  ([claude-directory](https://code.claude.com/docs/en/claude-directory)).
  Without `CLAUDE_CONFIG_DIR` it is `~/.claude.json`.
- Server-managed settings follow the organization of the credential in use,
  cached as `remote-settings.json` inside the directory.
- `claude --resume <session-id>` finds a transcript from any folder.
- Shell-mode (`!`) commands receive `CLAUDE_PID` and `CLAUDE_CODE_SESSION_ID`.

So the official mechanism already gives per-account login. cc-vitamins adds
**sharing** of everything else, a **switch** command and the **status line**.

## Model

- **Primary account** is the config directory the user already has
  (`~/.claude`, or `$CLAUDE_CONFIG_DIR` at setup time). It stays the single
  source of truth for all shared content. Nothing in it is moved.
- **Extra account** is a thin directory such as `~/.claude-personal`.
  Every top-level entry of the primary directory is a **symlink** to it,
  except the per-account files below.

### Per-account (never shared)

| Entry | Why |
|---|---|
| `.claude.json` | Login identity and organization caches (model access, limits, flags). |
| `.credentials.json` | Credential file (Keychain fallback / Linux). |
| `remote-settings.json*` | Organization's server-managed settings. |
| `policy-limits.json*` | Organization's policy limits. |

The primary account keeps using `~/.claude.json`. That is why the launcher
leaves `CLAUDE_CONFIG_DIR` **unset** for the primary account: setting it to
`~/.claude` explicitly would make Claude Code look for `~/.claude/.claude.json`
and a different Keychain entry, i.e. a fresh, logged-out profile.

### Shared parts of `.claude.json`

`.claude.json` cannot be a symlink, but two of its parts must look the same in
every account:

- `mcpServers` (user-scope MCP servers): union by name. If one name has
  different definitions, the primary wins and `ccv doctor` reports it.
- Per-project trust (`projects[<path>].hasTrustDialogAccepted`) for the folder
  being launched, so a trusted folder is not asked about again.

The launcher syncs these before starting Claude and writes only when something
differs (atomic replace). OAuth tokens for remote MCP servers stay per account
by design: each account authorizes its own.

### Everything else is shared

Transcripts (`projects/`), `history.jsonl`, `file-history/`, `settings.json`,
`settings.local.json`, `CLAUDE.md`, `rules/`, `skills/`, `agents/`,
`commands/`, `hooks/`, `plugins/`, `output-styles/`, `plans/`, `tasks/`, the
status line itself, and any entry Claude Code adds in the future. New entries
that appear in the primary directory are linked on the next launch.

## Configuration

One file, local to the user, never part of the repo:
`${XDG_CONFIG_HOME:-~/.config}/cc-vitamins/accounts`

```text
# name      config dir           color
account  work      ~/.claude            blue
account  personal  ~/.claude-personal   green

# folder (and everything under it) → account
route    ~/code/acme   work

# account for every other folder
default  personal
```

- The first `account` line is the primary.
- Routes match by resolved path prefix; the longest match wins.
- With no `default`, the primary account is the default.
- Without this file the feature is off: `claude` behaves exactly as before and
  the `account` segment is hidden.

## Commands

All commands come from one shell line that the installer offers to add:

```sh
eval "$("$HOME/.claude/cc-vitamins/bin/ccv" shell-init)"
```

It defines two shell functions, `claude` and `ccv`, and changes nothing else
in `PATH`. Supported shells: zsh and bash.

| Command | What it does |
|---|---|
| `ccv` / `ccv accounts` | List accounts: number, name, plan, logged in or not, current. |
| `ccv add <name> [--dir D] [--color C]` | Create the account directory and links, write the config line, run `claude auth login` for it, offer the shell setup. |
| `ccv login <name>` | Log in to that account again. |
| `ccv use <name\|number>` | Switch. Inside Claude (`! ccv use 2`): the same session continues under that account. In a terminal: every `claude` in this terminal uses it (`ccv use auto` undoes). |
| `ccv route <folder> <name>` | Add or replace a route. |
| `ccv default <name>` | Set the default account. |
| `ccv rename <old> <new>` | Rename an account in the config. |
| `ccv doctor` | Check links, per-account files, MCP drift, auth overrides, config. |
| `ccv shell-init [--install]` | Print the shell functions, or add the loader block to `~/.zshrc` / `~/.bashrc`. |
| `ccv remove <name>` | Log out that account and delete its thin directory. Shared content is untouched. |
| `claude --account <name> …` | One-off launch with a specific account; the flag is removed before Claude sees it. |

Example setup (any user):

```sh
ccv add personal               # creates ~/.claude-personal, opens login
ccv rename default work        # the existing login becomes "work"
ccv route ~/code/acme work
ccv default personal
```

## Switching inside a session

```text
! ccv use personal
```

1. `ccv` reads `CLAUDE_CODE_SESSION_ID` and `CLAUDE_PID` from the shell-mode
   environment, and `CCV_RUN`, a random token that the `claude` function
   exported when it started this Claude process.
2. It writes the request `{session, account}` to
   `${XDG_STATE_HOME:-~/.local/state}/cc-vitamins/switch/<CCV_RUN>` and stops
   the Claude process with `SIGTERM`. The transcript is already on disk:
   Claude Code saves it continuously.
3. The `claude` function sees that Claude exited, finds its request, and runs
   `claude --resume <session>` with the new account's environment, in the
   same terminal.

The current session ID is read at switch time, so it is correct after
`/resume` or `/clear`. Other Claude sessions are never touched.

Without the `claude` function (Claude started some other way) `ccv use`
does not stop anything; it prints the one command to run after `/exit`.

The wrapper is a plain loop in the shell function. Claude runs in the
foreground and owns the terminal; the function never forwards or ignores
Ctrl+C, so interrupting a generation works as usual.

**Limits, stated honestly.** This is a restart plus resume, not a hot swap.
Conversation, context and files carry over. A tool call, subagent or
background task running at the moment of the switch is interrupted and has to
be restarted ("continue"). The new account's limits and organization policy
apply from the first request after the switch.

## Status line: the `account` segment

```text
● personal Pro myproject …        ● work Enterprise myproject …
```

- Name and color come from the config.
- Plan comes from the account's own `.claude.json` (organization type); it is
  hidden when unknown.
- The active account is detected from the status line process environment
  (`CLAUDE_CONFIG_DIR`, unset = primary), not from the folder, so the segment
  shows what is really in use after a switch.
- Never shown: email, organization name, account or org IDs.
- Hidden when there is only one account. Add or move it with
  `CC_VITAMINS_LINE1`.

## Safety

- Credentials are never read, copied or linked. Login always happens through
  `claude auth login` in the target directory.
- `ccv doctor` and the launcher warn when `ANTHROPIC_API_KEY`,
  `ANTHROPIC_AUTH_TOKEN`, `CLAUDE_CODE_OAUTH_TOKEN` or a cloud-provider switch
  is set: these override any subscription login.
- Routes are defaults, not a policy. Using a personal account for company
  code, or the other way around, is the user's decision and may be against
  their employer's rules. cc-vitamins does not enforce or bypass anything.
- `ccv add` refuses to overwrite an existing non-empty directory. Every config
  change is atomic. `ccv remove` deletes only the thin directory.

## Open questions to verify on a real machine

1. Does Claude Code exit cleanly on `SIGTERM` with the transcript intact?
   Fallback: `SIGINT` twice or ask the user to `/exit`.
2. Does Claude Code replace any shared top-level **file** (for example
   `settings.json`) by write-then-rename, which would turn the symlink into a
   regular file in the extra account? If so, link the parent at a different
   level or relink and merge on launch; `ccv doctor` detects it either way.
3. Exact organization-type values for Pro and Max in `.claude.json`.
4. Do plugins installed from the primary account load unchanged in an extra
   account (absolute paths in `plugins/`)?

## Testing

`tests/run.sh` with a fake `claude` executable covering routing, link
creation and relinking, per-account exclusions, MCP union, the switch loop
(request, stop, resume with the same ID), the status line segment, and
`ccv remove`. Then a manual run on macOS with two real logins before
release.
