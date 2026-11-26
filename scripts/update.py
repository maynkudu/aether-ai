#!/usr/bin/env python3
"""User-local aether updater. Only reads the fixed official upstream."""
import configparser
import datetime
import fcntl
import io
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.error
import urllib.request
import zipfile

HOME = Path.home()
CONFIG = Path(os.environ.get("XDG_CONFIG_HOME") or HOME / ".config")
STATE = Path(os.environ.get("XDG_STATE_HOME") or HOME / ".local/state") / "aether"
CACHE = Path(os.environ.get("XDG_CACHE_HOME") or HOME / ".cache") / "aether"
SHELL = CONFIG / "quickshell/aether"
BIN = HOME / ".local/bin"
UNITS = CONFIG / "systemd/user"
RECEIPT = STATE / "installed-commit"
STATUS = STATE / "update-status.json"
ROLLBACK = STATE / "previous-build.zip"
BLOCKED = STATE / "blocked-commit"
MIRROR = CACHE / "update-repo.git"
UPSTREAM = "https://github.com/maynkudu/aether-ai.git"
RELEASE = "https://api.github.com/repos/maynkudu/aether-ai/releases/latest"
SHA = re.compile(r"[0-9a-f]{40}")
TAG = re.compile(r"v[0-9]+\.[0-9]+\.[0-9]+")
os.environ["PATH"] = str(HOME / ".cargo/bin") + os.pathsep + str(BIN) + os.pathsep + os.environ.get("PATH", "")

def atomic(path, data, mode=0o600):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix=".aether-update-", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(name, mode)
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)

def installed():
    try:
        value = RECEIPT.read_text().strip()
        return value if SHA.fullmatch(value) else ""
    except OSError:
        return ""

def targets():
    return [BIN/"aether", BIN/"aether-update", UNITS/"aether.service",
            UNITS/"aether-update.service", UNITS/"aether-update.timer", SHELL/"shell.qml",
            UNITS/"aether-ui.service"]

def rollback_available():
    try:
        with zipfile.ZipFile(ROLLBACK) as archive:
            meta = json.loads(archive.read("manifest.json"))
        return (meta.get("to") == installed() and bool(SHA.fullmatch(meta.get("from","")))
                and len(meta.get("files",[])) in {len(targets())-1,len(targets())})
    except (OSError,ValueError,KeyError,zipfile.BadZipFile):
        return False

def busy():
    with (STATE/"update.lock").open("a") as lock:
        try:
            fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
            return False
        except BlockingIOError:
            return True

def emit(message, channel, candidate="", checked=True, **extra):
    result = {"message":message, "channel":channel, "installed":installed(),
              "candidate":candidate, "rollbackAvailable":rollback_available(), **extra}
    if checked:
        result["checked"] = datetime.datetime.now().astimezone().isoformat(timespec="minutes")
        atomic(STATUS, (json.dumps(result)+"\n").encode())
    print(json.dumps(result))
    return result

def preferences():
    p = configparser.ConfigParser(interpolation=None)
    p.read(SHELL / "preferences.ini", encoding="utf-8")
    section = p["AetherUI"] if "AetherUI" in p else {}
    enabled = str(section.get("autoUpdate","false")).lower() == "true"
    channel = section.get("updateChannel","stable")
    return enabled, channel if channel in {"stable","development"} else "stable"

def run(args, **kwargs):
    return subprocess.run(args, check=True, timeout=kwargs.pop("timeout",120), **kwargs)

def git(*args, **kwargs):
    return run(["git","--git-dir",str(MIRROR),*args], **kwargs)

def resolve(ref):
    value = git("rev-parse","--verify",ref+"^{commit}",capture_output=True,text=True).stdout.strip()
    if not SHA.fullmatch(value):
        raise ValueError("invalid commit ID")
    return value

def ancestor(old, new):
    result = subprocess.run(["git","--git-dir",str(MIRROR),"merge-base","--is-ancestor",old,new],
                            stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=30)
    if result.returncode not in (0,1):
        raise RuntimeError("cannot verify commit ancestry")
    return result.returncode == 0

