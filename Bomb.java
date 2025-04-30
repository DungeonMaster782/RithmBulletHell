import java.awt.AlphaComposite;
import java.awt.Composite;
import java.awt.Font;
import java.awt.Graphics2D;
import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.util.List;
import javax.imageio.ImageIO;
import javax.sound.sampled.*;
import java.net.URL;

/**
 * Bomb управляет эффектом "бомбы": удаляет пули в радиусе,
 * рисует fullscreen-эффект и HUD, а также проигрывает звук при активации.
 * Громкость эффекта можно настраивать через Config.getSfxVolume() или setBombVolume().
 */
public class Bomb {
    // === Константы ===
    private static final int    MAX_BOMBS = 5;
    private static final long   DURATION  = 4000L; // ms полного эффекта
    private static final float  MAX_ALPHA = 0.5f;
    // ==================

    // Списки игровых объектов и параметры экрана
    private static List<Bullet>        bullets;
    private static List<SliderLaser>   sliderLasers;
    private static List<SpinnerManager> spinnerManagers;
    private static int screenW, screenH;

    // Состояние бомбы
    private static int    bombsLeft;
    private static boolean active;
    private static long   startTime;
    private static double centerX, centerY;

    // Графика
    private static BufferedImage image;
    private static final Font    hudFont = new Font("Arial", Font.BOLD, 14);

    // Звук активации бомбы
    private static byte[] bombSoundData;
    private static AudioFormat bombSoundFormat;
    private static int bombSoundLength;
    private static float bombVolume = Config.getSfxVolume();

    /** Устанавливает громкость звука бомбы [0.0..1.0] */
    public static void setBombVolume(float v) {
        bombVolume = Math.max(0f, Math.min(1f, v));
        Bomb.setBombVolume(1.8f);
    }

    /** Возвращает текущую громкость звука бомбы */
    public static float getBombVolume() {
        return bombVolume;
    }

    // Загрузка звука из ресурсов
    static {
        try {
            URL url = Bomb.class.getResource("bomb_activate.wav");
            if (url != null) {
                try (AudioInputStream ais = AudioSystem.getAudioInputStream(url);
                     ByteArrayOutputStream baos = new ByteArrayOutputStream()) {
                    bombSoundFormat = ais.getFormat();
                    byte[] buffer = new byte[4096];
                    int bytesRead;
                    while ((bytesRead = ais.read(buffer)) != -1) {
                        baos.write(buffer, 0, bytesRead);
                    }
                    bombSoundData = baos.toByteArray();
                    bombSoundLength = bombSoundData.length;
                }
            } else {
                System.err.println("Bomb sound resource not found: /bomb_activate.wav");
                bombSoundData = null;
            }
        } catch (UnsupportedAudioFileException | IOException e) {
            e.printStackTrace();
            bombSoundData = null;
        }
    }

    /**
     * Инициализация: передать ссылки на списки и размеры экрана.
     * Также обновляет громкость звука из конфигурации.
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
        // обновляем громкость по конфигу
        bombVolume = Config.getSfxVolume();
        try {
            image = ImageIO.read(Bomb.class.getResource("/bomb.png"));
        } catch (IOException | IllegalArgumentException e) {
            System.err.println("Bomb image resource not found: /bomb.png");
            image = null;
        }
    }

    /**
     * Активировать бомбу: удаляет пули в радиусе, запускает таймер и звук.
     */
    public static void activate(double cx, double cy, long now) {
        if (bombsLeft <= 0 || active) return;
        bombsLeft--;
        active    = true;
        startTime = now;
        centerX   = cx;
        centerY   = cy;
        // удаляем пули в радиусе половины ширины экрана
        double r2 = (screenW / 2.0) * (screenW / 2.0);
        bullets.removeIf(b -> {
            double dx = b.getX() - cx;
            double dy = b.getY() - cy;
            return dx*dx + dy*dy <= r2;
        });
        // проигрываем звук
        playBombSound();
    }

    /** Обновляет состояние бомбы (деактивация по таймеру). */
    public static void update(long now) {
        if (!active) return;
        if (now - startTime >= DURATION) {
            active = false;
        }
    }

    /** Проверка, активна ли бомба. */
    public static boolean isActive() {
        return active;
    }

    /**
     * Рендер HUD и fullscreen-эффекта. Вызывать после основного рендера.
     */
    public static void render(Graphics2D g, long now) {
        // HUD
        g.setFont(hudFont);
        g.setColor(java.awt.Color.WHITE);
        g.drawString("Bombs: " + bombsLeft, screenW - 100, 40);
        // Fullscreen-эффект
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

    // Вспомогательный метод для воспроизведения звука бомбы
    private static void playBombSound() {
        if (bombSoundData == null) return;
        try {
            Clip clip = (Clip) AudioSystem.getLine(
                new DataLine.Info(Clip.class, bombSoundFormat)
            );
            clip.open(bombSoundFormat, bombSoundData, 0, bombSoundLength);
            FloatControl lc = (FloatControl) clip.getControl(FloatControl.Type.MASTER_GAIN);
            float dB = (float) (20 * Math.log10(bombVolume <= 0f ? 0.0001f : bombVolume));
            lc.setValue(dB);
            clip.start();
        } catch (LineUnavailableException e) {
            e.printStackTrace();
        }
    }
}
