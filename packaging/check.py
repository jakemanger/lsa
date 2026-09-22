"""Check package contents, metadata, permissions and release checksums locally."""
import hashlib
from pathlib import Path
import shutil
import stat
import struct
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
dist = root / "dist"
version = subprocess.check_output([str(root / "lsa"), "--version"], text=True).strip()
number = version.split()[1]
expected = {"lsa", "lsa.deb", "lsa.rpm", "lsa.pkg.tar.zst", "lsa.rb"}
checksums = {}
for line in (dist / "SHA256SUMS").read_text().splitlines():
    digest, name = line.split()
    assert name in expected and name not in checksums, name
    assert hashlib.sha256((dist / name).read_bytes()).hexdigest() == digest, name
    checksums[name] = digest
assert set(checksums) == expected, "Build all formats with make packages first"
assert (dist / "lsa").read_bytes() == (root / "lsa").read_bytes()
assert (dist / "lsa.rb").read_bytes() == (root / "Formula/lsa.rb").read_bytes(), "Run make formula"
assert checksums["lsa"] in (dist / "lsa.rb").read_text()
assert f"/releases/download/v{number}/lsa" in (dist / "lsa.rb").read_text()
print("ok   release checksums and Homebrew formula match the source")

tar = shutil.which("bsdtar") or shutil.which("tar")
assert tar and "libarchive" in subprocess.check_output([tar, "--version"], text=True), (
    "Package checks need bsdtar (macOS tar, or apt install libarchive-tools)"
)


def extract(archive, target):
    target.mkdir()
    subprocess.run([tar, "-xf", str(archive), "-C", str(target)], check=True)


with tempfile.TemporaryDirectory(prefix="lsa-packages-") as temp:
    stage = Path(temp)
    extract(dist / "lsa.deb", stage / "deb-outer")
    assert (stage / "deb-outer/debian-binary").read_text().strip() == "2.0"
    extract(stage / "deb-outer/control.tar.gz", stage / "deb-control")
    extract(stage / "deb-outer/data.tar.gz", stage / "deb")
    extract(dist / "lsa.rpm", stage / "rpm")
    extract(dist / "lsa.pkg.tar.zst", stage / "arch")
    for kind in ("deb", "rpm", "arch"):
        package = stage / kind
        binary = package / "usr/bin/lsa"
        assert binary.read_bytes() == (root / "lsa").read_bytes(), kind
        assert stat.S_IMODE(binary.stat().st_mode) == 0o755, kind
        assert subprocess.check_output([str(binary), "--version"], text=True).strip() == version
        assert (package / "usr/share/doc/lsa/README.md").read_bytes() == (root / "README.md").read_bytes()
        assert (package / "usr/share/licenses/lsa/LICENSE").read_bytes() == (root / "LICENSE").read_bytes()
        files = {str(p.relative_to(package)) for p in package.rglob("*") if p.is_file()}
        allowed = {"usr/bin/lsa", "usr/share/doc/lsa/README.md", "usr/share/licenses/lsa/LICENSE"}
        if kind == "deb":
            allowed.add("usr/share/doc/lsa/copyright")
        if kind == "arch":
            allowed.update({".PKGINFO", ".MTREE"})
        assert files == allowed, (kind, files)
        print(f"ok   {kind}: exact executable, mode, docs and version; no install hooks")
    control = (stage / "deb-control/control").read_text().splitlines()
    assert {"Package: lsa", f"Version: {number}-1", "Architecture: all"}.issubset(control)
    deps = next(line for line in control if line.startswith("Depends:"))
    assert "jq" in deps and "sqlite3" in deps and "procps" in deps
    assert {p.name for p in (stage / "deb-control").iterdir()} <= {"control", "md5sums", "conffiles"}
    info = (stage / "arch/.PKGINFO").read_text().splitlines()
    assert {"pkgname = lsa", f"pkgver = {number}-1", "arch = any", "depend = jq", "depend = sqlite"}.issubset(info)

# Read the RPM's signature and main headers; no rpm installation is needed.
data = (dist / "lsa.rpm").read_bytes()


def rpm_header(offset):
    magic, _, _, count, size = struct.unpack_from(">3sB4sII", data, offset)
    assert magic == b"\x8e\xad\xe8"
    base = offset + 16 + count * 16
    values = {}
    for i in range(count):
        tag, kind, start, length = struct.unpack_from(">IIII", data, offset + 16 + i * 16)
        if kind in (6, 8, 9):
            values[tag] = data[base + start:base + size].split(b"\0")[:length]
    return base + size, values


end, _ = rpm_header(96)
_, fields = rpm_header((end + 7) // 8 * 8)
assert fields[1000] == [b"lsa"]
assert fields[1001] == [number.encode()]
assert fields[1002] == [b"1"]
assert fields[1022] == [b"noarch"]
assert {b"jq", b"sqlite", b"procps-ng"}.issubset(fields[1049])
assert not {1023, 1024, 1025, 1026}.intersection(fields), "Unexpected RPM install hooks"
print("ok   Debian, RPM and Arch metadata, architecture and dependencies")

# Test the documented manual install in a temporary prefix.
with tempfile.TemporaryDirectory(prefix="lsa-install-") as temp:
    subprocess.run(["make", "install", f"PREFIX={temp}"], cwd=root, check=True, stdout=subprocess.DEVNULL)
    assert subprocess.check_output([f"{temp}/bin/lsa", "--version"], text=True).strip() == version
    subprocess.run(["make", "uninstall", f"PREFIX={temp}"], cwd=root, check=True, stdout=subprocess.DEVNULL)
    assert not Path(temp, "bin/lsa").exists()
print("ok   make install and uninstall in an isolated prefix")
