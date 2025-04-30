import java.util.Random;

public class Bullet {
    private double x, y;
    private double dx, dy;
    private final int size;
    private boolean spinner = false;
    private static final Random RNG = new Random();

    public Bullet(int size) {
        this.size = size;
    }

    public void setSpinner(boolean spinner) {
        this.spinner = spinner;
    }

    public boolean isSpinner() {
        return spinner;
    }

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
        dx = (targetX - x) / approachTime * speed;
        dy = (targetY - y) / approachTime * speed;
    }

    public void initAt(int spawnX, int spawnY, double targetX, double targetY, double speed, long approachTime) {
        x = spawnX;
        y = spawnY;
        dx = (targetX - x) / approachTime * speed;
        dy = (targetY - y) / approachTime * speed;
    }

    public boolean updateAndCheck(int screenWidth, int screenHeight) {
        x += dx;
        y += dy;
        return y > screenHeight + size || x < -size || x > screenWidth + size;
    }

    public double getX() { return x; }
    public double getY() { return y; }
    public int getSize() { return size; }
}
