import android.content.ComponentName;
import java.lang.reflect.Method;

/**
 * ADB-shell helper for vendor builds whose wallpaper picker hides third-party
 * WallpaperService entries. Run only from the authorized shell UID.
 */
public final class LiveWallpaperSetter {
    public static void main(String[] args) {
        if (args.length != 1 || !args[0].contains("/")) {
            System.err.println("Usage: LiveWallpaperSetter package/class");
            System.exit(2);
        }
        try {
            Class<?> looperClass = Class.forName("android.os.Looper");
            if (looperClass.getMethod("myLooper").invoke(null) == null) {
                looperClass.getMethod("prepare").invoke(null);
            }
            String[] parts = args[0].split("/", 2);
            String className = parts[1].startsWith(".")
                    ? parts[0] + parts[1] : parts[1];
            ComponentName component = new ComponentName(parts[0], className);

            Class<?> serviceManagerClass = Class.forName("android.os.ServiceManager");
            Object binder = serviceManagerClass
                    .getMethod("getService", String.class).invoke(null, "wallpaper");
            Class<?> binderClass = Class.forName("android.os.IBinder");
            Class<?> stubClass = Class.forName("android.app.IWallpaperManager$Stub");
            Object manager = stubClass.getMethod("asInterface", binderClass)
                    .invoke(null, binder);
            Method setter = manager.getClass().getMethod(
                    "setWallpaperComponentChecked",
                    ComponentName.class, String.class, int.class);
            setter.invoke(manager, component, "com.android.shell", 0);
            boolean changed = true;
            System.out.println("component=" + component.flattenToShortString());
            System.out.println("changed=" + changed);
            System.exit(changed ? 0 : 1);
        } catch (Throwable error) {
            error.printStackTrace(System.err);
            System.exit(1);
        }
    }
}
