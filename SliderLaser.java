import java.awt.*;
import java.awt.geom.Path2D;
import java.awt.geom.Rectangle2D;
import java.awt.AlphaComposite;
import java.awt.BasicStroke;
import java.awt.Composite;
import java.awt.Shape;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.net.URL;
import java.util.List;
import javax.sound.sampled.AudioFormat;
import javax.sound.sampled.AudioInputStream;
import javax.sound.sampled.AudioSystem;
import javax.sound.sampled.Clip;
import javax.sound.sampled.FloatControl;
import javax.sound.sampled.DataLine;
import javax.sound.sampled.LineUnavailableException;
import javax.sound.sampled.UnsupportedAudioFileException;

/**
 * SliderLaser отображает лазер-путь с фазой превью (синий), фазой опасности (фиолетовый)
 * и плавным исчезанием, а также проигрывает звук при начале опасной фазы.
 * Поддерживает настройку громкости и одновременное воспроизведение нескольких звуков,
 * при этом звук проигрывается один раз на переход в опасную фазу.
 */
public class SliderLaser {
    private final List<Point> points;
    private final long appearTime;
    private final long fullOpacityTime;
    private final long endTime;
    private final long fadeDuration;
    private final long fadeOutDuration;
    private final long fadeOutEndTime;

    private Path2D fullPath;
    private Path2D collisionPath;
    private static final BasicStroke LASER_STROKE = new BasicStroke(9f);

    // флаг, чтобы звук проигрывался только один раз при переходе в опасную фазу
    private boolean soundPlayed;

    // Буфер звуковых данных для создания новых клипов
    private static byte[] soundData;
    private static AudioFormat soundFormat;
    private static int soundBufferLength;
    private static float volume = 1.2f; // по умолчанию 50%

    /** Устанавливает уровень громкости звуков эффекта [0.0 .. 1.0] */
    public static void setVolume(float v) {
        volume = Math.max(0f, Math.min(1f, v));
    }

    static {
        try {
            URL url = SliderLaser.class.getResource("laser_danger.wav");
            try (AudioInputStream ais = AudioSystem.getAudioInputStream(url);
                 ByteArrayOutputStream baos = new ByteArrayOutputStream()) {
                soundFormat = ais.getFormat();
                byte[] buffer = new byte[4096];
                int read;
                while ((read = ais.read(buffer)) != -1) {
                    baos.write(buffer, 0, read);
                }
                soundData = baos.toByteArray();
                soundBufferLength = soundData.length;
            }
        } catch (IOException | UnsupportedAudioFileException e) {
            e.printStackTrace();
            soundData = null;
        }
    }

    /**
     * @param ctrlPts точки контроля пути
     * @param startTime ms, начало опасной фазы
     * @param previewMs длительность превью в ms
     * @param sliderDuration длительность опасной фазы в ms
     */
    public SliderLaser(List<Point> ctrlPts, long startTime, double previewMs, double sliderDuration) {
        this.points = ctrlPts;
        this.fullOpacityTime = startTime;
        this.appearTime = (long) (startTime - previewMs);
        this.endTime = (long) (startTime + sliderDuration);
        this.fadeDuration = fullOpacityTime - appearTime;
        this.fadeOutDuration = fadeDuration / 4;
        this.fadeOutEndTime = endTime + fadeOutDuration;
        this.fullPath = null;
        this.collisionPath = null;
        this.soundPlayed = false;
    }

    public Path2D getPath(int screenW, int screenH, long elapsed) {
        if (elapsed < appearTime || elapsed > fadeOutEndTime || points == null || points.size() < 2)
            return null;
        if (fullPath == null) buildFullPath(screenW, screenH);
        return fullPath;
    }

    public Path2D getCollisionPath(int screenW, int screenH, long elapsed) {
        if (elapsed < fullOpacityTime || elapsed > endTime || points == null || points.size() < 2)
            return null;
        if (collisionPath == null) buildCollisionPath();
        return collisionPath;
    }

