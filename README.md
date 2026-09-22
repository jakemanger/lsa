# als

`ls` for agent sessions. One command lists every Claude Code, Codex and pi
transcript on the machine, newest first, and reopens or prints any of them.

```
$ als -a
pi      3s ago   geniebottle   01a0c6b6  can you help me make a very simple ls command…
claude  3s ago   geniebottle   659c064b  can you help me make a very simple ls command…
codex   21h ago  howtoconvert  01a0b932  can you create a new update (next 0. something…
claude  22h ago  shotglass     b0b493c9  ok, i've had some really good posts on social…
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
als -l              add the file path and the resume command to each row

als show 659c       print a transcript as plain text
als path 659c       print where the transcript lives
als resume 659c     reopen it in its own agent
```

An id is any unique prefix of the one in the listing. `show` works well
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

Nothing is written, nothing leaves the machine.

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
