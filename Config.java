import java.util.Properties;
import java.io.*;
import java.awt.event.KeyEvent;
import java.awt.image.BufferedImage;
import javax.imageio.ImageIO;
import javax.sound.sampled.FloatControl;

public class Config {
    private static final String FILE_NAME = "config.properties";
    private static Properties props = new Properties();
    private static BufferedImage playerTexture = null;

    static {
        loadProperties();
        loadTexture();
    }

    private static void loadProperties() {
        File cfg = new File(FILE_NAME);
        boolean changed = false;
        if (cfg.exists()) {
            try (FileInputStream in = new FileInputStream(cfg)) {
                props.load(in);
            } catch (IOException e) {
                e.printStackTrace();
            }
        }
        // дробные скорости
        changed |= addDefault("playerSpeed",   "5.0");
        changed |= addDefault("bulletSpeed",   "4.0");
        changed |= addDefault("slowSpeed",     "2.0");
        // размеры и хитбокс
        changed |= addDefault("screenWidth",   "800");
        changed |= addDefault("screenHeight",  "600");
        changed |= addDefault("hitboxRadius",  "10");
        // управление по умолчанию WASD
        changed |= addDefault("keyLeft",       "A");
        changed |= addDefault("keyRight",      "D");
        changed |= addDefault("keyUp",         "W");
        changed |= addDefault("keyDown",       "S");
        changed |= addDefault("playerTexture", "");
        // звук
        changed |= addDefault("musicVolume",   "1.0");
        changed |= addDefault("sfxVolume",     "1.0");
        // ограничения FPS и VSync
        changed |= addDefault("maxFPS",        "60");    // 0 — без ограничения
        changed |= addDefault("vsync",         "true");  // вертикальная синхронизация
        // затемнение фона (0.0–1.0)
        changed |= addDefault("backgroundDim", "0.5");

        if (changed) {
            try (FileOutputStream out = new FileOutputStream(cfg)) {
                props.store(out, null);
            } catch (IOException e) {
                e.printStackTrace();
            }
        }
    }

    private static boolean addDefault(String key, String def) {
        if (!props.containsKey(key)) {
            props.setProperty(key, def);
            return true;
        }
        return false;
    }

    private static void loadTexture() {
        String path = props.getProperty("playerTexture", "").trim();
        if (!path.isEmpty()) {
            try {
                playerTexture = ImageIO.read(new File(path));
            } catch (IOException e) {
                System.err.println("Config: failed to load texture `" + path + "`: " + e.getMessage());
            }
        }
    }

    // дробные скорости
    public static double getPlayerSpeed() {
        try {
            return Double.parseDouble(props.getProperty("playerSpeed", "5.0"));
        } catch (NumberFormatException e) {
            return 5.0;
        }
    }
    public static double getBulletSpeed() {
        try {
            return Double.parseDouble(props.getProperty("bulletSpeed", "4.0"));
        } catch (NumberFormatException e) {
            return 4.0;
        }
    }
    public static double getSlowSpeed() {
        try {
            return Double.parseDouble(props.getProperty("slowSpeed", "2.0"));
        } catch (NumberFormatException e) {
            return 2.0;
        }
    }

    public static int getScreenWidth()    { return Integer.parseInt(props.getProperty("screenWidth")); }
    public static int getScreenHeight()   { return Integer.parseInt(props.getProperty("screenHeight")); }
    public static int getHitboxRadius()   { return Integer.parseInt(props.getProperty("hitboxRadius")); }

    public static int getKeyCode(String keyProp) {
        String k = props.getProperty(keyProp, "").trim().toUpperCase();
        switch (k) {
            case "LEFT":  return KeyEvent.VK_LEFT;
            case "RIGHT": return KeyEvent.VK_RIGHT;
            case "UP":    return KeyEvent.VK_UP;
            case "DOWN":  return KeyEvent.VK_DOWN;
            case "SHIFT": return KeyEvent.VK_SHIFT;
            default:
                if (k.length() == 1) return KeyEvent.getExtendedKeyCodeForChar(k.charAt(0));
                try { return Integer.parseInt(k); }
                catch (Exception e) { return KeyEvent.getExtendedKeyCodeForChar(k.charAt(0)); }
        }
    }

    public static BufferedImage getPlayerTexture() {
        return playerTexture;
    }

    public static float getMusicVolume() {
        try {
            return Float.parseFloat(props.getProperty("musicVolume", "1.0"));
        } catch (NumberFormatException e) {
            return 1.0f;
        }
    }

    public static float getSfxVolume() {
        try {
            return Float.parseFloat(props.getProperty("sfxVolume", "1.0"));
        } catch (NumberFormatException e) {
            return 1.0f;
        }
    }

    public static int getMaxFPS() {
        try {
            return Integer.parseInt(props.getProperty("maxFPS", "0"));
        } catch (NumberFormatException e) {
            return 0;
        }
    }

    public static boolean isVSyncEnabled() {
        return Boolean.parseBoolean(props.getProperty("vsync", "true"));
    }

    /**
     * @return степень затемнения фона (0.0 = нет затемнения, 1.0 = полностью чёрный)
     */
    public static float getBackgroundDim() {
        try {
            return Float.parseFloat(props.getProperty("backgroundDim", "0.5"));
        } catch (NumberFormatException e) {
            return 0.5f;
        }
    }
}
