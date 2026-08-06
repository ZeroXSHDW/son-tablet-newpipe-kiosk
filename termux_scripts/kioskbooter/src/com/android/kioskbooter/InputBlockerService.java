package com.android.kioskbooter;

import android.accessibilityservice.AccessibilityService;
import android.accessibilityservice.AccessibilityServiceInfo;
import android.graphics.Color;
import android.graphics.Point;
import android.graphics.PixelFormat;
import android.graphics.Path;
import android.graphics.Rect;
import android.os.Handler;
import android.os.Looper;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.View;
import android.view.WindowManager;
import android.accessibilityservice.GestureDescription;
import android.media.AudioManager;
import android.util.Log;
import android.view.accessibility.AccessibilityNodeInfo;
import android.view.accessibility.AccessibilityWindowInfo;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;

import java.io.BufferedReader;
import java.io.FileReader;
import java.util.ArrayDeque;
import java.util.List;

/**
 * Child-mode input barrier. The overlay is transparent and consumes physical
 * touchscreen events across the display. The playback controller can request
 * a short unlock window through the local broadcast/file handshake while it
 * performs a NewPipe recovery action, then it relocks the display.
 */
public class InputBlockerService extends AccessibilityService {
    private static final String ACTION_LOCK = "com.android.kioskbooter.TOUCH_LOCK";
    private static final String ACTION_UNLOCK = "com.android.kioskbooter.TOUCH_UNLOCK";
    private static final String ACTION_TAP = "com.android.kioskbooter.TAP";
    private static final String NEWPIPE_PACKAGE = "org.schabi.newpipe";
    private static final String ACTION_NEWPIPE_FULLSCREEN =
            "com.android.kioskbooter.NEWPIPE_FULLSCREEN";
    private static final int NEWPIPE_FULLSCREEN_MAX_ATTEMPTS = 12;
    private static final String PARENT_FILE = "/sdcard/Kiosk/parent_mode.txt";

    private final Handler handler = new Handler(Looper.getMainLooper());
    private WindowManager windowManager;
    private View blockerView;
    private WindowManager.LayoutParams blockerParams;
    private BroadcastReceiver receiver;
    private boolean locked;
    private static volatile boolean commandedUnlock = false;
    private static volatile float commandedBrightness = -1.0f;
    private static volatile InputBlockerService activeInstance;
    private static volatile boolean pendingNewPipeFullscreen = false;
    private static final ArrayDeque<int[]> pendingTaps = new ArrayDeque<>();
    private boolean newPipeFullscreenRunning = false;
    private boolean restoreUnlockAfterFullscreen = false;
    private int newPipeFullscreenAttempts = 0;
    private final Runnable newPipeFullscreenWatchdog = new Runnable() {
        @Override public void run() {
            runNewPipeFullscreenWatchdog();
        }
    };
    private final Runnable newPipeFullscreenEventProbe = new Runnable() {
        @Override public void run() {
            runNewPipeFullscreenWatchdog();
        }
    };
    private final Runnable newPipeFullscreenTimeout = new Runnable() {
        @Override public void run() {
            if (newPipeFullscreenRunning) {
                Log.w("KioskBooter", "Fullscreen transition timeout; releasing controller");
                finishNewPipeFullscreen();
            }
        }
    };

    public static void setCommandedUnlock(boolean unlocked) {
        commandedUnlock = unlocked;
    }

    public static void setCommandedBrightness(int brightness) {
        if (brightness < 0) {
            commandedBrightness = -1.0f;
        } else {
            int bounded = Math.max(0, Math.min(255, brightness));
            commandedBrightness = bounded / 255.0f;
        }
        final InputBlockerService service = activeInstance;
        if (service != null) {
            service.handler.post(new Runnable() {
                @Override public void run() {
                    service.applyCommandedBrightness();
                }
            });
        }
    }

