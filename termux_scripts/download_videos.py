#!/data/data/com.termux/files/usr/bin/python3
"""NETZ-aware, storage-guarded offline media downloader for the tablet kiosk."""

import json
import os
import re
import shutil
import subprocess
import sys
import time
from datetime import datetime, timedelta

STATE_DIR = "/data/data/com.termux/files/home/Kiosk"
DOWNLOAD_DIR = ""
SCHEDULE_FILE = os.path.join(STATE_DIR, "download_schedule.json")
STATE_FILE = os.path.join(STATE_DIR, "download_state.json")
PLAYLIST_FILE = os.path.join(STATE_DIR, "offline_playlist.json")
ARCHIVE_FILE = os.path.join(STATE_DIR, "downloaded_ids.txt")
TERMUX_HOME = "/data/data/com.termux/files/home"
LOG_DIR = os.path.join(TERMUX_HOME, ".local/share/video_download_logs")
YTDLP = "/data/data/com.termux/files/usr/bin/yt-dlp"
PYTHON = "/data/data/com.termux/files/usr/bin/python3"

DOWNLOAD_CANDIDATES = [
    "/sdcard/Movies/NewPipeOffline",
    "/sdcard/Download/NewPipe",
    "/data/data/com.termux/files/home/Kiosk/offline_videos",
]
os.makedirs(STATE_DIR, exist_ok=True)


def select_download_dir():
    for candidate in DOWNLOAD_CANDIDATES:
        try:
            os.makedirs(candidate, exist_ok=True)
            probe = os.path.join(candidate, ".write_probe")
            with open(probe, "w", encoding="utf-8") as handle:
                handle.write("ok")
            os.unlink(probe)
            return candidate
        except (OSError, PermissionError):
            continue
    raise PermissionError("no writable download directory")


DOWNLOAD_DIR = select_download_dir()
os.makedirs(LOG_DIR, exist_ok=True)
LOG_FILE = os.path.join(LOG_DIR, "download.log")


def log(message):
    line = "[%s] %s" % (datetime.now().isoformat(timespec="seconds"), message)
    print(line, flush=True)
    with open(LOG_FILE, "a", encoding="utf-8") as handle:
        handle.write(line + "\n")


def load_json(path, default):
    try:
        with open(path, encoding="utf-8") as handle:
            return json.load(handle)
    except Exception:
        return default


def save_json(path, value):
    temporary = path + ".tmp"
    with open(temporary, "w", encoding="utf-8") as handle:
        json.dump(value, handle, indent=2, ensure_ascii=False)
        handle.write("\n")
    os.replace(temporary, path)


def connected_ssid():
    probes = [
        ["getprop", "dhcp.wlan0.ssid"],
        ["getprop", "wifi.interface"],
    ]
    for command in probes:
        try:
            value = subprocess.run(command, capture_output=True, text=True, timeout=5).stdout.strip().strip('"')
            if value and value.lower() not in ("null", "wlan0"):
                return value
        except Exception:
            pass
    try:
        output = subprocess.run(["dumpsys", "wifi"], capture_output=True, text=True, timeout=8).stdout
        match = re.search(r'mWifiInfo\s+SSID:\s+"([^"]+)"', output)
        if match:
            return match.group(1)
    except Exception:
        pass
    return ""


def online():
    for address in ("1.1.1.1", "8.8.8.8"):
        try:
            result = subprocess.run(["ping", "-c", "1", "-W", "2", address], timeout=5)
            if result.returncode == 0:
                return True
        except Exception:
            pass
    return False


def network_allowed(schedule):
    networks = [str(item).strip() for item in schedule.get("networks", ["any"])]
    if "any" in [item.lower() for item in networks]:
        return online(), connected_ssid()
    ssid = connected_ssid()
    if ssid and any(item.casefold() == ssid.casefold() for item in networks):
        return online(), ssid
    if not ssid and schedule.get("allow_online_when_ssid_unreadable", False):
        return online(), "SSID_UNREADABLE_ONLINE"
    return False, ssid


def free_bytes():
    stats = os.statvfs(DOWNLOAD_DIR)
    return stats.f_bavail * stats.f_frsize


def sources(schedule):
    configured = schedule.get("sources") or schedule.get("playlists") or []
    return [str(item) for item in configured if str(item).startswith(("http://", "https://"))]


