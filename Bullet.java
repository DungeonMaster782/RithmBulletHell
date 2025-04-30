import java.util.Random;

public class Bullet {
    private double x, y;
    private final int size;
    private boolean spinner = false;
    private static final Random RNG = new Random();

    /** скорость по осям в пикселях в секунду */
    private double vx, vy;

    public Bullet(int size) {
        this.size = size;
    }

    public void setSpinner(boolean spinner) {
        this.spinner = spinner;
    }

    public boolean isSpinner() {
        return spinner;
    }

    /**
     * Инициализация случайного спавна.
     * @param screenWidth ширина экрана в пикселях
     * @param targetX цель по X
     * @param targetY цель по Y
     * @param speed скорость движения (px/с)
     * @param approachTime не используется в новой логике, но оставлено для совместимости
     */
    public void initRandom(int screenWidth, double targetX, double targetY, double speed, long approachTime) {
        int side = RNG.nextInt(3);
        switch (side) {
            case 1:
                x = -size;
                y = RNG.nextDouble() * Config.getScreenHeight();
                break;
            case 2:
                x = screenWidth + size;
                y = RNG.nextDouble() * Config.getScreenHeight();
                break;
            default:
                x = RNG.nextDouble() * screenWidth;
                y = -size;
        }
        // вычисляем единичный вектор направления к цели
        double dirX = targetX - x;
        double dirY = targetY - y;
        double len = Math.hypot(dirX, dirY);
        if (len != 0) {
            dirX /= len;
            dirY /= len;
        }
        // задаём скорость по осям (px/с)
        vx = dirX * speed;
        vy = dirY * speed;
    }

    /**
     * Инициализация пули в заданной точке.
     * @param spawnX координата X спавна
     * @param spawnY координата Y спавна
     * @param targetX цель по X
     * @param targetY цель по Y
     * @param speed скорость движения (px/с)
     * @param approachTime не используется в новой логике
     */
    public void initAt(int spawnX, int spawnY, double targetX, double targetY, double speed, long approachTime) {
        x = spawnX;
        y = spawnY;
        double dirX = targetX - x;
        double dirY = targetY - y;
        double len = Math.hypot(dirX, dirY);
        if (len != 0) {
            dirX /= len;
            dirY /= len;
        }
        vx = dirX * speed;
        vy = dirY * speed;
    }

    /**
     * Обновление позиции и проверка выхода за границы экрана.
     * @param screenWidth ширина экрана
     * @param screenHeight высота экрана
     * @param dtSec время кадра в секундах
     * @return true, если пуля вышла за экран и должна быть удалена
     */
    public boolean updateAndCheck(int screenWidth, int screenHeight, double dtSec) {
        x += vx * dtSec;
        y += vy * dtSec;
        return y > screenHeight + size
            || x < -size
            || x > screenWidth + size;
    }

    public double getX() { return x; }
    public double getY() { return y; }
    public int getSize()  { return size; }
}