    private void buildFullPath(int screenW, int screenH) {
        double ext = Math.max(screenW, screenH) * 1.5;
        Path2D path = new Path2D.Double();
        Point p0 = points.get(0);
        Point p1 = points.get(1);
        double dx0 = p1.x - p0.x, dy0 = p1.y - p0.y;
        double len0 = Math.hypot(dx0, dy0);
        dx0 /= len0; dy0 /= len0;
        path.moveTo(p0.x - dx0 * ext, p0.y - dy0 * ext);
        for (int i = 0, n = points.size(); i < n; i++) {
            Point curr = points.get(i);
            if (i < n - 1) {
                Point next = points.get(i + 1);
                double mx = (curr.x + next.x) / 2.0;
                double my = (curr.y + next.y) / 2.0;
                path.quadTo(curr.x, curr.y, mx, my);
            } else {
                path.lineTo(curr.x, curr.y);
                Point prev = points.get(n - 2);
                double dxn = curr.x - prev.x, dyn = curr.y - prev.y;
                double lenn = Math.hypot(dxn, dyn);
                dxn /= lenn; dyn /= lenn;
                path.lineTo(curr.x + dxn * ext, curr.y + dyn * ext);
            }
        }
        fullPath = path;
    }

    private void buildCollisionPath() {
        Path2D path = new Path2D.Double();
        Point p0 = points.get(0);
        path.moveTo(p0.x, p0.y);
        for (int i = 1, n = points.size(); i < n; i++) {
            Point curr = points.get(i);
            if (i < n - 1) {
                Point next = points.get(i + 1);
                double mx = (curr.x + next.x) / 2.0;
                double my = (curr.y + next.y) / 2.0;
                path.quadTo(curr.x, curr.y, mx, my);
            } else {
                path.lineTo(curr.x, curr.y);
            }
        }
        collisionPath = path;
    }

    public float getOpacity(long elapsed) {
        if (elapsed < appearTime) return 0f;
        if (elapsed < fullOpacityTime) return (elapsed - appearTime) / (float) fadeDuration;
        if (elapsed <= endTime) return 1f;
        if (elapsed <= fadeOutEndTime) return 1f - (elapsed - endTime) / (float) fadeOutDuration;
        return 0f;
    }

    public void render(Graphics2D g, int screenW, int screenH, long elapsed) {
        Path2D path = getPath(screenW, screenH, elapsed);
        if (path == null) return;

        float alpha = getOpacity(elapsed);
        Composite orig = g.getComposite();
        g.setComposite(AlphaComposite.getInstance(AlphaComposite.SRC_OVER, alpha));
        g.setStroke(LASER_STROKE);

        // Цветовая фаза и одномоментный звук
        if (elapsed < fullOpacityTime) {
            g.setColor(Color.CYAN);
        } else if (elapsed <= endTime) {
            g.setColor(new Color(170, 0, 255));
            if (!soundPlayed) {
                playDangerSound();
                soundPlayed = true;
            }
        } else {
            g.setColor(Color.CYAN);
        }

        g.draw(path);
        g.setComposite(orig);
    }

    /** Воспроизводит звук начала опасной фазы с учётом громкости */
    private void playDangerSound() {
        if (soundData == null) return;
        try {
            Clip clip = (Clip) AudioSystem.getLine(new DataLine.Info(Clip.class, soundFormat));
            clip.open(soundFormat, soundData, 0, soundBufferLength);
            FloatControl volCtrl = (FloatControl) clip.getControl(FloatControl.Type.MASTER_GAIN);
            float dB = (float) (20 * Math.log10(volume <= 0f ? 0.0001f : volume));
            volCtrl.setValue(dB);
            clip.start();
        } catch (LineUnavailableException e) {
            e.printStackTrace();
        }
    }

    public Shape getCollisionShape(int screenW, int screenH, long elapsed) {
        Path2D cp = getCollisionPath(screenW, screenH, elapsed);
        if (cp == null) return null;
        return LASER_STROKE.createStrokedShape(cp);
    }
}
