// SpinnerManager.java
import java.util.Deque;
import java.util.List;

/**
 * Управляет спиральной эмиссией пуль из спиннера в центре.
 * Параметры (количество, скорость, интервал, скорость вращения)
 * берутся из Config.
 */
public class SpinnerManager {
    private final int x, y;
    private final long startTime, endTime;
    private double baseAngle;
    private long lastEmit;
    private final double angleStep;
    private final long fireInterval;
    private final double bulletSpeed;
    private static final double RADIUS = 100.0;

    public SpinnerManager(int x, int y, long startTime, long endTime) {
        this.x = x;
        this.y = y;
        this.startTime = startTime;
        this.endTime   = endTime;
        this.baseAngle = 0.0;
        this.fireInterval = Config.getSpinnerFireInterval();
        this.lastEmit  = startTime - fireInterval;
        this.angleStep = Config.getSpinnerRotationSpeed();
        this.bulletSpeed = Config.getSpinnerBulletSpeed();
    }

    /**
     * Вызывается каждый кадр в Game.update().
     * @param elapsed текущее время в мс
     * @param bullets список живых пуль
     * @param pool пул свободных объектов Bullet
     * @param bulletSize размер пули в пикселях
     * @return false, когда спиннер завершил работу
     */
    public boolean update(long elapsed, List<Bullet> bullets, Deque<Bullet> pool, int bulletSize) {
        if (elapsed < startTime) return true;
        if (elapsed > endTime)   return false;

        if (elapsed - lastEmit >= fireInterval) {
            int count = Config.getSpinnerBulletCount();
            for (int i = 0; i < count; i++) {
                double ang = baseAngle + i * (2 * Math.PI / count);
                double tx = x + Math.cos(ang) * RADIUS;
                double ty = y + Math.sin(ang) * RADIUS;
                Bullet b = pool.pollFirst();
                if (b == null) b = new Bullet(bulletSize);
                b.setSpinner(true);
                b.initAt(x, y, tx, ty, bulletSpeed, fireInterval * 2);
                bullets.add(b);
            }
            baseAngle += angleStep;
            lastEmit = elapsed;
        }
        return true;
    }
}
