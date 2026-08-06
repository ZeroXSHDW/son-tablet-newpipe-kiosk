# NewPipe: Right subscriptions + fullscreen autoplay

## Allowed channels only

| Channel | URL |
|---------|-----|
| **Ms Rachel** | https://www.youtube.com/@msrachel |
| **Tractor Ted** | https://www.youtube.com/@TractorTed |
| **Teletubbies** | https://www.youtube.com/@Teletubbies |
| **Teletubbies Compilations – WildBrain** | https://www.youtube.com/channel/UCrbHp6Xh0oEOhOozMk9t_wQ |
| **edubuzzkids** | https://www.youtube.com/@edubuzzkids |

Import file (already on tablet):

`/sdcard/Download/newpipe_subscriptions.json`

## One-time: import subscriptions into NewPipe

1. Open **NewPipe**
2. Bottom / side: open **Subscriptions** (or Bookmarked / What’s New area)
3. Open **⋮ menu** on the subscriptions screen  
4. **Import from** → **Previous export**  
5. Pick **`newpipe_subscriptions.json`** from **Download**  
6. Confirm import  

Optional cleanup: remove any other channels so only the list above remains.

## One-time: autoplay + fullscreen settings

In **NewPipe → Settings → Player** (wording may vary slightly by version):

- Preferred player type: **Main** (not popup / background only)
- **Autoplay next stream** / auto-queue: **ON**
- Start in fullscreen if available: **ON**
- Resume on start: optional

This setting supports daytime queued playback and the supervised sleep channel.
The kiosk controller targets Edubuzzkids during BEDTIME/NIGHT and uses the
curated Ms Rachel bedtime video if the channel feed fails.

## How autoplay works now (v4)

Termux `newpipe_24x7.sh` does **not** open random YouTube:

1. Picks a **subscribed channel** from `channels.json`
2. Opens that channel’s **Videos** tab in NewPipe  
3. Taps **Play All** (queues the channel continuously)  
4. Forces **immersive fullscreen**  
5. When playback dies, rotates to the next allowed channel  

Fallback: curated videos in `online_playlist.json` (same channels only).

## Restart / test

```powershell
.\platform-tools\adb.exe -s <tablet-serial> shell "am force-stop com.termux; am force-stop org.schabi.newpipe"
.\platform-tools\adb.exe -s <tablet-serial> shell "am start -n com.termux/.app.TermuxActivity"
.\platform-tools\adb.exe -s <tablet-serial> shell "run-as com.termux /data/data/com.termux/files/usr/bin/bash /data/data/com.termux/files/home/restart_termux_test.sh"
```
