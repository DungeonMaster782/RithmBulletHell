import java.awt.*;
import java.awt.geom.Path2D;
import java.awt.AlphaComposite;
import java.awt.BasicStroke;
import java.awt.Composite;
import java.awt.Shape;
import java.util.List;


public class SliderLaser {
    private final List<Point> points;
    private final long appearTime;         // время начала фазы появления
    private final long fullOpacityTime;    // время, когда достигается полная непрозрачность
    private final long endTime;            // время конца урона
    private final long fadeDuration;       // длительность fade-in
    private final long fadeOutDuration;    // длительность fade-out (сокращена относительно fade-in)
    private final long fadeOutEndTime;     // конец fade-out = endTime + fadeOutDuration
    // cached paths
    private Path2D fullPath = null;
    private Path2D collisionPath = null;
    private static final BasicStroke LASER_STROKE = new BasicStroke(5f);
    private static final float COLLISION_THRESHOLD = 0.5f;

    public SliderLaser(List<Point> ctrlPts, long startTime,
                       double approachTime, double sliderDuration) {
        this.points          = ctrlPts;
        this.fullOpacityTime = startTime;
        this.appearTime      = (long)(startTime - approachTime);
        this.endTime         = (long)(startTime + sliderDuration);

        this.fadeDuration    = fullOpacityTime - appearTime;
        this.fadeOutDuration = fadeDuration / 4;          // например, в 2 раза короче
        this.fadeOutEndTime  = endTime + fadeOutDuration;
    }

    /** Когда лазер начинает наносить урон */
    public long getFullOpacityTime() {
        return fullOpacityTime;
    }

    /** Путь для рендера (fade-in, полная фаза и fade-out) */
    public Path2D getPath(int screenW, int screenH, long elapsed) {
        if (elapsed < appearTime || elapsed > fadeOutEndTime || points.size() < 2)
            return null;
        if (fullPath == null) buildFullPath(screenW, screenH);
        return fullPath;
    }

    /** Путь для коллизий (только фаза урона) */
    public Path2D getCollisionPath(int screenW, int screenH, long elapsed) {
        if (elapsed < fullOpacityTime || elapsed > endTime || points.size() < 2)
            return null;
        if (collisionPath == null) buildCollisionPath();
        return collisionPath;
    }

    private void buildFullPath(int screenW, int screenH) {
        double ext = Math.max(screenW, screenH) * 1.5;
        Point p0 = points.get(0), p1 = points.get(1);
        double dx0 = p1.x - p0.x, dy0 = p1.y - p0.y;
        double len0 = Math.hypot(dx0, dy0);
        dx0 /= len0; dy0 /= len0;
        double sx = p0.x - dx0 * ext, sy = p0.y - dy0 * ext;

        Path2D path = new Path2D.Double();
        path.moveTo(sx, sy);
        int n = points.size();
        for (int i = 0; i < n; i++) {
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
                double ex = curr.x + dxn * ext, ey = curr.y + dyn * ext;
                path.lineTo(ex, ey);
            }
        }
        fullPath = path;
    }

    private void buildCollisionPath() {
        Path2D path = new Path2D.Double();
        Point first = points.get(0);
        path.moveTo(first.x, first.y);
        int n = points.size();
        for (int i = 1; i < n; i++) {
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

    /** Определяем прозрачность: fade-in → 1 → fade-out */
    public float getOpacity(long elapsed) {
        if (elapsed < appearTime)
            return 0f;
        if (elapsed < fullOpacityTime)
            return (elapsed - appearTime) / (float)fadeDuration;
        if (elapsed <= endTime)
            return 1f;
        if (elapsed <= fadeOutEndTime)
            return 1f - (elapsed - endTime) / (float)fadeOutDuration;
        return 0f;
    }

    public void render(Graphics2D g, int screenW, int screenH, long elapsed) {
        Path2D path = getPath(screenW, screenH, elapsed);
        if (path == null) return;

        float alpha = getOpacity(elapsed);
        Composite origComposite = g.getComposite();
        g.setComposite(AlphaComposite.getInstance(AlphaComposite.SRC_OVER, alpha));
        g.setStroke(LASER_STROKE);
        // если уже можно получить урон — рисуем фиолетовым, иначе — цианом
        if (alpha >= COLLISION_THRESHOLD) {
            g.setColor(new Color(170, 0, 255)); // purple
        } else {
            g.setColor(Color.CYAN);
        }
        g.draw(path);
        g.setComposite(origComposite);
    }
    public Shape getCollisionShape(int screenW, int screenH, long elapsed) {
        Path2D path = getPath(screenW, screenH, elapsed);
        if (path == null) return null;
        // начинаем коллизию уже при 50% непрозрачности
        if (getOpacity(elapsed) < COLLISION_THRESHOLD) return null;
        return LASER_STROKE.createStrokedShape(path);
    }
}
