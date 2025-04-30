import java.awt.AlphaComposite;
import java.awt.Composite;
import java.awt.Font;
import java.awt.Graphics2D;
import java.awt.image.BufferedImage;
import java.io.File;
import java.io.IOException;
import java.util.List;
import javax.imageio.ImageIO;

public class Bomb {
    // === Константы ===
    private static final int    MAX_BOMBS = 5;
    private static final long   DURATION  = 4000L; // ms
    private static final float  MAX_ALPHA = 0.5f;  // 50%
    // ==================

    // Списки и параметры экрана
    private static List<Bullet>        bullets;
    private static List<SliderLaser>   sliderLasers;
    private static List<SpinnerManager> spinnerManagers;
    private static int screenW, screenH;

    // Состояние
    private static int    bombsLeft;
    private static boolean active;
    private static long   startTime;
    private static double centerX, centerY;

    // Графика
    private static BufferedImage image;
    private static final Font    hudFont = new Font("Arial", Font.BOLD, 14);

    /**
     * Вызывать один раз в Game(): передаём списки и размеры экрана.
     */
    public static void init(
        List<Bullet> b,
        List<SliderLaser> sl,
        List<SpinnerManager> sp,
        int w,
        int h
    ) {
        bullets        = b;
        sliderLasers   = sl;
        spinnerManagers= sp;
        screenW        = w;
        screenH        = h;
        bombsLeft      = MAX_BOMBS;
        active         = false;
        try {
            image = ImageIO.read(new File("bomb.png"));
        } catch (IOException e) {
            e.printStackTrace();
            image = null;
        }
    }

    /**
     * Активировать бомбу: удаляем пули в радиусе, запускаем таймер.
     * Лазеры и спиннеры больше не чистятся целиком.
     */
    public static void activate(double cx, double cy, long now) {
        if (bombsLeft <= 0 || active) return;
        bombsLeft--;
        active    = true;
        startTime = now;
        centerX   = cx;
        centerY   = cy;

        // радиус = половина ширины экрана
        double r2 = (screenW / 2.0) * (screenW / 2.0);
        bullets.removeIf(b -> {
            double dx = b.getX() - cx;
            double dy = b.getY() - cy;
            return dx*dx + dy*dy <= r2;
        });
    }

    /** Останавливает эффект через DURATION */
    public static void update(long now) {
        if (!active) return;
        if (now - startTime >= DURATION) {
            active = false;
        }
    }

    /** true, если бомба всё ещё идёт */
    public static boolean isActive() {
        return active;
    }

    /**
     * Рисует HUD и fullscreen-эффект.
     * Вызывать в конце renderFrame: Bomb.render(g, elapsed);
     */
    public static void render(Graphics2D g, long now) {
        // 1) HUD
        g.setFont(hudFont);
        g.setColor(java.awt.Color.WHITE);
        g.drawString("Bombs: " + bombsLeft, screenW - 100, 40);

        // 2) fullscreen-эффект
        if (!active || image == null) return;
        float t = (now - startTime) / (float)DURATION;
        float alpha = t < 0.5f
            ? MAX_ALPHA * (t / 0.5f)
            : MAX_ALPHA * (1 - (t - 0.5f) / 0.5f);
        Composite old = g.getComposite();
        g.setComposite(AlphaComposite.getInstance(AlphaComposite.SRC_OVER, alpha));
        g.drawImage(image, 0, 0, screenW, screenH, null);
        g.setComposite(old);
    }
}
