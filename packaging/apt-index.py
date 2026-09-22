"""Build a flat APT repository from released, architecture-independent packages."""
import email.utils
import gzip
import hashlib
import io
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile
from datetime import datetime, timezone

source, output = map(Path, sys.argv[1:])
archives = sorted(source.rglob("*.deb"))
if not archives:
    raise SystemExit(f"No .deb packages in {source}")
if output.exists():
    raise SystemExit(f"Output already exists: {output}; use a fresh directory")
tar = shutil.which("bsdtar") or shutil.which("tar")
if not tar or "libarchive" not in subprocess.check_output([tar, "--version"], text=True):
    raise SystemExit("Install libarchive-tools (macOS tar also works)")

entries = []
versions = set()
for archive in archives:
    control_tar = subprocess.check_output([tar, "-xOf", str(archive), "control.tar.gz"])
    with tarfile.open(fileobj=io.BytesIO(control_tar), mode="r:gz") as control:
        member = next(m for m in control if m.name.removeprefix("./") == "control")
        metadata = control.extractfile(member).read().decode().strip()
    fields = dict(line.split(": ", 1) for line in metadata.splitlines()
                  if line and not line[0].isspace())
    version = fields.get("Version", "")
    if (fields.get("Package") != "lsa" or fields.get("Architecture") != "all"
            or not re.fullmatch(r"[0-9][A-Za-z0-9.+:~\-]*", version)):
        raise SystemExit(f"Expected an architecture-independent lsa package: {archive}")
    if version in versions:
        raise SystemExit(f"Duplicate package version: {version}")
    versions.add(version)
    data = archive.read_bytes()
    filename = f"pool/lsa_{version}_all.deb"
    entries.append(f"{metadata}\nFilename: {filename}\nSize: {len(data)}\n"
                   f"SHA256: {hashlib.sha256(data).hexdigest()}\n\n")
    # Validate every package before creating the output.

(output / "pool").mkdir(parents=True)
for archive, entry in zip(archives, entries):
    filename = next(line.removeprefix("Filename: ") for line in entry.splitlines()
                    if line.startswith("Filename: "))
    shutil.copyfile(archive, output / filename)
packages = "".join(entries).encode()
(output / "Packages").write_bytes(packages)
(output / "Packages.gz").write_bytes(gzip.compress(packages, mtime=0))
release = ("Origin: lsa\nLabel: lsa\n"
           "Description: ls for agent sessions\n"
           f"Date: {email.utils.format_datetime(datetime.now(timezone.utc), usegmt=True)}\n"
           "SHA256:\n")
for name in ("Packages", "Packages.gz"):
    data = (output / name).read_bytes()
    release += f" {hashlib.sha256(data).hexdigest()} {len(data)} {name}\n"
(output / "Release").write_text(release)
print(f"Indexed {len(archives)} lsa version(s) in {output}")
