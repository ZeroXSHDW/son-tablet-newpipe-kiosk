import http.server
import socketserver
import json
import os
import subprocess

PORT = 8080
HOME = "/data/data/com.termux/files/home"

class ParentDashboardHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/':
            self.path = '/dashboard.html'
            
        if self.path == '/api/health':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            try:
                # Run the health check explicitly first
                subprocess.run(["bash", os.path.join(HOME, "health_dashboard.sh"), "report"], capture_output=True)
                with open(os.path.join(HOME, 'health_report.txt'), 'r') as f:
                    report = f.read()
                self.wfile.write(json.dumps({'status': 'ok', 'report': report}).encode())
            except Exception as e:
                self.wfile.write(json.dumps({'status': 'error', 'message': str(e)}).encode())
            return
            
        elif self.path == '/api/status':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            
            # Get battery status
            batt_level = 0
            batt_charging = "Discharging"
            try:
                batt_out = subprocess.check_output("dumpsys battery", shell=True).decode()
                for line in batt_out.splitlines():
                    if "level:" in line:
                        try: batt_level = int(line.split(":")[1].strip())
                        except: pass
                    if "USB powered: true" in line or "AC powered: true" in line:
                        batt_charging = "Charging"
            except: pass
            
            # Get parent mode
            parent_mode = "false"
            if os.path.exists(os.path.join(HOME, 'Kiosk/parent_mode.txt')):
                with open(os.path.join(HOME, 'Kiosk/parent_mode.txt'), 'r') as f:
                    parent_mode = f.read().strip()
            elif os.path.exists("/sdcard/Kiosk/parent_mode.txt"):
                with open("/sdcard/Kiosk/parent_mode.txt", 'r') as f:
                    parent_mode = f.read().strip()
            
            # Get lock status
            lock_status = "UNLOCKED"
            try:
                chrome_res = subprocess.check_output("pm list packages -d com.android.chrome", shell=True).decode()
                if "com.android.chrome" in chrome_res:
                    lock_status = "LOCKED"
            except: pass
            
            # Get Wifi status
            wifi_status = "Offline"
            try:
                ip_res = subprocess.check_output("ip addr show wlan0", shell=True).decode()
                for line in ip_res.splitlines():
                    if "inet " in line:
                        parts = line.strip().split()
                        if len(parts) >= 2:
                            wifi_status = f"Connected (IP: {parts[1].split('/')[0]})"
            except: pass
            
            # Get Volume music level
            volume_level = "Unknown"
            try:
                volume_level = subprocess.check_output("settings get system volume_music", shell=True).decode().strip()
            except: pass
            
            # Get screen power state (wakefulness)
            screen_power = "unknown"
            try:
                wake_res = subprocess.check_output("dumpsys power", shell=True).decode()
                for line in wake_res.splitlines():
                    if "mWakefulness=" in line:
                        screen_power = line.split("=")[1].strip()
            except: pass
            
            # Get active stage URL and display name
            active_stage = "Unknown"
            try:
                stage_url = ""
                if os.path.exists("/sdcard/Kiosk/active_stage_url.txt"):
                    with open("/sdcard/Kiosk/active_stage_url.txt", "r") as f:
                        stage_url = f.read().strip()
                if "8KtnrtHRiCg" in stage_url:
                    active_stage = "Stage 1: First Words (Ms Rachel)"
                elif "2dDpryw3z5w" in stage_url:
                    active_stage = "Stage 2: Vocabulary (Ms Rachel)"
                elif "1v3Dk41C_10" in stage_url:
                    active_stage = "Stage 3: Phonics & Reading (Ms Rachel)"
                elif stage_url:
                    active_stage = f"Custom Stage ({stage_url})"
            except: pass

            # Get DNS status
            dns_status = "Bypassed"
            try:
                dns_mode = subprocess.check_output("settings get global private_dns_mode", shell=True).decode().strip()
                dns_spec = subprocess.check_output("settings get global private_dns_specifier", shell=True).decode().strip()
                if dns_mode == "hostname" and dns_spec == "family.adguard-dns.com":
                    dns_status = "Active"
            except: pass
            
            # Get storage details
            storage_free = "Unknown"
            storage_used = "Unknown"
            storage_size = "Unknown"
            storage_percent = "Unknown"
            try:
                storage_res = subprocess.check_output("df -h /sdcard", shell=True).decode()
                storage_lines = storage_res.splitlines()
                if len(storage_lines) >= 2:
                    parts = storage_lines[1].split()
                    if len(parts) >= 5:
                        storage_size = parts[1]
                        storage_used = parts[2]
                        storage_free = parts[3]
                        storage_percent = parts[4]
            except: pass
            
            self.wfile.write(json.dumps({
                "connected": True,
                "lock_status": lock_status,
                "battery_level": batt_level,
                "charging_status": batt_charging,
                "wifi_status": wifi_status,
                "volume_level": volume_level,
                "screen_power": screen_power,
                "active_stage": active_stage,
                "parent_mode": parent_mode,
                "dns_status": dns_status,
                "storage_free": storage_free,
                "storage_used": storage_used,
                "storage_size": storage_size,
                "storage_percent": storage_percent
            }).encode())
            return
            
        return super().do_GET()

    def do_POST(self):
        if self.path == '/api/pause_kiosk':
            self._write_parent_mode('true')
            self._send_ok()
        
        elif self.path == '/api/resume_kiosk':
            self._write_parent_mode('false')
            self._send_ok()
                
        elif self.path == '/api/restart_content':
            try:
                # Trigger watchdog immediately to restart content
                subprocess.Popen("am force-stop org.schabi.newpipe", shell=True)
                subprocess.Popen("am force-stop com.brouken.player", shell=True)
                self._send_ok()
            except:
                self.send_response(500)
                self.end_headers()
        else:
            self.send_response(404)
            self.end_headers()

    def _write_parent_mode(self, val):
        try:
            os.makedirs(os.path.join(HOME, 'Kiosk'), exist_ok=True)
            with open(os.path.join(HOME, 'Kiosk/parent_mode.txt'), 'w') as f:
                f.write(val)
            # Also try sdcard
            try:
                with open('/sdcard/Kiosk/parent_mode.txt', 'w') as f:
                    f.write(val)
            except: pass
        except Exception as e:
            print(f"Error writing parent mode: {e}")

    def _send_ok(self):
        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.end_headers()
        self.wfile.write(b'{"status": "ok"}')

os.chdir(HOME)
socketserver.TCPServer.allow_reuse_address = True
with socketserver.TCPServer(("", PORT), ParentDashboardHandler) as httpd:
    print("Parent Dashboard serving at port", PORT)
    httpd.serve_forever()