    public static void requestTap(int x, int y) {
        InputBlockerService service = activeInstance;
        if (service != null) {
            service.performTap(x, y);
            return;
        }
        synchronized (pendingTaps) {
            // The boot receiver can receive the first controller gestures
            // before Android has finished binding the accessibility service.
            // Keep a bounded FIFO so early fullscreen gestures are replayed
            // once the trusted service is ready.
            while (pendingTaps.size() >= 8) {
                pendingTaps.removeFirst();
            }
            pendingTaps.addLast(new int[] {x, y});
        }
    }

    /**
     * Request a player-level fullscreen transition using the accessibility
     * node tree. Termux's app UID cannot run uiautomator dumps on this tablet,
     * while this already-authorized service can read the live NewPipe bounds.
     */
    public static void requestNewPipeFullscreen() {
        final InputBlockerService service = activeInstance;
        if (service == null) {
            pendingNewPipeFullscreen = true;
            return;
        }
        service.handler.post(new Runnable() {
            @Override public void run() {
                service.beginNewPipeFullscreen();
            }
        });
    }

    private boolean fileContains(String path, String expected) {
        try (BufferedReader reader = new BufferedReader(new FileReader(path))) {
            String value = reader.readLine();
            return expected.equals(value == null ? "" : value.trim());
        } catch (Exception ignored) {
            return false;
        }
    }

    private boolean parentMode() {
        return fileContains(PARENT_FILE, "true");
    }

    private boolean requestedUnlock() {
        return commandedUnlock;
    }

    private void reconcile() {
        boolean shouldLock = !parentMode() && !requestedUnlock();
        if (shouldLock) {
            addBlocker();
        } else {
            removeBlocker();
        }
    }

    private void applyCommandedBrightness() {
        if (!locked || windowManager == null || blockerView == null || blockerParams == null) {
            return;
        }
        blockerParams.screenBrightness = commandedBrightness;
        try {
            windowManager.updateViewLayout(blockerView, blockerParams);
        } catch (Exception ignored) {
            // The accessibility window may be between attach/detach events.
        }
    }

    private void addBlocker() {
        if (locked || windowManager == null) {
            return;
        }
        try {
            if (blockerView == null) {
                blockerView = new View(this) {
                    @Override
                    public boolean onTouchEvent(MotionEvent event) {
                        return true;
                    }
                };
                blockerView.setBackgroundColor(Color.TRANSPARENT);
                blockerView.setClickable(true);
            }
            WindowManager.LayoutParams params = new WindowManager.LayoutParams(
                    WindowManager.LayoutParams.MATCH_PARENT,
                    WindowManager.LayoutParams.MATCH_PARENT,
                    WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                            | WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN
                            | WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
                    PixelFormat.TRANSLUCENT);
            params.gravity = Gravity.TOP | Gravity.START;
            params.screenBrightness = commandedBrightness;
            blockerParams = params;
            windowManager.addView(blockerView, params);
            locked = true;
            applyCommandedBrightness();
        } catch (Exception ignored) {
            locked = false;
            blockerParams = null;
        }
    }

    private void removeBlocker() {
        if (!locked || windowManager == null || blockerView == null) {
            locked = false;
            return;
        }
        try {
            windowManager.removeViewImmediate(blockerView);
        } catch (Exception ignored) {
            // The view may already have been removed during service teardown.
        }
        locked = false;
        blockerParams = null;
    }

    private AccessibilityNodeInfo findNodeByViewId(AccessibilityNodeInfo node, String viewId) {
        if (node == null) {
            return null;
        }
        if (viewId.equals(node.getViewIdResourceName())) {
            return node;
        }
        try {
            List<AccessibilityNodeInfo> matches = node.findAccessibilityNodeInfosByViewId(viewId);
            if (matches != null && !matches.isEmpty()) {
                return matches.get(0);
            }
        } catch (Exception ignored) {
            // Fall back to the recursive walk below on older vendor services.
        }
        for (int i = 0; i < node.getChildCount(); i++) {
            AccessibilityNodeInfo found = findNodeByViewId(node.getChild(i), viewId);
            if (found != null) {
                return found;
            }
        }
        return null;
    }

