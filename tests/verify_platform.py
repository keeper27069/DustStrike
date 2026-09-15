"""Check editor regressions and a matching released native build on Windows/Linux.

Run with RELEASE_TAG=v0.1.0, GITHUB_REPOSITORY=owner/repo and GH_TOKEN set.
The release may be a draft visible to that token. Uses Python's standard library
and GitHub CLI; no engine or export templates need to be preinstalled.
"""

from pathlib import Path, PurePosixPath
import hashlib
import os
import platform
import re
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.request
import zipfile


VERSION = "4.5.1-stable"
OFFICIAL = f"https://github.com/godotengine/godot/releases/download/{VERSION}/"
PLATFORMS = {
    "Windows": ("win64.exe.zip", "win64_console.exe", "Windows-x86_64.zip", "DustStrike.exe"),
    "Linux": ("linux.x86_64.zip", "linux.x86_64", "Linux-x86_64.tar.gz", "DustStrike.x86_64"),
}
ERROR_PATTERN = re.compile(r"\b(?:SCRIPT ERROR|ERROR|Parse Error|Assertion failed)\b", re.I)


def download(url, destination, limit=256 * 1024 * 1024):
    request = urllib.request.Request(url, headers={"User-Agent": "DustStrike-platform-check"})
    deadline = time.monotonic() + 240
    size = 0
    with urllib.request.urlopen(request, timeout=30) as response, destination.open("wb") as out:
        while True:
            chunk = response.read(1024 * 1024)
            if not chunk:
                break
            size += len(chunk)
            if size > limit or time.monotonic() > deadline:
                raise RuntimeError(f"Download exceeded its size/time limit: {destination.name}")
            out.write(chunk)


def verify_checksum(archive, manifest, algorithm):
    expected = []
    for line in manifest.read_text(encoding="utf-8-sig").splitlines():
        fields = line.split(maxsplit=1)
        if len(fields) == 2 and fields[1].lstrip("*").removeprefix("./") == archive.name:
            expected.append(fields[0].lower())
    length = hashlib.new(algorithm).digest_size * 2
    if len(expected) != 1 or not re.fullmatch(f"[0-9a-f]{{{length}}}", expected[0]):
        raise RuntimeError(f"Missing or ambiguous {algorithm} checksum for {archive.name}")
    digest = hashlib.new(algorithm)
    with archive.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    if digest.hexdigest() != expected[0]:
        raise RuntimeError(f"{algorithm} checksum mismatch: {archive.name}")
    print(f"Verified {algorithm}: {archive.name}", flush=True)


def safe_extract(archive, destination):
    """Extract only regular files/directories into a fresh, bounded directory."""
    destination.mkdir(parents=True, exist_ok=False)

    def validate(name):
        path = PurePosixPath(name)
        if path.is_absolute() or ".." in path.parts or "\\" in name or ":" in name:
            raise RuntimeError(f"Unsafe archive path: {name!r}")

    if zipfile.is_zipfile(archive):
        with zipfile.ZipFile(archive) as bundle:
            entries = bundle.infolist()
            if len(entries) > 10000 or sum(item.file_size for item in entries) > 1024 ** 3:
                raise RuntimeError("ZIP exceeds extraction limits")
            for item in entries:
                validate(item.filename)
                if stat.S_ISLNK(item.external_attr >> 16):
                    raise RuntimeError("Archive links are not supported")
            bundle.extractall(destination)
    else:
        with tarfile.open(archive, "r:gz") as bundle:
            entries = bundle.getmembers()
            if len(entries) > 10000 or sum(item.size for item in entries) > 1024 ** 3:
                raise RuntimeError("TAR exceeds extraction limits")
            for item in entries:
                validate(item.name)
                if not (item.isfile() or item.isdir()):
                    raise RuntimeError("Archive links and special files are not supported")
            for item in entries:
                target = destination.joinpath(*PurePosixPath(item.name).parts)
                if item.isdir():
                    target.mkdir(parents=True, exist_ok=True)
                else:
                    target.parent.mkdir(parents=True, exist_ok=True)
                    with bundle.extractfile(item) as source, target.open("wb") as out:
                        shutil.copyfileobj(source, out)


def run_checked(command, cwd, label, markers=(), timeout=180, engine_log=None, gh=False):
    """Godot can report script errors while exiting 0: inspect the output too."""
    command = [str(part) for part in command]
    if engine_log is not None:
        command[1:1] = ["--log-file", str(engine_log)]
    env = os.environ.copy()
    if not gh:
        env.pop("GH_TOKEN", None)
        env.pop("GITHUB_TOKEN", None)
    print(f"\n--- {label} ---", flush=True)
    result = subprocess.run(command, cwd=cwd, env=env, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, text=True, encoding="utf-8",
                            errors="replace", timeout=timeout, check=False)
    output = result.stdout
    if engine_log is not None and engine_log.exists():
        output += "\n" + engine_log.read_text(encoding="utf-8", errors="replace")
    output = re.sub(r"\x1b\[[0-9;]*m", "", output)
    print(output, flush=True)
    if result.returncode != 0:
        raise RuntimeError(f"{label}: exit code {result.returncode}")
    if ERROR_PATTERN.search(output):
        raise RuntimeError(f"{label}: error reported in output despite exit code 0")
    missing = [marker for marker in markers if marker not in output]
    if missing:
        raise RuntimeError(f"{label}: missing completion markers {missing}")