def run_one(url, schedule):
    archive = schedule.get("archive_file", ARCHIVE_FILE)
    quality = str(schedule.get("preferred_quality", "720p")).lower()
    height = "480" if quality in ("360p", "480p") else "720"
    output = os.path.join(DOWNLOAD_DIR, "%(title).180B [%(id)s].%(ext)s")
    command = [
        YTDLP, "--no-playlist", "--continue", "--no-warnings",
        "--download-archive", archive,
        "-f", "bv*[height<=" + height + "]+ba/b[height<=" + height + "]/best",
        "--merge-output-format", "mp4", "--retries", "3",
        "--fragment-retries", "3", "--socket-timeout", "30",
        "-o", output, url,
    ]
    log("Downloading %s" % url)
    result = subprocess.run(command, text=True)
    return result.returncode == 0


def completed_media():
    allowed_words = re.compile(r"ms.?rachel|tractor.?ted|teletubb|wildbrain|edubuzz", re.I)
    result = []
    for root, _, files in os.walk(DOWNLOAD_DIR):
        for name in files:
            if not name.lower().endswith((".mp4", ".mkv", ".webm", ".m4a")):
                continue
            if ".part" in name.lower() or name.lower().endswith(".ytdl") or "frag" in name.lower():
                continue
            if not allowed_words.search(name):
                continue
            path = os.path.join(root, name)
            try:
                result.append({"title": os.path.splitext(name)[0], "file": path, "size_bytes": os.path.getsize(path)})
            except OSError:
                pass
    return sorted(result, key=lambda item: item["title"].casefold())


def write_offline_playlist():
    media = completed_media()
    save_json(PLAYLIST_FILE, {
        "version": "3.0",
        "generated": datetime.now().isoformat(timespec="seconds"),
        "source": "NETZ guarded yt-dlp downloads and retained allowed tablet media",
        "total_videos": len(media),
        "total_size_bytes": sum(item["size_bytes"] for item in media),
        "videos": media,
    })
    return media


def run_download(force=False):
    schedule = load_json(SCHEDULE_FILE, {})
    state = load_json(STATE_FILE, {"downloads": [], "last_error": None})
    ok, ssid = network_allowed(schedule)
    if not ok:
        state["last_error"] = "network unavailable or SSID not allowed: %s" % (ssid or "unknown")
        save_json(STATE_FILE, state)
        log(state["last_error"])
        return 2
    reserve = int(schedule.get("storage_reserve_mb", 2048)) * 1024 * 1024
    log("Network available: %s; free=%d MB; safety reserve=%d MB" % (ssid or "connected", free_bytes() // 1048576, reserve // 1048576))
    downloaded = 0
    for url in sources(schedule):
        if free_bytes() <= reserve:
            log("Stopping before safety floor; free=%d MB" % (free_bytes() // 1048576))
            break
        if run_one(url, schedule):
            downloaded += 1
        else:
            log("Download failed or unavailable: %s" % url)
    media = write_offline_playlist()
    state.update({
        "last_download": datetime.now().isoformat(timespec="seconds"),
        "last_success": datetime.now().isoformat(timespec="seconds"),
        "last_error": None,
        "network": ssid or "connected",
        "download_attempts": downloaded,
        "total_videos": len(media),
        "total_size_bytes": sum(item["size_bytes"] for item in media),
        "free_bytes_after": free_bytes(),
    })
    save_json(STATE_FILE, state)
    log("Offline manifest: %d videos, %.2f GB; free after=%d MB" % (len(media), state["total_size_bytes"] / 1073741824, free_bytes() // 1048576))
    return 0


def status():
    schedule = load_json(SCHEDULE_FILE, {})
    state = load_json(STATE_FILE, {})
    media = load_json(PLAYLIST_FILE, {"videos": []})
    print(json.dumps({
        "ssid": connected_ssid(),
        "online": online(),
        "download_dir": DOWNLOAD_DIR,
        "free_mb": free_bytes() // 1048576,
        "reserve_mb": schedule.get("storage_reserve_mb", 2048),
        "state": state,
        "offline_videos": len(media.get("videos", [])),
    }, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    command = sys.argv[1].lower() if len(sys.argv) > 1 else "status"
    if command == "download":
        raise SystemExit(run_download(force="--force" in sys.argv))
    if command == "status":
        status()
    elif command == "manifest":
        print(json.dumps(write_offline_playlist(), indent=2, ensure_ascii=False))
    else:
        print("Usage: download_videos.py [download [--force] | status | manifest]")
