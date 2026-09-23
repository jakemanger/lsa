<h1><img src="assets/logo.png" alt="" height="64"> lsa</h1>

`ls` for agent sessions. List every session from every coding agent on the
machine, newest first. Resume the conversation, print it or pipe it to another
agent.

![lsa listing sessions](demo/list.gif)

Like `ls`, `lsa` on its own lists the sessions started in the current
directory. `-a` lists them all. Listing takes about as long as `ls -l`.

## Install

One command, on macOS or Linux:

```sh
curl -fLO https://github.com/jakemanger/lsa/releases/latest/download/lsa && sudo install lsa /usr/local/bin/
```

Downloads `lsa` and installs it with executable permissions.

**Oh My Zsh?** Replace its default `lsa='ls -lah'` alias with the `lsa` command:

```sh
printf '\nunalias lsa 2>/dev/null\n' >> ~/.zshrc && source ~/.zshrc
```

Needs bash 3.2 or later, grep, sed, awk, find, stat and ps. `lsa show` also
needs `jq`, and the database-backed agents need `sqlite3`.

### Package managers

Homebrew (macOS and Linux):

```sh
brew install jakemanger/tap/lsa
```

Debian / Ubuntu:

```sh
sudo mkdir -p /etc/apt/keyrings
sudo curl -fsSL https://jakemanger.github.io/lsa/apt/lsa.asc -o /etc/apt/keyrings/lsa.asc
sudo curl -fsSL https://jakemanger.github.io/lsa/apt/lsa.sources -o /etc/apt/sources.list.d/lsa.sources
sudo apt update && sudo apt install lsa
```

Add the repository once; subsequent updates come through `sudo apt upgrade`.

Fedora / RHEL:

```sh
curl -fLO https://github.com/jakemanger/lsa/releases/latest/download/lsa.rpm
sudo dnf install ./lsa.rpm
```

Arch Linux:

```sh
curl -fLO https://github.com/jakemanger/lsa/releases/latest/download/lsa.pkg.tar.zst
sudo pacman -U ./lsa.pkg.tar.zst
```

The Homebrew tap supports `brew upgrade lsa`. RPM and Arch packages are
release downloads; use the same commands to update them. All package managers
install the required dependencies.

## Agents

| Agent | | List | Show | Resume | Tested |
|---|---|:-:|:-:|:-:|:-:|
| Claude Code | ✳ | ✓ | ✓ | ✓ | ✓ |
| Codex | ⌘ | ✓ | ✓ | ✓ | ✓ |
| pi | π | ✓ | ✓ | ✓ | ✓ |
| Qwen Code | ❯ | ✓ | ✓ | ✓ | ✓ |
| OpenCode | ◐ | ✓ | ✓ | ✓ | ✓ |
| Goose | 🪿 | ✓ | ✓ | ✓ | ✓ |
| Cline | ⌬ | ✓ | ✓ | ✓ | ✓ |
| Muse Code (Meta) | ◈ | ✓ | ✓ | ✓ | ✓ |
| OpenClaw | 🦞 | ✓ | ✓ | ✓ | ✓ |
| Gemini CLI | ✦ | ✓ | ✓ | ✓ | from source |

Tested means I installed the agent, ran a session and checked that `lsa`
listed it, printed it and reopened it. Gemini CLI needs a Google account
I do not have, so its reader was written from the CLI's own source and
the fixture matches what that code writes.

Resume runs the agent's own command (`claude --resume`, `codex resume`,
`muse resume`, and so on) from the directory the session was started in,
because most agents only find a session from there. `lsa -l` adds the full
working directory and transcript path as columns on the same row.
OpenClaw sessions
are chats rather than projects, so their directory column shows the session
key instead.

## Why a list

Tools like herdr and Claude Squad run the agents for you, a pane each, with a
live view of which one is blocked. `lsa` assumes they have already run. It
reads the transcripts they leave behind so you can get back into one, and
nothing of it stays running afterwards.

