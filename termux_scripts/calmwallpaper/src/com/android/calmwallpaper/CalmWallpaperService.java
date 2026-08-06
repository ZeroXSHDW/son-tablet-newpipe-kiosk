package com.android.calmwallpaper;

import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.LinearGradient;
import android.graphics.Paint;
import android.graphics.Shader;
import android.os.Handler;
import android.service.wallpaper.WallpaperService;
import android.view.SurfaceHolder;
import java.util.Calendar;

/**
 * Slow, deterministic live wallpaper for a child's kiosk tablet.
 * It contains no network access, tracking, ads, touch actions, or audio.
 * The supervised NewPipe night playlist owns ASMR playback.
 */
public final class CalmWallpaperService extends WallpaperService {
    @Override
    public Engine onCreateEngine() {
        return new CalmEngine();
    }

    private final class CalmEngine extends Engine {
        private static final long FRAME_MS = 125L; // 8 fps: gentle and battery-aware
        private final Handler handler = new Handler();
        private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Runnable drawTask = new Runnable() {
            @Override public void run() { drawFrame(); }
        };
        private boolean visible;
        private float phase;

        @Override
        public void onVisibilityChanged(boolean isVisible) {
            visible = isVisible;
            handler.removeCallbacks(drawTask);
            if (visible) drawFrame();
        }

        @Override
        public void onSurfaceChanged(
                SurfaceHolder holder, int format, int width, int height) {
            super.onSurfaceChanged(holder, format, width, height);
            drawFrame();
        }

        @Override
        public void onSurfaceDestroyed(SurfaceHolder holder) {
            super.onSurfaceDestroyed(holder);
            visible = false;
            handler.removeCallbacks(drawTask);
        }

        private int currentPhase() {
            Calendar now = Calendar.getInstance();
            int hm = now.get(Calendar.HOUR_OF_DAY) * 100 + now.get(Calendar.MINUTE);
            if (hm >= 600 && hm < 1800) return 0;   // calm day
            if (hm >= 1800 && hm < 2030) return 1;  // dusk
            return 2;                               // bedtime/night
        }

        private void drawFrame() {
            SurfaceHolder holder = getSurfaceHolder();
            Canvas canvas = null;
            try {
                canvas = holder.lockCanvas();
                if (canvas == null) return;
                int width = canvas.getWidth();
                int height = canvas.getHeight();
                int mode = currentPhase();
                int top;
                int bottom;
                if (mode == 0) {
                    top = Color.rgb(42, 112, 132);
                    bottom = Color.rgb(80, 145, 112);
                } else if (mode == 1) {
                    top = Color.rgb(76, 55, 105);
                    bottom = Color.rgb(151, 91, 112);
                } else {
                    top = Color.rgb(7, 12, 34);
                    bottom = Color.rgb(24, 31, 65);
                }

                paint.setShader(new LinearGradient(
                        0, 0, 0, height, top, bottom, Shader.TileMode.CLAMP));
                canvas.drawRect(0, 0, width, height, paint);
                paint.setShader(null);

                // A few slow translucent orbs; movement is periodic and gentle.
                int count = mode == 2 ? 12 : 8;
                for (int i = 0; i < count; i++) {
                    double t = phase * (0.10 + i * 0.004) + i * 0.83;
                    float x = (float) ((0.08 + 0.84 * ((Math.sin(t) + 1) / 2)) * width);
                    float y = (float) ((0.10 + 0.80 * ((Math.cos(t * 0.73) + 1) / 2)) * height);
                    float radius = Math.max(3f, Math.min(width, height) * (0.008f + (i % 3) * 0.004f));
                    int alpha = mode == 2 ? 55 : 38;
                    paint.setColor(Color.argb(alpha, 230, 242, 255));
                    canvas.drawCircle(x, y, radius, paint);
                }
                phase += 0.04f;
            } finally {
                if (canvas != null) holder.unlockCanvasAndPost(canvas);
                handler.removeCallbacks(drawTask);
                if (visible) handler.postDelayed(drawTask, FRAME_MS);
            }
        }
    }
}
