// Config.java
import java.util.Properties;
import java.io.*;
import java.awt.event.KeyEvent;
import java.awt.image.BufferedImage;
import javax.imageio.ImageIO;

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
        changed |= addDefault("playerSpeed",  "5");
        changed |= addDefault("bulletSpeed",  "4");
        changed |= addDefault("screenWidth",  "800");
        changed |= addDefault("screenHeight", "600");
        changed |= addDefault("hitboxRadius", "10");
        changed |= addDefault("slowSpeed",    "2");
        changed |= addDefault("keyLeft",      "A");
        changed |= addDefault("keyRight",     "D");
        changed |= addDefault("keyUp",        "W");
        changed |= addDefault("keyDown",      "S");
        changed |= addDefault("playerTexture","");   // путь к спрайту героини

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
        String path = props.getProperty("playerTexture","").trim();
        // обратная совместимость: если вдруг остался старый ключ
        if (path.isEmpty() && props.containsKey("hitboxTexture")) {
            path = props.getProperty("hitboxTexture","").trim();
        }
        if (!path.isEmpty()) {
            try {
                playerTexture = ImageIO.read(new File(path));
            } catch (IOException e) {
                System.err.println("Config: failed to load texture `" + path + "`: " + e.getMessage());
            }
        }
    }

    public static int getPlayerSpeed()    { return Integer.parseInt(props.getProperty("playerSpeed")); }
    public static double getBulletSpeed() { return Double.parseDouble(props.getProperty("bulletSpeed")); }
    public static int getSlowSpeed()      { return Integer.parseInt(props.getProperty("slowSpeed")); }
    public static int getScreenWidth()    { return Integer.parseInt(props.getProperty("screenWidth")); }
    public static int getScreenHeight()   { return Integer.parseInt(props.getProperty("screenHeight")); }
    public static int getHitboxRadius()   { return Integer.parseInt(props.getProperty("hitboxRadius")); }
    public static int getKeyCode(String keyProp) {
        String k = props.getProperty(keyProp,"").trim().toUpperCase();
        switch (k) {
            case "LEFT":  return KeyEvent.VK_LEFT;
            case "RIGHT": return KeyEvent.VK_RIGHT;
            case "UP":    return KeyEvent.VK_UP;
            case "DOWN":  return KeyEvent.VK_DOWN;
            case "SHIFT": return KeyEvent.VK_SHIFT;
            default:
                if (k.length()==1) return KeyEvent.getExtendedKeyCodeForChar(k.charAt(0));
                try { return Integer.parseInt(k); }
                catch(Exception e){}
                return KeyEvent.getExtendedKeyCodeForChar(k.charAt(0));
        }
    }
    public static BufferedImage getPlayerTexture() {
        return playerTexture;
    }
}