If all you wanted from a session manager was to find the conversation you were
in and pick it up again, this is one that is one more letter than `ls`.

## Use

```
lsa                 sessions started in this directory
lsa -a              every session
lsa ~/code/foo      sessions started in another directory
lsa -t codex -n 5   the five newest Codex sessions
lsa -l              add full directory and transcript path columns

lsa show 659c       print a transcript as plain text
lsa path 659c       print where the transcript lives
lsa resume 659c     reopen it in its own agent
lsa resume 0        the same by index, like tmux attach -t 0
```

![lsa picking a session](demo/pick.gif)

A session whose transcript changed in the last two minutes, and whose agent
has a live process, shows a green `●` and how long the current turn has been
running, counted from the last prompt you typed, in place of its age:

```
  0 claude   ● 2m      3e1f    add a --dry-run flag to the deploy script
  1 codex    15m ago   01a0c7d the flaky test in api/test_auth.py
```

Use a session's index or short id. Index 0 is the newest session.
Indexes stay the same when filtering.

Any unique prefix of the full id also works.

Pipe a transcript to a pager or search it:

```
lsa show 659c | less
lsa show 659c | grep -n 'TODO'
```

### Switch agents

Pick a session from `lsa`, then continue it in Claude from its project directory:

```sh
lsa show 659c | claude "Continue this conversation from where it left off."
```

For Codex or Pi, pass the transcript as the opening prompt:

```sh
codex "Continue this conversation: $(lsa show 659c)"
pi "Continue this conversation: $(lsa show 659c)"
```

To send just the last 200 lines:

```sh
lsa show 659c | tail -n 200 | claude "Continue this conversation."
```

## Where it looks

| Agent       | Where                                                       | Override              |
|-------------|-------------------------------------------------------------|-----------------------|
| Claude Code | `~/.claude/projects/*/*.jsonl`                              | `CLAUDE_CONFIG_DIR`   |
| Codex       | `~/.codex/sessions/YYYY/MM/DD/*.jsonl`                      | `CODEX_HOME`          |
| pi          | `~/.pi/agent/sessions/*/*.jsonl`                            | `PI_CODING_AGENT_DIR` |
| Qwen Code   | `~/.qwen/projects/*/chats/*.jsonl`                          | |
| Gemini CLI  | `~/.gemini/tmp/*/chats/session-*.jsonl` + `projects.json`   | `GEMINI_CLI_HOME` |
| Cline       | `~/.cline/data/sessions/*/*.json`                           | |
| OpenCode    | `~/.local/share/opencode/opencode.db`                       | `XDG_DATA_HOME` |
| Goose       | `~/.local/share/goose/sessions/sessions.db`                 | `XDG_DATA_HOME` |
| Muse Code   | `~/.local/share/muse/session-index.db`                      | `XDG_DATA_HOME` |
| OpenClaw    | `~/.openclaw/agents/*/agent/openclaw-agent.sqlite`          | |

The last four are SQLite databases and are read with the `sqlite3` binary
that ships with macOS and most Linux distributions; without it those
agents are silently skipped.

A session's directory and first prompt never change, so they are cached in
`~/.cache/lsa/` after the first run. Listing is then one directory scan,
one `stat` and one `awk`, about the cost of `ls -l` on the same files.
Delete the cache directory if you ever want a rescan. Nothing else is
written, nothing leaves the machine.

## Adding an agent

Open an issue with the agent's name, version and a sample session file.
Pull requests with support and a test are welcome too.

## Development

```
make test        run the fixture tests
make lint        ShellCheck, workflow lint and formula syntax
make packages    build .deb, .rpm and Arch packages (needs nFPM)
make check-packages  check the release files locally
make formula     refresh the Homebrew formula's version and checksum
make install     copy to /usr/local/bin
demo/record.sh   re-record the gifs (asciinema + agg, Goose over ollama,
                 and an authenticated Claude Code for the handoff)
```

## Licence

MIT.

Made with ❤️ and ☕ by Jake Manger