    private AccessibilityNodeInfo findNodeByContentDescription(
            AccessibilityNodeInfo node, String description) {
        if (node == null) {
            return null;
        }
        CharSequence current = node.getContentDescription();
        if (current != null && description.contentEquals(current)) {
            return node;
        }
        for (int i = 0; i < node.getChildCount(); i++) {
            AccessibilityNodeInfo found = findNodeByContentDescription(
                    node.getChild(i), description);
            if (found != null) {
                return found;
            }
        }
        return null;
    }

    private AccessibilityNodeInfo findNewPipePlayerPlaceholder(AccessibilityNodeInfo root) {
        return findNodeByViewId(root, NEWPIPE_PACKAGE + ":id/player_placeholder");
    }

    private AccessibilityNodeInfo findNewPipePlayerHolder(AccessibilityNodeInfo root) {
        return findNodeByViewId(root, NEWPIPE_PACKAGE + ":id/fragment_player_holder");
    }

    private boolean isNewPipeWindow(AccessibilityNodeInfo root) {
        return root != null && root.getPackageName() != null
                && NEWPIPE_PACKAGE.contentEquals(root.getPackageName());
    }

    private AccessibilityNodeInfo getNewPipeRoot() {
        AccessibilityNodeInfo active = getRootInActiveWindow();
        if (isNewPipeWindow(active)) {
            return active;
        }
        try {
            List<AccessibilityWindowInfo> windows = getWindows();
            for (AccessibilityWindowInfo window : windows) {
                AccessibilityNodeInfo root = window.getRoot();
                if (isNewPipeWindow(root)) {
                    return root;
                }
            }
        } catch (Exception ignored) {
            // The active root remains a valid fallback during window changes.
        }
        return active;
    }

    private void getDisplaySize(Point out) {
        if (windowManager != null) {
            windowManager.getDefaultDisplay().getRealSize(out);
        } else {
            out.x = getResources().getDisplayMetrics().widthPixels;
            out.y = getResources().getDisplayMetrics().heightPixels;
        }
    }

    private void beginNewPipeFullscreen() {
        if (newPipeFullscreenRunning) {
            return;
        }
        newPipeFullscreenRunning = true;
        restoreUnlockAfterFullscreen = commandedUnlock;
        commandedUnlock = true;
        newPipeFullscreenAttempts = 0;
        removeBlocker();
        handler.removeCallbacks(newPipeFullscreenTimeout);
        handler.postDelayed(newPipeFullscreenTimeout, 20000);
        // A paused NewPipe mini-player is allowed to collapse again after the
        // gesture completes. Request PLAY through Android's trusted media
        // dispatcher so the fullscreen state is a real playback state, not a
        // transient expanded detail pane.
        dispatchMediaPlay();
        runNewPipeFullscreenAttempt();
    }

    private void dispatchMediaPlay() {
        try {
            AudioManager audio = (AudioManager) getSystemService(AUDIO_SERVICE);
            audio.dispatchMediaKeyEvent(new KeyEvent(
                    KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_MEDIA_PLAY));
            audio.dispatchMediaKeyEvent(new KeyEvent(
                    KeyEvent.ACTION_UP, KeyEvent.KEYCODE_MEDIA_PLAY));
        } catch (Exception e) {
            Log.w("KioskBooter", "Trusted media play failed: " + e.getMessage());
        }
    }

    private void finishNewPipeFullscreen() {
        handler.removeCallbacks(newPipeFullscreenTimeout);
        clickNewPipePlayControl();
        newPipeFullscreenRunning = false;
        commandedUnlock = restoreUnlockAfterFullscreen;
        if (!commandedUnlock && !parentMode()) {
            addBlocker();
        }
    }

    private void clickNewPipePlayControl() {
        AccessibilityNodeInfo root = getNewPipeRoot();
        if (!isNewPipeWindow(root)) {
            return;
        }
        AccessibilityNodeInfo play = findNodeByContentDescription(root, "Play");
        if (play != null && play.isClickable()) {
            if (play.performAction(AccessibilityNodeInfo.ACTION_CLICK)) {
                Log.i("KioskBooter", "Clicked native NewPipe Play control");
            }
        }
    }

