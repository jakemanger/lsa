#!/usr/bin/env python3
"""Render the marked social take, shortening waits while preserving its output.

Usage: python3 demo/render-social.py path/to/raw.cast path/to/output-stem
Keeps the raw cast unchanged. Writes an edited cast, GIF, MP4, cover and timing map.
"""
import json
import re
import subprocess
import sys
from pathlib import Path

source = Path(sys.argv[1])
stem = Path(sys.argv[2])
stem.parent.mkdir(parents=True, exist_ok=True)
items = [json.loads(line) for line in source.read_text().splitlines()]
header = items[0]
if header.get('version') != 3:
    raise SystemExit('Expected the existing pipeline’s asciicast v3 format')
marker = re.compile(r'\x1b\]777;lsa-demo:([a-z.]+)\x07')
events, marks, clock = [], {}, 0.0
for event in items[1:]:
    clock += event[0]
    if event[1] == 'o':
        for label in marker.findall(event[2]):
            marks[label] = clock
        event[2] = marker.sub('', event[2])
    events.append((clock, event))
required = [f'{agent}.{stage}' for agent in ('claude', 'codex')
            for stage in ('start', 'ready', 'submit', 'reply', 'exit')]
if missing := set(required) - marks.keys():
    raise SystemExit(f'Incomplete recording; missing {sorted(missing)}')

# Only startup and model-wait intervals are accelerated. Character typing,
# shell commands, and the exits retain their original timings.
intervals = []
for agent, stage, end, maximum in [
    ('claude', 'start', 'ready', 0.25),
    ('claude', 'submit', 'reply', 0.9),
    ('codex', 'start', 'ready', 0.35),
    ('codex', 'submit', 'reply', 1.4),
]:
    a, b = marks[f'{agent}.{stage}'], marks[f'{agent}.{end}']
    intervals.append((a, b, min(b-a, maximum)))

def compressed(t):
    result = t
    for a, b, length in intervals:
        if t > a:
            result -= min(t-a, b-a) * (1-length/(b-a))
    return result

# Do not pad to a target length. Keep the recorded reading pauses and opening
# keystrokes; the finished clip should end as soon as the workflow is complete.
tail = 0.2
def edited_time(t):
    return compressed(t)

edited = stem.with_suffix('.cast')
previous = 0.0
header['idle_time_limit'] = 60
header['title'] = 'lsa: Claude Code to Codex — waiting shortened'
with edited.open('w') as handle:
    handle.write(json.dumps(header)+'\n')
    for t, event in events:
        new_t = edited_time(t)
        event[0] = round(new_t-previous, 6)
        previous = new_t
        handle.write(json.dumps(event, ensure_ascii=False)+'\n')
timing = {key: round(edited_time(value), 3) for key, value in marks.items()}
timing.update(raw_duration=round(clock, 3),
              edited_duration=round(edited_time(clock)+tail, 3),
              note='Real recorded output. Startup and model waits shortened. No added holds, opening trim, or duration padding.')
stem.with_suffix('.timing.json').write_text(json.dumps(timing, indent=2)+'\n')
subprocess.run(['agg', '--quiet', '--theme', 'github-dark', '--font-size', '30',
                '--font-family', 'JuliaMono,JetBrains Mono,Menlo,DejaVu Sans Mono',
                '--font-dir', str(Path(__file__).resolve().parent.parent/'.tools/demo-fonts'),
                '--idle-time-limit', '60', '--last-frame-duration', str(tail),
                str(edited), str(stem.with_suffix('.gif'))], check=True)
subprocess.run(['ffmpeg', '-y', '-hide_banner', '-loglevel', 'error',
                '-i', str(stem.with_suffix('.gif')),
                '-vf', 'fps=30,scale=1080:-2:flags=lanczos',
                '-c:v', 'libx264', '-preset', 'medium', '-crf', '18',
                '-pix_fmt', 'yuv420p', '-movflags', '+faststart', '-an',
                str(stem.with_suffix('.mp4'))], check=True)
subprocess.run(['ffmpeg', '-y', '-hide_banner', '-loglevel', 'error', '-ss', '1',
                '-i', str(stem.with_suffix('.mp4')), '-frames:v', '1', '-q:v', '2',
                str(stem.parent/(stem.name+'-cover.jpg'))], check=True)
timing['video_duration'] = float(subprocess.check_output([
    'ffprobe', '-v', 'error', '-show_entries', 'format=duration',
    '-of', 'default=noprint_wrappers=1:nokey=1', str(stem.with_suffix('.mp4')),
], text=True).strip())
stem.with_suffix('.timing.json').write_text(json.dumps(timing, indent=2)+'\n')
print(json.dumps(timing, indent=2))
