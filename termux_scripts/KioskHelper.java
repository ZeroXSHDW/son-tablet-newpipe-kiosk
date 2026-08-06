import java.lang.reflect.Method;

public class KioskHelper {
    public static void main(String[] args) {
        if (args.length < 1) {
            printUsageAndExit();
        }

        String command = args[0];
        try {
            // Prepare Looper if not present
            Class<?> looperCls = Class.forName("android.os.Looper");
            if (looperCls.getMethod("myLooper").invoke(null) == null) {
                looperCls.getMethod("prepare").invoke(null);
            }
            
            Class<?> atClass = Class.forName("android.app.ActivityThread");
            Object at = atClass.getMethod("systemMain").invoke(null);
            Object context = atClass.getMethod("getSystemContext").invoke(at);

            // Dynamically resolve the package context based on current UID to avoid SecurityExceptions
            try {
                Class<?> processCls = Class.forName("android.os.Process");
                int myUid = (Integer) processCls.getMethod("myUid").invoke(null);
                
                Method getPackageManager = context.getClass().getMethod("getPackageManager");
                Object pm = getPackageManager.invoke(context);
                
                Method getPackagesForUid = pm.getClass().getMethod("getPackagesForUid", int.class);
                String[] packages = (String[]) getPackagesForUid.invoke(pm, myUid);
                
                if (packages != null && packages.length > 0) {
                    String pkgName = packages[0];
                    Method createPackageContext = context.getClass().getMethod("createPackageContext", String.class, int.class);
                    context = createPackageContext.invoke(context, pkgName, 0);
                    
                    try {
                        java.lang.reflect.Field opPkgField = context.getClass().getDeclaredField("mOpPackageName");
                        opPkgField.setAccessible(true);
                        opPkgField.set(context, pkgName);
                    } catch (Exception e) {}
                    
                    try {
                        java.lang.reflect.Field pkgField = context.getClass().getDeclaredField("mPackageName");
                        pkgField.setAccessible(true);
                        pkgField.set(context, pkgName);
                    } catch (Exception e) {}

                    try {
                        Class<?> builderClass = Class.forName("android.content.AttributionSource$Builder");
                        Object builder = builderClass.getConstructor(int.class).newInstance(myUid);
                        builderClass.getMethod("setPackageName", String.class).invoke(builder, pkgName);
                        Object attrSource = builderClass.getMethod("build").invoke(builder);
                        
                        java.lang.reflect.Field attrSourceField = context.getClass().getDeclaredField("mAttributionSource");
                        attrSourceField.setAccessible(true);
                        attrSourceField.set(context, attrSource);
                    } catch (Exception e) {}
                }
            } catch (Exception e) {
                System.err.println("Warning: Failed to resolve package context: " + e.getMessage());
            }

            if ("get-foreground".equals(command)) {
                // 1. Query the KioskService TCP socket on port 30303
                try {
                    java.net.Socket socket = new java.net.Socket("127.0.0.1", 30303);
                    socket.setSoTimeout(1000);
                    java.io.PrintWriter out = new java.io.PrintWriter(socket.getOutputStream(), true);
                    java.io.BufferedReader in = new java.io.BufferedReader(new java.io.InputStreamReader(socket.getInputStream()));
                    out.println("GET");
                    String app = in.readLine();
                    socket.close();
                    if (app != null && !app.trim().isEmpty()) {
                        System.out.println(app.trim());
                        System.exit(0);
                    }
                } catch (Exception e) {
                    System.err.println("Socket connection failed: " + e.toString());
                    e.printStackTrace();
                    // Fallback to file and package manager
                }

                // 2. Read from com.android.kioskbooter shared file next
                try {
                    java.io.File file = new java.io.File("/data/local/tmp/foreground_app.txt");
                    if (file.exists() && file.length() > 0) {
                        java.io.BufferedReader br = new java.io.BufferedReader(new java.io.FileReader(file));
                        String app = br.readLine();
                        br.close();
                        if (app != null && !app.trim().isEmpty()) {
                            System.out.println(app.trim());
                            System.exit(0);
                        }
                    }
                } catch (Exception e) {
                    System.err.println("File read failed: " + e.toString());
                    e.printStackTrace();
                    // Fallback to local query if file read fails
                }

                Method getSystemService = context.getClass().getMethod("getSystemService", String.class);
                Object usm = getSystemService.invoke(context, "usagestats");
                
                long time = System.currentTimeMillis();
                Method queryUsageStats = usm.getClass().getMethod("queryUsageStats", int.class, long.class, long.class);
                // UsageStatsManager.INTERVAL_DAILY = 4
                java.util.List<?> appList = (java.util.List<?>) queryUsageStats.invoke(usm, 4, time - 1000 * 60, time);
                
                String foregroundApp = "unknown";
                if (appList != null && !appList.isEmpty()) {
                    java.util.SortedMap<Long, Object> mySortedMap = new java.util.TreeMap<>();
                    for (Object usageStats : appList) {
                        long lastTimeUsed = (Long) usageStats.getClass().getMethod("getLastTimeUsed").invoke(usageStats);
                        mySortedMap.put(lastTimeUsed, usageStats);
                    }
                    if (!mySortedMap.isEmpty()) {
                        Object latestStats = mySortedMap.get(mySortedMap.lastKey());
                        foregroundApp = (String) latestStats.getClass().getMethod("getPackageName").invoke(latestStats);
                    }
                }
                System.out.println(foregroundApp);
                System.exit(0);

            } else if ("kill-background".equals(command)) {
                if (args.length < 2) {
                    System.err.println("Usage: kill-background <package>");
                    System.exit(1);
                }
                String targetPkg = args[1];
                try {
                    java.net.Socket socket = new java.net.Socket("127.0.0.1", 30303);
                    socket.setSoTimeout(1000);
                    java.io.PrintWriter out = new java.io.PrintWriter(socket.getOutputStream(), true);
                    java.io.BufferedReader in = new java.io.BufferedReader(new java.io.InputStreamReader(socket.getInputStream()));
                    out.println("KILL " + targetPkg);
                    String resp = in.readLine();
                    socket.close();
                    if ("OK".equals(resp)) {
                        System.out.println("SUCCESS");
                        System.exit(0);
                    }
                } catch (Exception e) {
                    System.err.println("Socket kill failed: " + e.toString());
                }
                System.exit(1);

            } else if ("write-setting".equals(command)) {
                if (args.length < 4) {
                    System.err.println("Usage: write-setting <table: secure|system|global> <key> <value>");
                    System.exit(1);
                }
                String table = args[1];
                String key = args[2];
                String value = args[3];
                
                Method getContentResolver = context.getClass().getMethod("getContentResolver");
                Object resolver = getContentResolver.invoke(context);
                
                Class<?> resolverClass = Class.forName("android.content.ContentResolver");
                Class<?> settingsClass = null;
                if ("secure".equalsIgnoreCase(table)) {
                    settingsClass = Class.forName("android.provider.Settings$Secure");
                } else if ("system".equalsIgnoreCase(table)) {
                    settingsClass = Class.forName("android.provider.Settings$System");
                } else if ("global".equalsIgnoreCase(table)) {
                    settingsClass = Class.forName("android.provider.Settings$Global");
                } else {
                    System.err.println("Invalid table: " + table);
                    System.exit(1);
                }
                
                Method putString = settingsClass.getMethod("putString", resolverClass, String.class, String.class);
                Boolean success = (Boolean) putString.invoke(null, resolver, key, value);
                System.out.println(success ? "SUCCESS" : "FAILED");
                System.exit(success ? 0 : 1);

            } else if ("read-setting".equals(command)) {
                if (args.length < 3) {
                    System.err.println("Usage: read-setting <table: secure|system|global> <key>");
                    System.exit(1);
                }
                String table = args[1];
                String key = args[2];
                
                Method getContentResolver = context.getClass().getMethod("getContentResolver");
                Object resolver = getContentResolver.invoke(context);
                
                Class<?> resolverClass = Class.forName("android.content.ContentResolver");
                Class<?> settingsClass = null;
                if ("secure".equalsIgnoreCase(table)) {
                    settingsClass = Class.forName("android.provider.Settings$Secure");
                } else if ("system".equalsIgnoreCase(table)) {
                    settingsClass = Class.forName("android.provider.Settings$System");
                } else if ("global".equalsIgnoreCase(table)) {
                    settingsClass = Class.forName("android.provider.Settings$Global");
                } else {
                    System.err.println("Invalid table: " + table);
                    System.exit(1);
                }
                
                Method getString = settingsClass.getMethod("getString", resolverClass, String.class);
                String val = (String) getString.invoke(null, resolver, key);
                System.out.println(val != null ? val : "");
                System.exit(0);

            } else if ("set-volume".equals(command)) {
                if (args.length < 3) {
                    System.err.println("Usage: set-volume <ring|music|system|voice> <level>");
                    System.exit(1);
                }
                String streamName = args[1];
                int level = Integer.parseInt(args[2]);
                
                Method getSystemService = context.getClass().getMethod("getSystemService", String.class);
                Object am = getSystemService.invoke(context, "audio");
                
                int stream = 3; // AudioManager.STREAM_MUSIC
                if ("ring".equalsIgnoreCase(streamName)) {
                    stream = 2; // AudioManager.STREAM_RING
                } else if ("system".equalsIgnoreCase(streamName)) {
                    stream = 1; // AudioManager.STREAM_SYSTEM
                } else if ("voice".equalsIgnoreCase(streamName)) {
                    stream = 0; // AudioManager.STREAM_VOICE_CALL
                }
                
                Method setStreamVolume = am.getClass().getMethod("setStreamVolume", int.class, int.class, int.class);
                setStreamVolume.invoke(am, stream, level, 0);
                System.out.println("SUCCESS");
                System.exit(0);

            } else if ("is-screen-on".equals(command)) {
                Method getSystemService = context.getClass().getMethod("getSystemService", String.class);
                Object pm = getSystemService.invoke(context, "power");
                
                Method isInteractive = pm.getClass().getMethod("isInteractive");
                Boolean interactive = (Boolean) isInteractive.invoke(pm);
                System.out.println(interactive ? "true" : "false");
                System.exit(0);

            } else if ("is-music-active".equals(command)) {
                Method getSystemService = context.getClass().getMethod("getSystemService", String.class);
                Object am = getSystemService.invoke(context, "audio");
                
                Method isMusicActive = am.getClass().getMethod("isMusicActive");
                Boolean active = (Boolean) isMusicActive.invoke(am);
                System.out.println(active ? "true" : "false");
                System.exit(0);

            } else if ("get-wifi-rssi".equals(command)) {
                 Method getSystemService = context.getClass().getMethod("getSystemService", String.class);
                 Object wm = getSystemService.invoke(context, "wifi");
                 Object info = wm.getClass().getMethod("getConnectionInfo").invoke(wm);
                 int rssi = (Integer) info.getClass().getMethod("getRssi").invoke(info);
                 System.out.println(rssi);
                 System.exit(0);

            } else if ("get-battery".equals(command)) {
                Method getSystemService = context.getClass().getMethod("getSystemService", String.class);
                Object bm = getSystemService.invoke(context, "batterymanager");
                Method getIntProperty = bm.getClass().getMethod("getIntProperty", int.class);
                int level = (Integer) getIntProperty.invoke(bm, 4); // 4 = BATTERY_PROPERTY_CAPACITY
                System.out.println(level);
                System.exit(0);

            } else if ("am-start".equals(command)) {
                String action = null;
                String data = null;
                String type = null;
                String component = null;
                java.util.List<String[]> extras = new java.util.ArrayList<String[]>();
                
                for (int i = 1; i < args.length; i++) {
                    if ("-a".equals(args[i]) && i + 1 < args.length) {
                        action = args[i + 1];
                        i++;
                    } else if ("-d".equals(args[i]) && i + 1 < args.length) {
                        data = args[i + 1];
                        i++;
                    } else if ("-n".equals(args[i]) && i + 1 < args.length) {
                        component = args[i + 1];
                        i++;
                    } else if ("-t".equals(args[i]) && i + 1 < args.length) {
                        type = args[i + 1];
                        i++;
                    } else if ("-e".equals(args[i]) && i + 2 < args.length) {
                        extras.add(new String[]{args[i + 1], args[i + 2]});
                        i += 2;
                    }
                }
                
                Class<?> intentClass = Class.forName("android.content.Intent");
                Object broadcastIntent = intentClass.getConstructor(String.class).newInstance("com.android.kioskbooter.START_ACTIVITY");
                
                // Explicitly target com.android.kioskbooter BootReceiver
                Method setClassName = intentClass.getMethod("setClassName", String.class, String.class);
                setClassName.invoke(broadcastIntent, "com.android.kioskbooter", "com.android.kioskbooter.BootReceiver");
                
                Method putExtra = intentClass.getMethod("putExtra", String.class, String.class);
                if (action != null) {
                    putExtra.invoke(broadcastIntent, "action", action);
                }
                if (data != null) {
                    putExtra.invoke(broadcastIntent, "data", data);
                }
                if (type != null) {
                    putExtra.invoke(broadcastIntent, "type", type);
                }
                if (component != null) {
                    putExtra.invoke(broadcastIntent, "component", component);
                }
                
                for (String[] extra : extras) {
                    putExtra.invoke(broadcastIntent, extra[0], extra[1]);
                }
                
                Method sendBroadcast = context.getClass().getMethod("sendBroadcast", intentClass);
                sendBroadcast.invoke(context, broadcastIntent);
                System.out.println("SUCCESS");
                System.exit(0);

            } else {
                System.err.println("Unknown command: " + command);
                printUsageAndExit();
            }

        } catch (Exception e) {
            System.err.println("ERROR: " + e.getClass().getName() + ": " + e.getMessage());
            e.printStackTrace();
            System.exit(1);
        }
    }

    private static void printUsageAndExit() {
        System.out.println("Usage: KioskHelper <command> [args]");
        System.out.println("Commands:");
        System.out.println("  get-foreground");
        System.out.println("  kill-background <package>");
        System.out.println("  write-setting <secure|system|global> <key> <value>");
        System.out.println("  read-setting <secure|system|global> <key>");
        System.out.println("  set-volume <ring|music|system|voice> <level>");
        System.out.println("  is-screen-on");
        System.out.println("  is-music-active");
        System.out.println("  get-wifi-rssi");
        System.out.println("  get-battery");
        System.out.println("  am-start -a <action> -d <data> -n <component> -t <type> [-e <key> <val>]...");
        System.exit(1);
    }
}