    private void runNewPipeFullscreenAttempt() {
        if (!newPipeFullscreenRunning) {
            return;
        }
        AccessibilityNodeInfo root = getNewPipeRoot();
        AccessibilityNodeInfo placeholder = findNewPipePlayerPlaceholder(root);
        AccessibilityNodeInfo player = placeholder != null
                ? placeholder : findNewPipePlayerHolder(root);
        if (!isNewPipeWindow(root) || player == null) {
            if (++newPipeFullscreenAttempts < NEWPIPE_FULLSCREEN_MAX_ATTEMPTS) {
                handler.postDelayed(new Runnable() {
                    @Override public void run() {
                        runNewPipeFullscreenAttempt();
                    }
                }, 700);
            } else {
                finishNewPipeFullscreen();
            }
            return;
        }

        Point display = new Point();
        getDisplaySize(display);
        Rect bounds = new Rect();
        player.getBoundsInScreen(bounds);
        // NewPipe's tablet layout keeps fragment_player_holder full-screen
        // while the embedded video/queue pane occupies only the left side.
        // Use the detail content bounds for that state so it is not mistaken
        // for player fullscreen.
        if (placeholder == null) {
            AccessibilityNodeInfo detail = findNodeByViewId(root,
                    NEWPIPE_PACKAGE + ":id/detail_main_content");
            if (detail != null) {
                Rect detailBounds = new Rect();
                detail.getBoundsInScreen(detailBounds);
                if (detailBounds.width() < display.x - 32) {
                    bounds.set(detailBounds);
                }
            }
        }
        // The bottom mini-player can span the full tablet width, so width alone
        // is not proof that the player has entered fullscreen mode.
        if (bounds.width() >= display.x - 32
                && bounds.height() >= display.y - 80
                && bounds.top <= 48) {
            finishNewPipeFullscreen();
            return;
        }
        if (++newPipeFullscreenAttempts > NEWPIPE_FULLSCREEN_MAX_ATTEMPTS) {
            finishNewPipeFullscreen();
            return;
        }

        final int centerX = bounds.centerX();
        final int centerY = bounds.centerY();
        boolean miniPlayer = bounds.top >= display.y - 160
                || (bounds.width() >= display.x - 32
                && bounds.height() < display.y - 80);
        if (miniPlayer) {
            // Mini-player: open the current video detail pane first.
            // Some builds report the navigation-bar edge as the mini-player
            // bottom, so its geometric center can land on the nav boundary.
            // Tap safely inside the visible upper portion instead.
            int miniTapY = Math.min(504,
                    Math.max(bounds.top + 1, bounds.bottom - 48));
            performTap(centerX, miniTapY);
            handler.postDelayed(new Runnable() {
                @Override public void run() {
                    runNewPipeFullscreenAttempt();
                }
            }, 1300);
            return;
        }

        // Detail pane: surface tap reveals controls, then the native rotation
        // button is clicked from the refreshed accessibility node tree.
        performTap(centerX, centerY);
        handler.postDelayed(new Runnable() {
            @Override public void run() {
                clickNewPipeRotationControl();
            }
        }, 350);
    }

