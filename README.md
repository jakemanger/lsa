# als

`ls` for agent sessions. One command lists every session from every coding
agent on the machine, newest first, then prints or reopens any of them.

![als listing sessions](demo/list.gif)

Like `ls`, `als` on its own lists the sessions started in the current
directory. `-a` lists them all. Listing takes about as long as `ls -l`.

## Install

Homebrew:

```
brew install jakemanger/tap/als
```

Debian / Ubuntu (a `.deb` is attached to every release):

```
curl -LO https://github.com/jakemanger/als/releases/latest/download/als.deb
sudo apt install ./als.deb
```

Anywhere else: it is one bash script.

```
curl -fsSL https://raw.githubusercontent.com/jakemanger/als/main/als -o /usr/local/bin/als
chmod +x /usr/local/bin/als
```

Needs bash 3.2 or later, grep, sed, awk and stat. `als show` also needs `jq`,
and the database-backed agents need `sqlite3`.

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

Tested means I installed the agent, ran a session and checked that `als`
listed it, printed it and reopened it. Gemini CLI needs a Google account
I do not have, so its reader was written from the CLI's own source and
the fixture matches what that code writes; if you use it, `als -a -t gemini`
and an issue with what you see, good or bad, gets it a tick. Want another
agent? Open an issue with one session file.

Resume runs the agent's own command (`claude --resume`, `codex resume`,
`muse resume`, and so on) from the directory the session was started in;
`als -l` prints it if you would rather paste it yourself. OpenClaw sessions
are chats rather than projects, so their directory column shows the session
key instead.

Skipped on purpose: Claude Code's sub-agent files, Codex Desktop's internal
reviewer threads (`guardian_review`), OpenCode's sub-agent sessions, and
Cline's VS Code extension, which keeps its tasks in a different place from
the Cline CLI. Cursor is not read.

## Use

```
als                 sessions started in this directory
als -a              every session
als ~/code/foo      sessions started in another directory
als -t codex -n 5   the five newest Codex sessions
als -l              show the command that resumes each session
als -L              show each transcript's path

als show 659c       print a transcript as plain text
als path 659c       print where the transcript lives
als resume 659c     reopen it in its own agent
als resume 0        the same by index, like tmux attach -t 0
```

![als picking a session](demo/pick.gif)

A session whose transcript changed in the last two minutes, and whose agent
has a live process, shows `● working` instead of its age. That is the
whole detection: an agent writes to its transcript while it works and stops
when it is waiting on you, so an open but idle session is not marked.

A session is named by its index or its id. Index 0 is the newest session
on the machine and the numbers are global, so `als resume 3` is the same
session whether you listed with `-a` or not. Ids are the shortest prefix
that is unique on your machine, the way git shortens hashes; any longer
prefix of the full id works too. `show` works well with a pager or grep:

```
als show 659c | less
als show 659c | grep -n 'TODO'
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
`~/.cache/als/` after the first run. Listing is then one directory scan,
one `stat` and one `awk`, about the cost of `ls -l` on the same files.
Delete the cache directory if you ever want a rescan. Nothing else is
written, nothing leaves the machine.

## Adding an agent

For an agent that writes files: a line in the `ROOTS` table, a branch in
the `parse` awk that pulls the directory and first prompt out of one file,
and a branch in `join_cache` that takes the id from the file name. For one
that keeps a database: a query in `db_rows`. Then a `resume_cmd` case, a
`cmd_show` case, and a fixture in `test.sh`. Pull requests welcome, and
please say which version of the agent wrote your fixture.

## Development

```
make test        run the fixture tests
make lint        shellcheck
make deb         build a .deb (needs dpkg-deb)
make install     copy to /usr/local/bin
demo/record.sh   re-record the gifs (asciinema + agg; invented sessions,
                 plus one real Goose session over ollama for the resume)
```

## Licence

MIT.
