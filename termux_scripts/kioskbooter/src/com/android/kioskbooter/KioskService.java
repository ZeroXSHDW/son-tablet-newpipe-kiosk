package com.android.kioskbooter;

import android.app.Service;
import android.app.usage.UsageStats;
import android.app.usage.UsageStatsManager;
import android.content.Context;
import android.content.Intent;
import android.os.IBinder;
import android.util.Log;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.util.List;
import java.util.SortedMap;
import java.util.TreeMap;

public class KioskService extends Service {
    private static final String TAG = "KioskService";
    private boolean running = false;
    private Thread monitorThread;
    private java.net.ServerSocket serverSocket;

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        Log.i(TAG, "KioskService started");
        if (!running) {
            running = true;
            startMonitoring();
            startServer();
        }
        return START_STICKY;
    }

    private void startServer() {
        new Thread(new Runnable() {
            @Override
            public void run() {
                try {
                    // Local IPC only. Exposing the control socket to the LAN
                    // allowed unauthenticated devices to request app stops.
                    serverSocket = new java.net.ServerSocket(
                            30303, 8, java.net.InetAddress.getLoopbackAddress());
                    Log.i(TAG, "ServerSocket listening on loopback:30303");
                    while (running) {
                        java.net.Socket socket = serverSocket.accept();
                        try {
                            socket.setSoTimeout(1000);
                            java.io.BufferedReader reader = new java.io.BufferedReader(new java.io.InputStreamReader(socket.getInputStream()));
                            java.io.OutputStream os = socket.getOutputStream();
                            
                            String line = reader.readLine();
                            if (line != null) {
                                line = line.trim();
                                if (line.startsWith("KILL ")) {
                                    String pkgToKill = line.substring(5).trim();
                                    Log.i(TAG, "Received request to kill background package: " + pkgToKill);
                                    
                                    // Send media pause and stop button events to stop playback service
                                    try {
                                        Intent downIntent = new Intent(Intent.ACTION_MEDIA_BUTTON);
                                        downIntent.setPackage(pkgToKill);
                                        downIntent.putExtra(Intent.EXTRA_KEY_EVENT, new android.view.KeyEvent(android.view.KeyEvent.ACTION_DOWN, android.view.KeyEvent.KEYCODE_MEDIA_PAUSE));
                                        sendOrderedBroadcast(downIntent, null);
                                        
                                        Intent upIntent = new Intent(Intent.ACTION_MEDIA_BUTTON);
                                        upIntent.setPackage(pkgToKill);
                                        upIntent.putExtra(Intent.EXTRA_KEY_EVENT, new android.view.KeyEvent(android.view.KeyEvent.ACTION_UP, android.view.KeyEvent.KEYCODE_MEDIA_PAUSE));
                                        sendOrderedBroadcast(upIntent, null);
                                        
                                        Intent stopDown = new Intent(Intent.ACTION_MEDIA_BUTTON);
                                        stopDown.setPackage(pkgToKill);
                                        stopDown.putExtra(Intent.EXTRA_KEY_EVENT, new android.view.KeyEvent(android.view.KeyEvent.ACTION_DOWN, android.view.KeyEvent.KEYCODE_MEDIA_STOP));
                                        sendOrderedBroadcast(stopDown, null);
                                        
                                        Intent stopUp = new Intent(Intent.ACTION_MEDIA_BUTTON);
                                        stopUp.setPackage(pkgToKill);
                                        stopUp.putExtra(Intent.EXTRA_KEY_EVENT, new android.view.KeyEvent(android.view.KeyEvent.ACTION_UP, android.view.KeyEvent.KEYCODE_MEDIA_STOP));
                                        sendOrderedBroadcast(stopUp, null);
                                    } catch (Exception e) {
                                        Log.e(TAG, "Error sending media keys", e);
                                    }

                                    android.app.ActivityManager am = (android.app.ActivityManager) getSystemService(Context.ACTIVITY_SERVICE);
                                    am.killBackgroundProcesses(pkgToKill);
                                    os.write("OK\n".getBytes());
                                } else {
                                    String app = getForegroundApp((UsageStatsManager) getSystemService(Context.USAGE_STATS_SERVICE));
                                    os.write((app + "\n").getBytes());
                                }
                            } else {
                                String app = getForegroundApp((UsageStatsManager) getSystemService(Context.USAGE_STATS_SERVICE));
                                os.write((app + "\n").getBytes());
                            }
                            os.flush();
                            socket.close();
                        } catch (Exception e) {
                            Log.e(TAG, "Error handling socket client", e);
                        }
                    }
                } catch (IOException e) {
                    Log.e(TAG, "ServerSocket error", e);
                }
            }
        }).start();
    }

    private void startMonitoring() {
        monitorThread = new Thread(new Runnable() {
            @Override
            public void run() {
                UsageStatsManager usm = (UsageStatsManager) getSystemService(Context.USAGE_STATS_SERVICE);
                
                File kioskDir = new File("/sdcard/Kiosk");
                if (!kioskDir.exists()) {
                    kioskDir = new File("/storage/emulated/0/Kiosk");
                }
                if (!kioskDir.exists()) {
                    kioskDir.mkdirs();
                }
                
                File outputFile = new File(kioskDir, "foreground_app.txt");
                Log.i(TAG, "Monitoring started. Writing to: " + outputFile.getAbsolutePath());
                
                while (running) {
                    String foregroundApp = getForegroundApp(usm);
                    writeAppToFile(outputFile, foregroundApp);
                    try {
                        Thread.sleep(1000);
                    } catch (InterruptedException e) {
                        break;
                    }
                }
            }
        });
        monitorThread.start();
    }

    private String getForegroundApp(UsageStatsManager usm) {
        long time = System.currentTimeMillis();
        List<UsageStats> appList = usm.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, time - 1000 * 60, time);
        if (appList != null && !appList.isEmpty()) {
            SortedMap<Long, UsageStats> mySortedMap = new TreeMap<>();
            for (UsageStats usageStats : appList) {
                mySortedMap.put(usageStats.getLastTimeUsed(), usageStats);
            }
            if (!mySortedMap.isEmpty()) {
                return mySortedMap.get(mySortedMap.lastKey()).getPackageName();
            }
        }
        return "unknown";
    }

    private void writeAppToFile(File file, String packageName) {
        FileOutputStream fos = null;
        try {
            fos = new FileOutputStream(file);
            fos.write(packageName.getBytes());
            fos.flush();
            fos.close();
            fos = null;
            
            // Explicitly set the file as world-readable so other apps (like Termux) can read it
            file.setReadable(true, false);
        } catch (IOException e) {
            Log.e(TAG, "Error writing foreground app to file", e);
        } finally {
            if (fos != null) {
                try {
                    fos.close();
                } catch (IOException ignored) {}
            }
        }
    }

    @Override
    public void onDestroy() {
        Log.i(TAG, "KioskService stopped");
        running = false;
        if (monitorThread != null) {
            monitorThread.interrupt();
        }
        if (serverSocket != null) {
            try {
                serverSocket.close();
            } catch (IOException ignored) {}
        }
        super.onDestroy();
    }
}
