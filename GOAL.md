# Goal: Son’s tablet kiosk (live)

## End state

1. **NewPipe online**, fullscreen immersive; **VLC cached-media fallback offline**
2. **Right subscriptions only**: Ms Rachel, Tractor Ted, Teletubbies/WildBrain, edubuzzkids  
3. **Time-based autoplay**  
   - Day: learning channels (Play All)  
   - Bedtime 20:30–22:30: Edubuzzkids sleep channel autoplay at volume 3/15
   - Night 22:30–06:00: Edubuzzkids sleep channel autoplay at volume 3/15; Ms Rachel fallback
4. **Volume/brightness by phase**, with brightness applied by the child-mode Kiosk Booter overlay
5. **ADHD live wallpaper** cycles soft day/dusk/night art  
6. **Wi‑Fi ADB** after one USB pair  
7. **Kiosk Booter** auto-starts the stack through Termux `RUN_COMMAND`

## Live status (device)

Scripts on tablet via `run-as` + tar deploy. Phases + wallpaper_live v5 deployed.

| Time | Phase | Content | Vol |
|------|-------|---------|-----|
| 06–09 | MORNING | Allowed subscription channels | 12/15 |
| 09–18 | LEARNING | Allowed subscription channels | 12/15 |
| 18–20:30 | RELAXING | Allowed subscription channels | 12/15 |
| 20:30–22:30 | BEDTIME | Edubuzzkids sleep channel | 3/15 |
| 22:30–06 | NIGHT | Edubuzzkids sleep channel; Ms Rachel fallback | 3/15 |

## One-time on tablet

1. Import `/sdcard/Download/newpipe_subscriptions.json` in NewPipe (Previous export)  
2. NewPipe Settings → Player → **Autoplay next stream ON**, Main player  
3. Allow the Kiosk Booter accessibility service if Android asks
4. If home wallpaper doesn’t change automatically: set **Download/wallpaper.jpg** once as wallpaper (night ADHD art is staged there); effective phase brightness is enforced by the Kiosk Booter child overlay
