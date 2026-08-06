#!/usr/bin/env python3
import os
import re
import sys
import shutil
import urllib.request
import subprocess
import glob
import socket

# Set global timeout for all socket connections
socket.setdefaulttimeout(15)


# Configuration
CHANNELS = ["@msrachel", "@SuperSimpleSongs", "@TractorTed", "@SesameStreet"]
TARGET_DIR = "/sdcard/Movies"
MIN_FREE_SPACE_GB = 3.0
TARGET_FREE_SPACE_GB = 4.5

def check_internet():
    try:
        urllib.request.urlopen("https://8.8.8.8", timeout=3)
        return True
    except Exception:
        return False

def get_free_space_gb():
    try:
        stat = shutil.disk_usage("/sdcard")
        return stat.free / (1024**3)
    except Exception:
        # Fallback to df command if shutil.disk_usage fails on Android
        try:
            res = subprocess.run(["df", "-h", "/sdcard"], capture_output=True, text=True)
            for line in res.stdout.split("\n"):
                if "/sdcard" in line or "emulated" in line:
                    parts = line.split()
                    # Find part with free size
                    # Typically: Filesystem Size Used Free Blksize
                    # Just return a reasonable default or parse
                    pass
        except Exception:
            pass
        return 5.0 # default fallback

def scan_file_android(file_path):
    try:
        subprocess.run(["am", "broadcast", "-a", "android.intent.action.MEDIA_SCANNER_SCAN_FILE", "-d", f"file://{file_path}"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception as e:
        print(f"Error scanning file: {e}")

def clean_old_downloads():
    free_gb = get_free_space_gb()
    print(f"Current free space: {free_gb:.2f} GB")
    if free_gb >= MIN_FREE_SPACE_GB:
        return

    print(f"Free space below threshold ({MIN_FREE_SPACE_GB} GB). Cleaning old downloads...")
    if not os.path.exists(TARGET_DIR):
        return
        
    files = glob.glob(os.path.join(TARGET_DIR, "*.mp4"))
    
    # Filter files that match the auto-download pattern: they must have a video ID at the end like [xxxxxxxxx].mp4
    # and they must NOT contain sleep, lullaby, bedtime, or routine in the name (to protect bedtime videos)
    auto_download_pattern = re.compile(r'\[[a-zA-Z0-9_-]{11}\]\.mp4$')
    bedtime_keywords = ["sleep", "lullaby", "bedtime", "routine", "whitenoise"]
    
    candidates = []
    for f in files:
        basename = os.path.basename(f)
        if auto_download_pattern.search(basename):
            is_bedtime = any(kw in basename.lower() for kw in bedtime_keywords)
            if not is_bedtime:
                candidates.append((os.path.getmtime(f), f))
                
    # Sort candidates by modification time (oldest first)
    candidates.sort()
    
    for mtime, f in candidates:
        if get_free_space_gb() >= TARGET_FREE_SPACE_GB:
            break
        print(f"Deleting old video to free space: {os.path.basename(f)}")
        try:
            os.remove(f)
            scan_file_android(f)
        except Exception as e:
            print(f"Error deleting file {f}: {e}")

def scrape_channel_video_ids(handle):
    url = f"https://www.youtube.com/{handle}/videos"
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'})
    try:
        with urllib.request.urlopen(req, timeout=10) as response:
            html = response.read().decode('utf-8')
        video_ids = re.findall(r'\"videoId\":\"([a-zA-Z0-9_-]{11})\"', html)
        unique_ids = list(dict.fromkeys(video_ids))
        return unique_ids
    except Exception as e:
        print(f"Error scraping {handle}: {e}")
        return []

def is_video_downloaded(video_id):
    if not os.path.exists(TARGET_DIR):
        return False
    for f in os.listdir(TARGET_DIR):
        if f.endswith(".mp4") and f"[{video_id}]" in f:
            return True
    return False

def download_video(video_id):
    url = f"https://www.youtube.com/watch?v={video_id}"
    print(f"Downloading {video_id} using yt-dlp...")
    
    cmd = [
        "yt-dlp",
        "--js-runtimes", "node",
        "--remote-components", "ejs:github",
        "--cookies", "/data/data/com.termux/files/home/cookies.txt",
        "--restrict-filenames",
        "-f", "best[height<=720]/best",
        "--merge-output-format", "mp4",
        "-o", f"{TARGET_DIR}/%(title)s [%(id)s].%(ext)s",
        "--max-filesize", "350M",
        "--no-playlist",
        url
    ]
    
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
        if res.returncode == 0:
            print(f"Success downloading {video_id}")
            # Find the downloaded file and scan it
            for f in os.listdir(TARGET_DIR):
                if f.endswith(".mp4") and video_id in f:
                    file_path = os.path.join(TARGET_DIR, f)
                    scan_file_android(file_path)
                    print(f"Scanned {file_path} into MediaStore")
            return True
        else:
            print(f"Failed to download {video_id}: {res.stderr}")
            return False
    except subprocess.TimeoutExpired:
        print(f"Timeout expired (600s) downloading video {video_id}")
        return False
    except Exception as e:
        print(f"Error running yt-dlp: {e}")
        return False

def main():
    print("=== Auto-Downloader over Wi-Fi ===")
    if not check_internet():
        print("No internet connectivity. Exiting.")
        sys.exit(0)
        
    print("Internet connected. Performing storage cleanup if necessary...")
    
    # Generate cookies file dynamically
    try:
        import urllib.request, http.cookiejar
        cookie_path = '/data/data/com.termux/files/home/cookies.txt'
        cj = http.cookiejar.MozillaCookieJar(cookie_path)
        opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))
        req = urllib.request.Request(
            'https://www.youtube.com', 
            headers={'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36'}
        )
        opener.open(req)
        cj.save(ignore_discard=True, ignore_expires=True)
        print("Successfully generated cookies.txt")
    except Exception as e:
        print(f"Warning: Failed to generate cookies.txt: {e}")
        
    clean_old_downloads()
    
    download_count = 0
    for channel in CHANNELS:
        print(f"Checking channel: {channel}")
        video_ids = scrape_channel_video_ids(channel)
        if not video_ids:
            continue
            
        # Get the 3 latest video IDs
        latest_ids = video_ids[:3]
        print(f"Latest videos: {latest_ids}")
        
        for vid in latest_ids:
            if is_video_downloaded(vid):
                print(f"Video {vid} already downloaded.")
                continue
                
            if get_free_space_gb() < MIN_FREE_SPACE_GB:
                clean_old_downloads()
                if get_free_space_gb() < MIN_FREE_SPACE_GB:
                    print("Could not free enough space. Skipping further downloads.")
                    break
                    
            print(f"New video found: {vid}")
            if download_video(vid):
                download_count += 1
                if download_count >= 3:
                    print("Download limit reached for this run. Exiting.")
                    return

    print("Sync finished.")

if __name__ == "__main__":
    main()