def candidate(channel):
    tag = None
    if channel == "stable":
        req = urllib.request.Request(RELEASE, headers={"Accept":"application/vnd.github+json","User-Agent":"aether-ai-updater"})
        try:
            with urllib.request.urlopen(req, timeout=20) as response:
                data = json.load(io.BytesIO(response.read(1024*1024)))
        except urllib.error.HTTPError as exc:
            if exc.code == 404:
                return None
            raise
        tag = data.get("tag_name","")
        if data.get("draft") or data.get("prerelease") or not TAG.fullmatch(tag):
            raise ValueError("release must use a stable vMAJOR.MINOR.PATCH tag")
    CACHE.mkdir(parents=True,exist_ok=True)
    if not MIRROR.exists():
        run(["git","init","--bare",str(MIRROR)],stdout=sys.stderr)
    # Never operate on the user's project directory or follow another remote.
    git("fetch","--no-tags",UPSTREAM,"refs/heads/main:refs/remotes/aether/main",stdout=sys.stderr)
    head = resolve("refs/remotes/aether/main")
    if tag:
        git("fetch","--no-tags",UPSTREAM,"refs/tags/"+tag+":refs/tags/"+tag,stdout=sys.stderr)
        target = resolve("refs/tags/"+tag)
        if not ancestor(target,head):
            raise RuntimeError("release is not in official main history")
        return target
    return head

def snapshot():
    return [(dst,dst.read_bytes() if dst.exists() else None,
             dst.stat().st_mode & 0o777 if dst.exists() else 0o644) for dst in targets()]

def restore(backup):
    for dst,data,mode in reversed(backup):
        if data is None:
            dst.unlink(missing_ok=True)
        else:
            atomic(dst,data,mode)

def restart():
    run(["systemctl","--user","daemon-reload"],stdout=sys.stderr)
    run(["systemctl","--user","restart","aether.service"],stdout=sys.stderr)
    run(["systemctl","--user","is-active","--quiet","aether.service"])
    if (UNITS/"aether-ui.service").exists():
        run(["systemctl","--user","try-restart","aether-ui.service"],stdout=sys.stderr)

def save_previous(backup,current,target):
    buf=io.BytesIO()
    with zipfile.ZipFile(buf,"w",compression=zipfile.ZIP_DEFLATED) as archive:
        entries=[]
        for i,(_,data,mode) in enumerate(backup):
            entries.append({"exists":data is not None,"mode":mode})
            if data is not None:
                archive.writestr(str(i),data)
        archive.writestr("manifest.json",json.dumps({"from":current,"to":target,"files":entries}))
    atomic(ROLLBACK,buf.getvalue())

def rollback(current):
    with zipfile.ZipFile(ROLLBACK) as archive:
        meta=json.loads(archive.read("manifest.json"))
        previous=meta.get("from","")
        entries=meta.get("files",[])
        if meta.get("to")!=current or not SHA.fullmatch(previous) or len(entries) not in {len(targets())-1,len(targets())}:
            raise RuntimeError("previous build does not match installed commit")
        old=[(dst,archive.read(str(i)) if entries[i]["exists"] else None,
              int(entries[i]["mode"]) & 0o777) for i,dst in enumerate(targets()[:len(entries)])]
    current_files=snapshot()
    # Older rollback archives predate the UI unit; preserve its current setup.
    old.extend(current_files[len(entries):])
    try:
        restore(old)
        restart()
        atomic(RECEIPT,(previous+"\n").encode())
        atomic(BLOCKED,(current+"\n").encode())
    except Exception:
        restore(current_files)
        atomic(RECEIPT,(current+"\n").encode())
        restart()
        raise

