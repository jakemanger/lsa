# als

`ls` for agent sessions. One command lists every coding-agent transcript on
the machine, newest first, then prints or reopens any of them.

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
curl -LO https://github.com/jakemanger/als/releases/latest/download/als_all.deb
sudo apt install ./als_all.deb
```

Anywhere else: it is one bash script.

```
curl -fsSL https://raw.githubusercontent.com/jakemanger/als/main/als -o /usr/local/bin/als
chmod +x /usr/local/bin/als
```

Needs bash 3.2 or later, grep, sed, awk and stat. `als show` also needs `jq`.

## Agents

| Agent | | List | Show | Resume | Status |
|---|---|:-:|:-:|:-:|---|
| Claude Code | ✳ | ✓ | ✓ | ✓ | ✓ tested on real sessions |
| Codex | ⌘ | ✓ | ✓ | ✓ | ✓ tested on real sessions |
| pi | π | ✓ | ✓ | ✓ | ✓ tested on real sessions |
| Gemini CLI | ✦ | ✓ | ✓ | ✓ | ○ from the documented format |
| Qwen Code | ❯ | ✓ | ✓ | ✓ | ○ from the documented format |
| OpenCode | ◐ | ✓ | – | ✓ | ○ from the documented format |
| Goose | 🪿 | ✓ | ✓ | ✓ | ○ from the documented format |
| Cline | ⌬ | ✓ | ✓ | – | ○ from the documented format |

✓ means I ran it against my own transcripts. ○ means the reader was written
from the agent's documented file layout and passes the fixture tests, but I
have not had a real session file to check it against. If you use one of
those agents, run `als -a -t <agent>` and open an issue with what you see,
good or bad, and it gets a tick. Want another agent? Attach one session
file to an issue.

Skipped on purpose: Claude Code's sub-agent files, Codex Desktop's internal
reviewer threads (`guardian_review`), and any tool that keeps sessions in a
database rather than files (Cursor, Crush).

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

| Agent       | Directory                                                        | Override              |
|-------------|------------------------------------------------------------------|-----------------------|
| Claude Code | `~/.claude/projects/*/*.jsonl`                                   | `CLAUDE_CONFIG_DIR`   |
| Codex       | `~/.codex/sessions/YYYY/MM/DD/*.jsonl`                           | `CODEX_HOME`          |
| pi          | `~/.pi/agent/sessions/*/*.jsonl`                                 | `PI_CODING_AGENT_DIR` |
| Gemini CLI  | `~/.gemini/tmp/*/chats/session-*.json`                           | |
| Qwen Code   | `~/.qwen/tmp/*/chats/session-*.json`                             | |
| OpenCode    | `~/.local/share/opencode/storage/session/*/ses_*.json`           | `XDG_DATA_HOME` |
| Goose       | `~/.local/share/goose/sessions/*.jsonl`                          | `XDG_DATA_HOME` |
| Cline       | VS Code `globalStorage/saoudrizwan.claude-dev/tasks/*/`          | |

A session's directory and first prompt never change, so they are cached in
`~/.cache/als/` after the first run. Listing is then one directory scan,
one `stat` and one `awk`, about the cost of `ls -l` on the same files.
Delete the cache directory if you ever want a rescan. Nothing else is
written, nothing leaves the machine.

## Adding an agent

Three places in `als`: a line in the `ROOTS` table, a branch in the
`parse` awk that pulls the directory and first prompt out of one file, and
a branch in `join_cache` that takes the id from the file name. Add a
`resume_cmd` case and a `jq` filter in `cmd_show` if the agent has them.
Then a fixture in `test.sh`. Pull requests welcome.

## Development

```
make test        run the fixture tests
make lint        shellcheck
make deb         build a .deb (needs dpkg-deb)
make install     copy to /usr/local/bin
demo/record.sh   re-record the gifs (asciinema + agg, invented sessions)
```

## Licence

MIT.
