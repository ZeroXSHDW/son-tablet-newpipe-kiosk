package com.android.kioskbooter;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.util.Log;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.media.AudioManager;
import android.view.KeyEvent;

public class BootReceiver extends BroadcastReceiver {
    private static final String TAG = "KioskBooter";
    private static final String TERMUX_COMMAND_ACTION = "com.termux.RUN_COMMAND";
    private static final String TERMUX_COMMAND_PATH = "com.termux.RUN_COMMAND_PATH";
    private static final String TERMUX_COMMAND_ARGUMENTS = "com.termux.RUN_COMMAND_ARGUMENTS";
    private static final String TERMUX_COMMAND_WORKDIR = "com.termux.RUN_COMMAND_WORKDIR";
    private static final String TERMUX_COMMAND_BACKGROUND = "com.termux.RUN_COMMAND_BACKGROUND";
    private static final String TERMUX_HOME = "/data/data/com.termux/files/home";

    private void startTermuxActivity(Context context, boolean force) {
        if (!force && context.getSharedPreferences("kiosk_state", Context.MODE_PRIVATE)
                .getBoolean("termux_foreground_handoff_done", false)) {
            Log.i(TAG, "Termux startup handoff already completed; preserving current foreground activity");
            return;
        }
        try {
            Intent activityIntent = new Intent();
            activityIntent.setClassName("com.termux", "com.termux.app.TermuxActivity");
            activityIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK
                    | Intent.FLAG_ACTIVITY_CLEAR_TOP
                    | Intent.FLAG_ACTIVITY_SINGLE_TOP);
            context.startActivity(activityIntent);
            context.getSharedPreferences("kiosk_state", Context.MODE_PRIVATE)
                    .edit().putBoolean("termux_foreground_handoff_done", true).apply();
            Log.i(TAG, "Termux stopped state cleared");
        } catch (Exception e) {
            Log.e(TAG, "Unable to clear Termux stopped state", e);
        }
    }

    private void startKioskStack(Context context) {
        try {
            Intent command = new Intent(TERMUX_COMMAND_ACTION);
            command.setClassName("com.termux", "com.termux.app.RunCommandService");
            command.putExtra(TERMUX_COMMAND_PATH,
                    "/data/data/com.termux/files/usr/bin/bash");
            command.putExtra(TERMUX_COMMAND_ARGUMENTS, new String[] {
                    "-c",
                    TERMUX_HOME + "/boot_orchestrator_v2_integrated.sh; "
                            + "exec /data/data/com.termux/files/usr/bin/sleep infinity"
            });
            command.putExtra(TERMUX_COMMAND_WORKDIR, TERMUX_HOME);
            command.putExtra(TERMUX_COMMAND_BACKGROUND, true);
            context.startService(command);
            Log.i(TAG, "Requested the single Termux kiosk orchestrator");
        } catch (Exception e) {
            Log.e(TAG, "Unable to request Termux kiosk orchestrator", e);
        }
    }

    private void startKioskStackWithRetry(Context context, boolean forceTermuxActivation) {
        // On this firmware RUN_COMMAND can remain registered while Termux's
        // command shell has stopped. Re-activating Termux before the command
        // is the reliable recovery path; the delayed NewPipe handoff restores
        // the user-facing foreground app afterwards.
        startTermuxActivity(context, forceTermuxActivation);
        startKioskStack(context);
        if (forceTermuxActivation) {
            // This P7 can deliver BOOT_COMPLETED before Termux is ready to
            // bind its service. The first RUN_COMMAND request is then lost
            // even though the receiver itself ran successfully. Retry after
            // the early-boot service window; the orchestrator's own lock and
            // daemon checks make this safe if the first request succeeded.
            final Context appContext = context.getApplicationContext();
            new Handler(Looper.getMainLooper()).postDelayed(new Runnable() {
                @Override public void run() {
                    Log.i(TAG, "Retrying the single Termux kiosk orchestrator after cold boot");
                    startKioskStack(appContext);
                }
            }, 10000);
        }
        // Termux is the sole foreground/playback owner after the RUN_COMMAND
        // request. Do not schedule a second NewPipe handoff here; it races the
        // orchestrator and used an activity name that is not exported on every
        // NewPipe build.
    }

    private void scheduleNewPipeForeground(Context context) {
        final Context appContext = context.getApplicationContext();
        new Handler(Looper.getMainLooper()).postDelayed(new Runnable() {
            @Override public void run() {
                try {
                    Intent activityIntent = new Intent(Intent.ACTION_MAIN);
                    activityIntent.setClassName("org.schabi.newpipe",
                            "org.schabi.newpipe.MainActivity");
                    activityIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK
                            | Intent.FLAG_ACTIVITY_CLEAR_TOP
                            | Intent.FLAG_ACTIVITY_SINGLE_TOP);
                    appContext.startActivity(activityIntent);
                    Log.i(TAG, "Delayed NewPipe foreground handoff completed");
                    new Handler(Looper.getMainLooper()).postDelayed(new Runnable() {
                        @Override public void run() {
                            InputBlockerService.requestNewPipeFullscreen();
                        }
                    }, 2500);
                } catch (Exception e) {
                    Log.e(TAG, "Unable to hand off foreground to NewPipe", e);
                }
            }
        }, 20000);
    }

    private void dispatchMediaPlay(Context context) {
        try {
            AudioManager audio = (AudioManager)
                    context.getApplicationContext().getSystemService(Context.AUDIO_SERVICE);
            audio.dispatchMediaKeyEvent(new KeyEvent(
                    KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_MEDIA_PLAY));
            audio.dispatchMediaKeyEvent(new KeyEvent(
                    KeyEvent.ACTION_UP, KeyEvent.KEYCODE_MEDIA_PLAY));
            Log.i(TAG, "Dispatched trusted media play");
        } catch (Exception e) {
            Log.e(TAG, "Unable to dispatch media play", e);
        }
    }

    @Override
    public void onReceive(Context context, Intent intent) {
        String action = intent.getAction();
        Log.i(TAG, "Received action: " + action);

        if ("com.android.kioskbooter.TOUCH_LOCK".equals(action)
                || "com.android.kioskbooter.TOUCH_UNLOCK".equals(action)) {
            boolean unlocked = "com.android.kioskbooter.TOUCH_UNLOCK".equals(action);
            InputBlockerService.setCommandedUnlock(unlocked);
            context.getSharedPreferences("kiosk_state", Context.MODE_PRIVATE)
                    .edit().putBoolean("touch_unlocked", unlocked).apply();
            Log.i(TAG, "Touch barrier state: " + (unlocked ? "unlocked" : "locked"));
            return;
        }

        if ("com.android.kioskbooter.TAP".equals(action)) {
            // Termux cannot inject input events on this firmware. Forward the
            // coordinate request to the installed accessibility service, which
            // can dispatch a trusted gesture without exposing child input.
            InputBlockerService.requestTap(intent.getIntExtra("x", 0),
                    intent.getIntExtra("y", 0));
            return;
        }

        if ("com.android.kioskbooter.NEWPIPE_FULLSCREEN".equals(action)) {
            InputBlockerService.requestNewPipeFullscreen();
            return;
        }

        if ("com.android.kioskbooter.MEDIA_PLAY".equals(action)) {
            dispatchMediaPlay(context);
            return;
        }

        if ("com.android.kioskbooter.BRIGHTNESS_SET".equals(action)) {
            int brightness = intent.getIntExtra("brightness", -1);
            InputBlockerService.setCommandedBrightness(brightness);
            Log.i(TAG, "Requested child overlay brightness=" + brightness);
            return;
        }

        if (Intent.ACTION_BOOT_COMPLETED.equals(action)
                || "com.android.kioskbooter.WAKEUP".equals(action)
                || "com.android.kioskbooter.RESTART_STACK".equals(action)) {
            // Clear Android's stopped-app state, then use Termux's documented
            // RUN_COMMAND service. Some vendor firmware skips Termux:Boot even
            // though it delivers this receiver reliably.
            if (Intent.ACTION_BOOT_COMPLETED.equals(action)) {
                context.getSharedPreferences("kiosk_state", Context.MODE_PRIVATE)
                        .edit().putBoolean("termux_foreground_handoff_done", false).apply();
            }
            boolean coldStart = Intent.ACTION_BOOT_COMPLETED.equals(action)
                    || "com.android.kioskbooter.WAKEUP".equals(action);
            // A manual stack restart must preserve the currently visible
            // NewPipe surface. Bringing Termux to the foreground here caused
            // a second foreground owner and could leave the child on a blank
            // terminal while the daemons were already healthy.
            startKioskStackWithRetry(context, coldStart);
            // Cold boot still gets one delayed handoff for firmware that will
            // not foreground NewPipe from Termux's background command. The
            // explicit restart path leaves foreground recovery to
            // newpipe_24x7, the sole playback owner.
            if (coldStart) {
                scheduleNewPipeForeground(context);
            }
        } else if ("com.android.kioskbooter.START_ACTIVITY".equals(action)) {
            try {
                // Disable VM policy file URI exposure check to prevent FileUriExposedException
                try {
                    Class<?> strictModeClass = Class.forName("android.os.StrictMode");
                    strictModeClass.getMethod("disableDeathOnFileUriExposure").invoke(null);
                } catch (Exception e) {
                    Log.w(TAG, "Failed to disable StrictMode FileUri check: " + e.getMessage());
                }

                String component = intent.getStringExtra("component");
                String data = intent.getStringExtra("data");
                String act = intent.getStringExtra("action");
                String type = intent.getStringExtra("type");
                
                Log.i(TAG, "Starting activity for component: " + component + ", action: " + act + ", data: " + data);
                
                Intent launchIntent = new Intent();
                if (act != null) {
                    launchIntent.setAction(act);
                } else {
                    launchIntent.setAction(Intent.ACTION_VIEW);
                }
                
                if (data != null && type != null) {
                    launchIntent.setDataAndType(Uri.parse(data), type);
                } else {
                    if (data != null) {
                        launchIntent.setData(Uri.parse(data));
                    }
                    if (type != null) {
                        launchIntent.setType(type);
                    }
                }
                
                if (component != null && component.contains("/")) {
                    String[] parts = component.split("/");
                    String pkg = parts[0];
                    String cls = parts[1];
                    if (cls.startsWith(".")) {
                        cls = pkg + cls;
                    }
                    launchIntent.setClassName(pkg, cls);
                }
                
                // Add extras if present
                Bundle extras = intent.getExtras();
                if (extras != null) {
                    for (String key : extras.keySet()) {
                        if (!"component".equals(key) && !"data".equals(key) && !"action".equals(key) && !"type".equals(key)) {
                            Object val = extras.get(key);
                            if (val instanceof String) {
                                String stringVal = (String) val;
                                if ("autoplay".equals(key) || "fullscreen".equals(key)) {
                                    launchIntent.putExtra(key, Boolean.parseBoolean(stringVal));
                                } else {
                                    launchIntent.putExtra(key, stringVal);
                                }
                            }
                        }
                    }
                }
                
                launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                context.startActivity(launchIntent);
                Log.i(TAG, "Activity launched successfully via KioskBooter");

                // NewPipe can restore its player before accepting media input.
                // Dispatch PLAY twice, gently spaced, instead of coordinate taps.
                final Context appContext = context.getApplicationContext();
                final Handler handler = new Handler(Looper.getMainLooper());
                Runnable play = new Runnable() {
                    @Override public void run() {
                        dispatchMediaPlay(appContext);
                    }
                };
                handler.postDelayed(play, 2500);
                handler.postDelayed(play, 6000);
            } catch (Exception e) {
                Log.e(TAG, "Error launching activity via KioskBooter", e);
            }
        }
    }
}
