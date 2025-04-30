// Config.java
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

    // Default values (change here)
    private static final double DEFAULT_PLAYER_SPEED       = 30.0;
    private static final double DEFAULT_BULLET_SPEED       = 400.0;
    private static final double DEFAULT_SLOW_SPEED         = 15.0;
    private static final int    DEFAULT_SCREEN_WIDTH       = 1280;
    private static final int    DEFAULT_SCREEN_HEIGHT      = 800;
    private static final int    DEFAULT_HITBOX_RADIUS      = 5;
    private static final String DEFAULT_KEY_LEFT           = "A";
    private static final String DEFAULT_KEY_RIGHT          = "D";
    private static final String DEFAULT_KEY_UP             = "W";
    private static final String DEFAULT_KEY_DOWN           = "S";
    private static final String DEFAULT_PLAYER_TEXTURE     = "reimu.png";
    private static final double DEFAULT_MUSIC_VOLUME       = 1.0;
    private static final double DEFAULT_SFX_VOLUME         = 1.0;
    private static final int    DEFAULT_MAX_FPS            = 0;
    private static final boolean DEFAULT_VSYNC_ENABLED     = true;
    private static final double DEFAULT_BACKGROUND_DIM     = 0.6;

    private static final int    DEFAULT_SPINNER_BULLET_COUNT   = 11;
    private static final double DEFAULT_SPINNER_BULLET_SPEED   = 2.0;
    private static final long   DEFAULT_SPINNER_FIRE_INTERVAL  = 100;
    private static final double DEFAULT_SPINNER_ROTATION_SPEED = 0.1063495408; // ~Math.PI/27

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
        // apply defaults
        changed |= addDefault("playerSpeed",       Double.toString(DEFAULT_PLAYER_SPEED));
        changed |= addDefault("bulletSpeed",       Double.toString(DEFAULT_BULLET_SPEED));
        changed |= addDefault("slowSpeed",         Double.toString(DEFAULT_SLOW_SPEED));
        changed |= addDefault("screenWidth",       Integer.toString(DEFAULT_SCREEN_WIDTH));
        changed |= addDefault("screenHeight",      Integer.toString(DEFAULT_SCREEN_HEIGHT));
        changed |= addDefault("hitboxRadius",      Integer.toString(DEFAULT_HITBOX_RADIUS));
        changed |= addDefault("keyLeft",           DEFAULT_KEY_LEFT);
        changed |= addDefault("keyRight",          DEFAULT_KEY_RIGHT);
        changed |= addDefault("keyUp",             DEFAULT_KEY_UP);
        changed |= addDefault("keyDown",           DEFAULT_KEY_DOWN);
        changed |= addDefault("playerTexture",     DEFAULT_PLAYER_TEXTURE);
        changed |= addDefault("musicVolume",       Double.toString(DEFAULT_MUSIC_VOLUME));
        changed |= addDefault("sfxVolume",         Double.toString(DEFAULT_SFX_VOLUME));
        changed |= addDefault("maxFPS",            Integer.toString(DEFAULT_MAX_FPS));
        changed |= addDefault("vsync",             Boolean.toString(DEFAULT_VSYNC_ENABLED));
        changed |= addDefault("backgroundDim",     Double.toString(DEFAULT_BACKGROUND_DIM));
        changed |= addDefault("spinnerBulletCount",    Integer.toString(DEFAULT_SPINNER_BULLET_COUNT));
        changed |= addDefault("spinnerBulletSpeed",    Double.toString(DEFAULT_SPINNER_BULLET_SPEED));
        changed |= addDefault("spinnerFireInterval",   Long.toString(DEFAULT_SPINNER_FIRE_INTERVAL));
        changed |= addDefault("spinnerRotationSpeed",  Double.toString(DEFAULT_SPINNER_ROTATION_SPEED));

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

    private static double parseDouble(String key, double def) {
        try {
            return Double.parseDouble(props.getProperty(key, Double.toString(def)));
        } catch (NumberFormatException e) {
            return def;
        }
    }

    public static double getPlayerSpeed()       { return parseDouble("playerSpeed", DEFAULT_PLAYER_SPEED); }
    public static double getBulletSpeed()       { return parseDouble("bulletSpeed", DEFAULT_BULLET_SPEED); }
    public static double getSlowSpeed()         { return parseDouble("slowSpeed",   DEFAULT_SLOW_SPEED); }
    public static int    getScreenWidth()       { return Integer.parseInt(props.getProperty("screenWidth")); }
    public static int    getScreenHeight()      { return Integer.parseInt(props.getProperty("screenHeight")); }
    public static int    getHitboxRadius()      { return Integer.parseInt(props.getProperty("hitboxRadius")); }
    public static int    getKeyCode(String k)   { /* unchanged */
        String key = props.getProperty(k, "").trim().toUpperCase();
        switch (key) {
            case "LEFT":  return KeyEvent.VK_LEFT;
            case "RIGHT": return KeyEvent.VK_RIGHT;
            case "UP":    return KeyEvent.VK_UP;
            case "DOWN":  return KeyEvent.VK_DOWN;
            case "SHIFT": return KeyEvent.VK_SHIFT;
            default:
                if (key.length() == 1) return KeyEvent.getExtendedKeyCodeForChar(key.charAt(0));
                try { return Integer.parseInt(key); }
                catch (Exception e) { return KeyEvent.getExtendedKeyCodeForChar(key.charAt(0)); }
        }
    }
    public static BufferedImage getPlayerTexture() { return playerTexture; }
    public static float  getMusicVolume()          { return (float)parseDouble("musicVolume", DEFAULT_MUSIC_VOLUME); }
    public static float  getSfxVolume()            { return (float)parseDouble("sfxVolume",   DEFAULT_SFX_VOLUME); }
    public static int    getMaxFPS()               { return Integer.parseInt(props.getProperty("maxFPS", Integer.toString(DEFAULT_MAX_FPS))); }
    public static boolean isVSyncEnabled()         { return Boolean.parseBoolean(props.getProperty("vsync", Boolean.toString(DEFAULT_VSYNC_ENABLED))); }
    public static float  getBackgroundDim()        { return (float)parseDouble("backgroundDim", DEFAULT_BACKGROUND_DIM); }

    public static int    getSpinnerBulletCount()   { return Integer.parseInt(props.getProperty("spinnerBulletCount", Integer.toString(DEFAULT_SPINNER_BULLET_COUNT))); }
    public static double getSpinnerBulletSpeed()   { return parseDouble("spinnerBulletSpeed", DEFAULT_SPINNER_BULLET_SPEED); }
    public static long   getSpinnerFireInterval()  { return Long.parseLong(props.getProperty("spinnerFireInterval", Long.toString(DEFAULT_SPINNER_FIRE_INTERVAL))); }
    public static double getSpinnerRotationSpeed() { return parseDouble("spinnerRotationSpeed", DEFAULT_SPINNER_ROTATION_SPEED); }
}