def one_executable(directory, filename):
    matches = list(directory.rglob(filename))
    if len(matches) != 1:
        raise RuntimeError(f"Expected one {filename}, found {len(matches)}")
    matches[0].chmod(matches[0].stat().st_mode | stat.S_IXUSR)
    return matches[0]


def main():
    system = platform.system()
    if system not in PLATFORMS or platform.machine().lower() not in {"amd64", "x86_64"}:
        raise RuntimeError("This check targets native Windows/Linux x86_64 runners")
    tag = os.environ.get("RELEASE_TAG", "v0.1.0")
    repository = os.environ.get("GITHUB_REPOSITORY", "keeper27069/DustStrike")
    if len(tag) > 128 or not re.fullmatch(r"v\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?", tag):
        raise RuntimeError("RELEASE_TAG must be a version such as v0.1.0")
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
        raise RuntimeError("Invalid GITHUB_REPOSITORY")
    if not shutil.which("gh"):
        raise RuntimeError("GitHub CLI (gh) must be installed")
    suffix, engine_name, release_suffix, game_name = PLATFORMS[system]
    source = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix="duststrike-platform-") as scratch:
        work = Path(scratch)
        project = work / "project"
        # Never reuse a developer's imported assets or editor state.
        shutil.copytree(source, project, ignore=shutil.ignore_patterns(
            ".godot", ".git", "exports", "build", "dist", "work", "__pycache__", "*.app"))
        editor_zip = work / f"Godot_v{VERSION}_{suffix}"
        sha512 = work / "SHA512-SUMS.txt"
        download(OFFICIAL + "SHA512-SUMS.txt", sha512, 1024 * 1024)
        download(OFFICIAL + editor_zip.name, editor_zip)
        verify_checksum(editor_zip, sha512, "sha512")
        safe_extract(editor_zip, work / "editor")
        engine = one_executable(work / "editor", f"Godot_v{VERSION}_{engine_name}")
        run_checked([engine, "--headless", "--editor", "--path", project, "--import"],
                    project, "Clean Godot 4.5.1 import", timeout=300,
                    engine_log=work / "import.log")
        base = [engine, "--headless", "--path", project, "--fixed-fps", "60", "--quit-after", "4000"]
        cases = [
            ("self-test", ["--", "--self-test"], ("SELFTEST PASS:",)),
            ("bot movement and map slopes", ["--script", "res://tests/bot_movement_test.gd", "--", "--map"],
             ("BOT MOVEMENT PASS", "BOT MAP A approach", "BOT MAP mid / B incline")),
            ("death recap", ["--script", "res://tests/death_recap_test.gd"], ("DEATH RECAP PASS:",)),
            ("spectator", ["--script", "res://tests/spectator_test.gd"], ("SPECTATOR TEST PASS:",)),
            ("operators", ["--script", "res://tests/operator_test.gd"], ("OPERATOR TEST PASS:",)),
        ]
        for index, (label, arguments, markers) in enumerate(cases):
            run_checked(base + arguments, project, label, markers,
                        engine_log=work / f"editor-test-{index}.log")
        print("EDITOR REGRESSIONS PASS: assertions enabled in the official editor", flush=True)

        release = work / "release"
        release.mkdir()
        asset_name = f"DustStrike-{tag}-{release_suffix}"
        run_checked(["gh", "release", "download", tag, "--repo", repository, "--dir", release,
                     "--pattern", asset_name, "--pattern", "SHA256SUMS.txt"],
                    work, f"Download release {tag}", timeout=300, gh=True)
        archive = release / asset_name
        verify_checksum(archive, release / "SHA256SUMS.txt", "sha256")
        safe_extract(archive, work / "native-game")
        game = one_executable(work / "native-game", game_name)
        run_checked([game, "--headless", "--fixed-fps", "60", "--quit-after", "4000", "--", "--self-test"],
                    game.parent, "Exported native smoke check", ("SELFTEST PASS:",),
                    engine_log=work / "exported-smoke.log")
        print("EXPORTED SMOKE PASS: release assertions are disabled; this verifies launch, assets and execution", flush=True)
        print(f"PLATFORM CHECK PASS: {system} x86_64, {tag}", flush=True)


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, subprocess.SubprocessError, ValueError,
            zipfile.BadZipFile, tarfile.TarError) as error:
        print(f"PLATFORM CHECK FAILED: {error}", file=sys.stderr, flush=True)
        sys.exit(1)