    private void clickNewPipeRotationControl() {
        if (!newPipeFullscreenRunning) {
            return;
        }
        AccessibilityNodeInfo root = getNewPipeRoot();
        AccessibilityNodeInfo rotation = findNodeByViewId(root,
                NEWPIPE_PACKAGE + ":id/screenRotationButton");
        boolean clicked = false;
        if (isNewPipeWindow(root) && rotation != null) {
            clicked = rotation.performAction(AccessibilityNodeInfo.ACTION_CLICK);
        }
        if (!clicked) {
            if (isNewPipeWindow(root) && rotation != null) {
                Rect rotationBounds = new Rect();
                rotation.getBoundsInScreen(rotationBounds);
                performTap(rotationBounds.centerX(), rotationBounds.centerY());
                handler.postDelayed(new Runnable() {
                    @Override public void run() {
                        runNewPipeFullscreenAttempt();
                    }
                }, 1800);
                return;
            }
            // Older NewPipe tablet layouts do not expose a rotation control
            // while the video is embedded beside the queue.  Avoid tapping a
            // guessed bottom-right coordinate there; the next bounded attempt
            // will re-read the refreshed accessibility tree.
        }
        handler.postDelayed(new Runnable() {
            @Override public void run() {
                runNewPipeFullscreenAttempt();
            }
        }, 1800);
    }

    /**
     * Keep player-level fullscreen owned by the bound accessibility service.
     * Termux's `am` wrapper can block on this firmware, so a shell watchdog
     * cannot be the only path that repairs a NewPipe mini-player.
     */
    private void runNewPipeFullscreenWatchdog() {
        try {
            if (!parentMode() && !newPipeFullscreenRunning) {
                AccessibilityNodeInfo root = getNewPipeRoot();
                AccessibilityNodeInfo placeholder = findNewPipePlayerPlaceholder(root);
                AccessibilityNodeInfo player = placeholder != null
                        ? placeholder : findNewPipePlayerHolder(root);
                if (isNewPipeWindow(root) && player != null) {
                    Point display = new Point();
                    getDisplaySize(display);
                    Rect bounds = new Rect();
                    player.getBoundsInScreen(bounds);
                    if (placeholder == null) {
                        AccessibilityNodeInfo detail = findNodeByViewId(root,
                                NEWPIPE_PACKAGE + ":id/detail_main_content");
                        if (detail != null) {
                            Rect detailBounds = new Rect();
                            detail.getBoundsInScreen(detailBounds);
                            if (detailBounds.width() < display.x - 32) {
                                bounds.set(detailBounds);
                            }
                        }
                    }
                    boolean fullscreen = bounds.width() >= display.x - 32
                            && bounds.height() >= display.y - 80
                            && bounds.top <= 48;
                    if (!fullscreen) {
                        Log.i("KioskBooter", "Fullscreen watchdog promoting player bounds="
                                + bounds.toShortString());
                        beginNewPipeFullscreen();
                    }
                }
            }
        } catch (Exception e) {
            Log.w("KioskBooter", "Fullscreen watchdog pass failed: " + e.getMessage());
        } finally {
            handler.postDelayed(newPipeFullscreenWatchdog, 4000);
        }
    }

    @Override
    protected void onServiceConnected() {
        super.onServiceConnected();
        activeInstance = this;
        AccessibilityServiceInfo info = getServiceInfo();
        if (info == null) {
            info = new AccessibilityServiceInfo();
        }
        info.eventTypes = -1;
        info.feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC;
        info.flags |= AccessibilityServiceInfo.FLAG_REQUEST_FILTER_KEY_EVENTS
                | AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS
                | AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS;
        setServiceInfo(info);

        windowManager = (WindowManager) getSystemService(WINDOW_SERVICE);
        receiver = new BroadcastReceiver() {
            @Override
            public void onReceive(Context context, Intent intent) {
                if (ACTION_TAP.equals(intent.getAction())) {
                    performTap(intent.getIntExtra("x", 0), intent.getIntExtra("y", 0));
                    return;
                }
                if (ACTION_NEWPIPE_FULLSCREEN.equals(intent.getAction())) {
                    requestNewPipeFullscreen();
                    return;
                }
                reconcile();
            }
        };
        IntentFilter filter = new IntentFilter();
        filter.addAction(ACTION_LOCK);
        filter.addAction(ACTION_UNLOCK);
        filter.addAction(ACTION_TAP);
        filter.addAction(ACTION_NEWPIPE_FULLSCREEN);
        registerReceiver(receiver, filter);
        reconcile();
        if (pendingNewPipeFullscreen) {
            pendingNewPipeFullscreen = false;
            handler.post(new Runnable() {
                @Override public void run() {
                    beginNewPipeFullscreen();
                }
            });
        }
        handler.postDelayed(new Runnable() {
            @Override public void run() {
                int[] tap = null;
                synchronized (pendingTaps) {
                    if (!pendingTaps.isEmpty()) {
                        tap = pendingTaps.removeFirst();
                    }
                }
                if (tap != null && activeInstance == InputBlockerService.this) {
                    performTap(tap[0], tap[1]);
                    handler.postDelayed(this, 350);
                }
            }
        }, 500);
        handler.postDelayed(new Runnable() {
            @Override
            public void run() {
                reconcile();
                handler.postDelayed(this, 1000);
            }
        }, 1000);
        handler.postDelayed(newPipeFullscreenWatchdog, 5000);
    }

