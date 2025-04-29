import java.awt.*;
import java.awt.geom.Path2D;
import java.awt.AlphaComposite;
import java.awt.BasicStroke;
import java.awt.Composite;
import java.util.List;

public class SliderLaser {
    private final List<Point> points;
    private final long appearTime;
    private final long fullOpacityTime;
    private final long endTime;

    // cached paths
    private Path2D fullPath = null;
    private Path2D collisionPath = null;
    private static final BasicStroke LASER_STROKE = new BasicStroke(2f);

    public SliderLaser(List<Point> ctrlPts, long startTime, double approachTime, double sliderDuration) {
        this.points          = ctrlPts;
        this.fullOpacityTime = startTime;
        this.appearTime      = (long)(startTime - approachTime);
        this.endTime         = (long)(startTime + sliderDuration);
    }

    /** Когда лазер начинает наносить урон */
    public long getFullOpacityTime() {
        return fullOpacityTime;
    }

    /** Путь для рендера (с экстендом) */
    public Path2D getPath(int screenW, int screenH, long elapsed) {
        if (elapsed < appearTime || elapsed > endTime || points.size() < 2) return null;
        if (fullPath == null) buildFullPath(screenW, screenH);
        return fullPath;
    }

    /** Путь для коллизий (без экстендов) */
    public Path2D getCollisionPath(int screenW, int screenH, long elapsed) {
        if (elapsed < fullOpacityTime || elapsed > endTime || points.size() < 2) return null;
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

    public float getOpacity(long elapsed) {
        if (elapsed < appearTime) return 0f;
        if (elapsed < fullOpacityTime)
            return (elapsed - appearTime) / (float)(fullOpacityTime - appearTime);
        return 1f;
    }

    public void render(Graphics2D g, int screenW, int screenH, long elapsed) {
        Path2D path = getPath(screenW, screenH, elapsed);
        if (path == null) return;
        float alpha = getOpacity(elapsed);
        Composite orig = g.getComposite();
        g.setComposite(AlphaComposite.getInstance(AlphaComposite.SRC_OVER, alpha));
        g.setStroke(LASER_STROKE);
        g.setColor(Color.CYAN);
        g.draw(path);
        g.setComposite(orig);
    }
}
