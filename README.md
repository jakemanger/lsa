# als

`ls` for agent sessions. One command lists every Claude Code, Codex and pi
transcript on the machine, newest first, and reopens or prints any of them.

```
$ als -a
  0 pi      3s ago   geniebottle   01a0c6  can you help me make a very simple ls command…
  1 claude  3s ago   geniebottle   659c    can you help me make a very simple ls command…
  2 codex   21h ago  howtoconvert  01a0b9  can you create a new update (next 0. something…
  3 claude  22h ago  shotglass     b0b4    ok, i've had some really good posts on social…
```

Like `ls`, `als` on its own lists the sessions started in the current
directory. `-a` lists them all.

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

A session is named by its index or its id. Index 0 is the newest session
on the machine and the numbers are global, so `als resume 3` is the same
session whether you listed with `-a` or not. Ids are the shortest prefix
that is unique on your machine, the way git shortens hashes; any longer
prefix of the full id works too. With `-l`
each row carries the agent's own command, so you can paste that instead:

```
$ als -l -n 2
  0 claude  22h ago  shotglass     b0b4    ok, i've had some really good posts…
            $ claude --resume b0b493c9-1f3d-4e1e-9d3f-2b7c8a0f1e21
  1 codex   21h ago  howtoconvert  01a0b9  can you create a new update…
            $ codex resume 01a0b932-3e57-7401-949a-66354671f006
``` `show` works well
with a pager or grep:

```
als show 659c | less
als show 659c | grep -n 'TODO'
```

## Where it looks

| Agent       | Directory                              | Override                |
|-------------|----------------------------------------|-------------------------|
| Claude Code | `~/.claude/projects/*/*.jsonl`         | `CLAUDE_CONFIG_DIR`     |
| Codex       | `~/.codex/sessions/YYYY/MM/DD/*.jsonl` | `CODEX_HOME`            |
| pi          | `~/.pi/agent/sessions/*/*.jsonl`       | `PI_CODING_AGENT_DIR`   |

Claude Code's sub-agent files and Codex Desktop's internal reviewer threads
(`guardian_review`) are skipped: they are not sessions you can resume.

A session's directory and first prompt never change, so they are cached
in `~/.cache/als/` after the first run. Listing is then a directory scan,
about the cost of `ls -l` on the same files. Delete the cache directory
if you ever want a rescan. Nothing else is written, nothing leaves the
machine.

## Adding an agent

Three things per agent in `als`: a directory in the settings block, a
`read_<agent>` function that prints the cwd, id and first prompt of a
file, and a `find` line in `find_all`. Add a `jq` filter in `cmd_show`
if you want `show` to work. Pull requests welcome.

## Development

```
make test      run the fixture tests
make lint      shellcheck
make deb       build a .deb (needs dpkg-deb)
make install   copy to /usr/local/bin
```

## Licence

MIT.