    private void performTap(int x, int y) {
        // The overlay itself consumes touch input. Remove it for the short
        // trusted accessibility gesture; the controller explicitly relocks
        // after its bounded sequence.
        removeBlocker();
        Path path = new Path();
        path.moveTo(x, y);
        GestureDescription gesture = new GestureDescription.Builder()
                .addStroke(new GestureDescription.StrokeDescription(path, 0, 90))
                .build();
        boolean accepted = dispatchGesture(gesture, new GestureResultCallback() {
            @Override public void onCompleted(GestureDescription completedGesture) {
                Log.i("KioskBooter", "Accessibility tap completed");
                if (!requestedUnlock() && !parentMode()) {
                    addBlocker();
                }
            }
            @Override public void onCancelled(GestureDescription cancelledGesture) {
                Log.w("KioskBooter", "Accessibility tap cancelled");
                if (!requestedUnlock() && !parentMode()) {
                    addBlocker();
                }
            }
        }, null);
        Log.i("KioskBooter", "Accessibility tap requested x=" + x + " y=" + y
                + " accepted=" + accepted);
    }

    @Override
    public boolean onKeyEvent(KeyEvent event) {
        if (!locked) {
            return false;
        }
        int keyCode = event.getKeyCode();
        // Keep controller/media-session recovery available; suppress navigation,
        // volume, launcher, and other physical button paths in child mode.
        switch (keyCode) {
            case KeyEvent.KEYCODE_MEDIA_PLAY:
            case KeyEvent.KEYCODE_MEDIA_PAUSE:
            case KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE:
            case KeyEvent.KEYCODE_MEDIA_NEXT:
            case KeyEvent.KEYCODE_MEDIA_PREVIOUS:
            case KeyEvent.KEYCODE_MEDIA_FAST_FORWARD:
            case KeyEvent.KEYCODE_MEDIA_REWIND:
                return false;
            default:
                return true;
        }
    }

    @Override
    public void onAccessibilityEvent(android.view.accessibility.AccessibilityEvent event) {
        // NewPipe can restore its player into a bottom/detail pane after a
        // playback or window-state change.  Do a debounced accessibility-side
        // probe as well as the periodic watchdog so the recovery does not
        // depend on Termux being foreground or on a shell `am` call.
        CharSequence eventPackage = event == null ? null : event.getPackageName();
        if (eventPackage != null && NEWPIPE_PACKAGE.contentEquals(eventPackage)) {
            handler.removeCallbacks(newPipeFullscreenEventProbe);
            handler.postDelayed(newPipeFullscreenEventProbe, 350);
        }
    }

    @Override
    public void onInterrupt() {
        removeBlocker();
    }

    @Override
    public void onDestroy() {
        activeInstance = null;
        handler.removeCallbacks(newPipeFullscreenWatchdog);
        handler.removeCallbacks(newPipeFullscreenEventProbe);
        handler.removeCallbacks(newPipeFullscreenTimeout);
        handler.removeCallbacksAndMessages(null);
        if (receiver != null) {
            try {
                unregisterReceiver(receiver);
            } catch (Exception ignored) {
            }
        }
        removeBlocker();
        super.onDestroy();
    }
}
