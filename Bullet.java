import java.util.Random;

/**
 * Represents a bullet in the game, handling its movement and lifecycle.
 */
public class Bullet {
    private double x, y;   // current position
    private double dx, dy; // velocity components
    private final int size;
    private static final Random RNG = new Random();

    /**
     * @param size diameter of the bullet in pixels
     */
    public Bullet(int size) {
        this.size = size;
    }

    /**
     * Инициализация пули из рандомного X по верхней границе экрана.
     * @param screenWidth ширина экрана
     * @param targetX координата цели по X
     * @param targetY координата цели по Y
     * @param speed скорость движения
     * @param approachTime время (ms), за которое пуля добегает до цели
     */
    public void initRandom(int screenWidth, double targetX, double targetY, double speed, long approachTime) {
        this.x = RNG.nextDouble() * screenWidth;
        this.y = -size;
        this.dx = (targetX - x) / approachTime * speed;
        this.dy = (targetY - y) / approachTime * speed;
    }

    /**
     * Инициализация пули из заданной точки.
     * @param spawnX стартовая координата X
     * @param spawnY стартовая координата Y
     * @param targetX координата цели по X
     * @param targetY координата цели по Y
     * @param speed скорость движения
     * @param approachTime время (ms), за которое пуля добегает до цели
     */
    public void initAt(int spawnX, int spawnY, double targetX, double targetY, double speed, long approachTime) {
        this.x = spawnX;
        this.y = spawnY;
        this.dx = (targetX - x) / approachTime * speed;
        this.dy = (targetY - y) / approachTime * speed;
    }

    /**
     * Обновляет положение пули и проверяет, вышла ли она за границы экрана.
     * @param screenWidth ширина экрана
     * @param screenHeight высота экрана
     * @return true, если пуля вышла за границы и должна быть удалена
     */
    public boolean updateAndCheck(int screenWidth, int screenHeight) {
        x += dx;
        y += dy;
        return y > screenHeight + size || x < -size || x > screenWidth + size;
    }

    public double getX() { return x; }
    public double getY() { return y; }
    public int getSize()   { return size; }
}