def apply(target, current):
    # Build from an isolated exact source commit, not from an edited checkout.
    with tempfile.TemporaryDirectory(prefix="aether-build-",dir=CACHE) as tmp:
        source = Path(tmp)
        archive = source / "source.tar"
        with archive.open("wb") as stream:
            git("archive","--format=tar",target,stdout=stream)
        with tarfile.open(archive) as tar:
            tar.extractall(source,filter="data")
        archive.unlink()
        cmd = ["cargo","build","--release"]
        if (source / "Cargo.lock").exists():
            cmd.append("--locked")
        run(cmd,cwd=source,stdout=sys.stderr,timeout=1200)
        files = [
            (source/"target/release/aether",BIN/"aether",0o755),
            (source/"scripts/update.py",BIN/"aether-update",0o755),
            (source/"systemd/aether.service",UNITS/"aether.service",0o644),
            (source/"systemd/aether-update.service",UNITS/"aether-update.service",0o644),
            (source/"systemd/aether-update.timer",UNITS/"aether-update.timer",0o644),
            (source/"systemd/aether-ui.service",UNITS/"aether-ui.service",0o644),
            (source/"shell/shell.qml",SHELL/"shell.qml",0o644),
        ]
        payload = [(dst,src.read_bytes(),mode) for src,dst,mode in files]
        if not payload[0][1] or b"ShellRoot" not in payload[-1][1]:
            raise RuntimeError("incomplete build")
        backup = snapshot()
        save_previous(backup,current,target)
        try:
            for dst,data,mode in payload:
                atomic(dst,data,mode)
            restart()
            atomic(RECEIPT,(target+"\n").encode())
            BLOCKED.unlink(missing_ok=True)
        except Exception:
            restore(backup)
            atomic(RECEIPT,(current+"\n").encode())
            restart()
            raise

def main():
    STATE.mkdir(parents=True,exist_ok=True,mode=0o700)
    action = sys.argv[1] if len(sys.argv)>1 else "status"
    if action not in {"status","check","apply","auto","rollback"}:
        raise ValueError("usage: aether-update status|check|apply|auto|rollback [stable|development]")
    enabled, preferred = preferences()
    channel = sys.argv[2] if len(sys.argv)>2 else preferred
    if channel not in {"stable","development"}:
        raise ValueError("invalid update channel")
    if action == "status":
        try:
            data=json.loads(STATUS.read_text())
            if data.get("channel") != channel:
                raise ValueError("different channel")
            data["installed"]=installed()
            data["rollbackAvailable"]=rollback_available()
            data["busy"]=busy()
            if not data["busy"] and data.get("message","").startswith("Building update"):
                data["message"]="Previous update ended; check again for its result"
            print(json.dumps(data))
        except (OSError,ValueError):
            emit("No update check yet",channel,checked=False,busy=busy())
        return
    if action == "auto" and not enabled:
        print(json.dumps({"message":"Automatic updates disabled","installed":installed(),"channel":channel}))
        return
    # Shared with manual installer to avoid two simultaneous replacements.
    with (STATE/"update.lock").open("a") as lock:
        try:
            fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        except BlockingIOError:
            emit("Another installation or update is running",channel,checked=False)
            return
        current=installed()
        if not current:
            emit("Run a full install from a clean Git checkout once to initialise the updater",channel)
            return
        if action == "rollback":
            if not rollback_available():
                emit("No previous build is available",channel)
                return
            rollback(current)
            emit("Previous build restored. Automatic installation of the rolled-back commit is paused.",channel)
            return
        target=candidate(channel)
        if target is None:
            emit("No stable GitHub release has been published yet",channel)
            return
        if target == current:
            emit("You're up to date",channel,target)
            return
        if ancestor(target,current):
            emit("Installed commit is newer than this channel; no downgrade",channel,target)
            return
        if not ancestor(current,target):
            emit("Update refused: divergent commit history",channel,target)
            return
        if action == "check":
            emit("Update available",channel,target,available=True)
            return
        if action == "auto" and BLOCKED.exists() and BLOCKED.read_text().strip()==target:
            emit("This commit was rolled back; automatic reinstall is paused",channel,target)
            return
        emit("Building update from isolated source…",channel,target,busy=True)
        emit_install = "Update installed."
        apply(target,current)
        emit(emit_install,channel,target,available=False)

if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        try:
            channel = sys.argv[2] if len(sys.argv)>2 and sys.argv[2] in {"stable","development"} else preferences()[1]
            emit("Update failed: "+str(exc),channel)
        except Exception:
            print(json.dumps({"message":"Update failed: "+str(exc)}))
        sys.exit(1)
