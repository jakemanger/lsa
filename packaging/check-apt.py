"""Verify the archive's signatures and every link in its SHA-256 chain."""
import gzip
import hashlib
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(sys.argv[1] if len(sys.argv) > 1 else "dist/site/apt").resolve()
trusted_key = Path(__file__).parent / "lsa-archive-keyring.asc"
assert (root / "lsa.asc").read_bytes() == trusted_key.read_bytes()
with tempfile.TemporaryDirectory(prefix="lsa-apt-verify-") as home:
    gpg = ["gpg", "--homedir", home, "--batch"]
    subprocess.run([*gpg, "--import", str(trusted_key)], check=True, capture_output=True)
    subprocess.run([*gpg, "--verify", str(root / "Release.gpg"), str(root / "Release")],
                   check=True, capture_output=True)
    cleartext = subprocess.check_output([*gpg, "--decrypt", str(root / "InRelease")],
                                        stderr=subprocess.DEVNULL)
    assert cleartext == (root / "Release").read_bytes()
release = (root / "Release").read_text().split("SHA256:\n", 1)[1]
checked = set()
for line in release.splitlines():
    digest, size, name = line.split()
    assert name in {"Packages", "Packages.gz"} and name not in checked
    checked.add(name)
    data = (root / name).read_bytes()
    assert len(data) == int(size) and hashlib.sha256(data).hexdigest() == digest
assert checked == {"Packages", "Packages.gz"}
assert gzip.decompress((root / "Packages.gz").read_bytes()) == (root / "Packages").read_bytes()
count = 0
for paragraph in (root / "Packages").read_text().strip().split("\n\n"):
    fields = dict(line.split(": ", 1) for line in paragraph.splitlines()
                  if line and not line[0].isspace())
    assert fields["Package"] == "lsa" and fields["Architecture"] == "all"
    path = (root / fields["Filename"]).resolve()
    assert path.is_relative_to(root / "pool")
    data = path.read_bytes()
    assert len(data) == int(fields["Size"])
    assert hashlib.sha256(data).hexdigest() == fields["SHA256"]
    count += 1
assert (root / "lsa.sources").read_bytes() == (trusted_key.parent / "lsa.sources").read_bytes()
print(f"ok   APT signatures, indexes and {count} package(s)")
