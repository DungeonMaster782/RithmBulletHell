import java.awt.Canvas;
import java.awt.Color;
import java.awt.Composite;
import java.awt.AlphaComposite;
import java.awt.BasicStroke;
import java.awt.Dimension;
import java.awt.Font;
import java.awt.Graphics2D;
import java.awt.RenderingHints;
import java.awt.Toolkit;
import java.awt.Window;
import java.awt.event.KeyEvent;
import java.awt.event.KeyListener;
import java.awt.image.BufferStrategy;
import java.awt.image.BufferedImage;
import java.awt.geom.Path2D;
import java.awt.geom.Rectangle2D;
import java.awt.Shape;
import java.io.File;
import java.io.IOException;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.Deque;
import java.util.List;
import javax.imageio.ImageIO;
import javax.sound.sampled.Clip;
import javax.swing.JFrame;
import javax.swing.JOptionPane;
import javax.swing.SwingUtilities;
import java.awt.BufferCapabilities;


public class Game extends Canvas implements KeyListener, Runnable {
    static {
        System.setProperty("sun.java2d.opengl", "true");
        System.setProperty("sun.java2d.d3d",    "true");
    }

    private static final int WIDTH = Config.getScreenWidth();
    private static final int HEIGHT = Config.getScreenHeight();
    private static final long INV_DURATION = 3000;
    private static final int BLINK_INTERVAL = 200;

    private final int playerSize = 40;
    private final int bulletSize = 13;
    private final int maxLives = 5;



    private static final double SPEED_SCALE = 20.0;

    private long prevElapsedTime = -1;

    private final double playerSpeedPerSec = Config.getPlayerSpeed() * SPEED_SCALE;

    private final double slowSpeedPerSec   = Config.getSlowSpeed()   * SPEED_SCALE;
    private final double bulletSpeed = Config.getBulletSpeed();
    private final int hitboxRadius = Config.getHitboxRadius();

    private final int keyLeft = Config.getKeyCode("keyLeft");
    private final int keyRight = Config.getKeyCode("keyRight");
    private final int keyUp = Config.getKeyCode("keyUp");
    private final int keyDown = Config.getKeyCode("keyDown");

    private BufferedImage playerTexture = Config.getPlayerTexture();
    private BufferedImage backgroundImage;
    private final float backgroundDim = Config.getBackgroundDim();

    private double approachTime;
    private double sliderMultiplier;
    private double beatLength;

    private Clip musicClip;
    private long startTime;
    private boolean running;
    private boolean paused;

    private int fps;             // текущее значение FPS
    private int frames;          // накопленные кадры
    private long fpsTimer;       // таймер для отсчёта секунды

    private double playerX;
    private double playerY;
    private boolean left, right, up, down, slowMode, invulnerable;
    private int lives;
    private long lastDamageTime;

    private String mapTitle = "No map selected";
    private String currentSetName;
    private String currentOsuFile;

    private final List<OsuParser.HitObject> hitObjects = new ArrayList<>();
    private int spawnIndex;

    private final List<SliderLaser> sliderLasers = new ArrayList<>();
    private final List<ScheduledSpawn> scheduledSpawns = new ArrayList<>();
    private int scheduleIndex;

    private final List<SpinnerManager> spinnerManagers = new ArrayList<>();

    private final Deque<Bullet> bulletPool = new ArrayDeque<>();
    private final List<Bullet> bullets = new ArrayList<>();
    private final int CELL = 100;
    private final int cols = (WIDTH + CELL - 1) / CELL;
    private final int rows = (HEIGHT + CELL - 1) / CELL;
    @SuppressWarnings("unchecked")
    private final List<Bullet>[][] grid = new List[cols][rows];

    private final BufferedImage bulletSprite;
    private final BufferedImage spinnerBulletSprite;

    private final Font hudFont = new Font("Arial", Font.BOLD, 14);
    private final BasicStroke hitboxStroke = new BasicStroke(2f);
    private final Composite defaultComposite = AlphaComposite.getInstance(AlphaComposite.SRC_OVER, 1f);
    private final Composite hitboxComposite = AlphaComposite.getInstance(AlphaComposite.SRC_OVER, 0.5f);

    private boolean aaDisabled = false;
    private boolean bombWasActive = false;
    private int savedSpawnIndex;
    private int savedScheduleIndex;

    public Game() {
        setPreferredSize(new Dimension(WIDTH, HEIGHT));
        setBackground(Color.BLACK);
        initGrid();
        bulletSprite = createBulletSprite(Color.RED);
        spinnerBulletSprite = createBulletSprite(Color.CYAN);
        Bomb.init(bullets,sliderLasers,spinnerManagers,WIDTH,HEIGHT);
        addKeyListener(this);
        setFocusable(true);
        requestFocus();
        resetPlayer();
    }

    private void initGrid() {
        for (int x = 0; x < cols; x++) {
            for (int y = 0; y < rows; y++) {
                grid[x][y] = new ArrayList<>();
            }
        }
    }

    private BufferedImage createBulletSprite(Color color) {
        BufferedImage img = new BufferedImage(bulletSize, bulletSize, BufferedImage.TYPE_INT_ARGB);
        Graphics2D g = img.createGraphics();
        g.setColor(color);
        g.fillOval(0, 0, bulletSize, bulletSize);
        g.dispose();
        return img;
    }

    @Override
    public void addNotify() {
        super.addNotify();
        SwingUtilities.invokeLater(() -> {
            Window w = SwingUtilities.getWindowAncestor(this);
            if (w instanceof JFrame) {
                JFrame f = (JFrame) w;
                f.setResizable(false);
                f.getContentPane().setBackground(Color.BLACK);
            }
        });
    }

    private void resetPlayer() {
        playerX = (WIDTH - playerSize) / 2.0;
        playerY = HEIGHT - playerSize - 20;
        lives = maxLives;
        left = right = up = down = slowMode = invulnerable = false;
        lastDamageTime = 0;
    }

    public void setMap(String setName, String osuFile) {
        stopMusic();
        currentSetName = setName;
        currentOsuFile = osuFile;
        mapTitle = setName + " | " + osuFile;

        hitObjects.clear();
        bullets.clear();
        scheduledSpawns.clear();
        sliderLasers.clear();
        bulletPool.clear();
        clearGrid();
        spawnIndex = scheduleIndex = 0;
        resetPlayer();

        OsuParser.OsuMapData mapData = new OsuParser().parse(
            new File(Main.BEATMAPS_DIR, setName), osuFile
        );
        approachTime = mapData.approachTime;
        sliderMultiplier = mapData.sliderMultiplier;
        beatLength = mapData.beatLength;
        musicClip = mapData.musicClip;
        hitObjects.addAll(mapData.hitObjects);

        loadBackground(setName);
        scheduleSliderLasers(mapData);

        spinnerManagers.clear();
        for (OsuParser.Spinner s : mapData.spinners) {
            spinnerManagers.add(
                new SpinnerManager(WIDTH/2, HEIGHT/2, s.startTime, s.endTime)
            );
        }

        startMusic();
        startTime = System.currentTimeMillis();
        if (!running) {
            running = true;
            new Thread(this, "GameLoop").start();
        }
    }

    private void clearGrid() {
        for (int x = 0; x < cols; x++) {
            for (int y = 0; y < rows; y++) {
                grid[x][y].clear();
            }
        }
    }

    private void loadBackground(String setName) {
        backgroundImage = null;
        try {
            File dir = new File(Main.BEATMAPS_DIR, setName);
            File[] imgs = dir.listFiles((d, n) -> n.toLowerCase().matches(".*\\.(jpg|png|jpeg|bmp)$"));
            if (imgs != null && imgs.length > 0) {
                backgroundImage = ImageIO.read(imgs[0]);
            }
        } catch (IOException ignored) {}
    }

    private void scheduleSliderLasers(OsuParser.OsuMapData mapData) {
        double sliderVelocity = sliderMultiplier * 100;
        for (OsuParser.TempSlider ts : mapData.tempSliders) {
            double singleDur = ts.pixelLen / sliderVelocity * beatLength;
            double totalDur = singleDur * ts.repeats;
            int nPts = ts.ctrlPts.size();
            for (int k = 1; k < nPts; k++) {
                double frac = (double) k / (nPts - 1);
                long ctrlT = (long)(ts.time + frac * singleDur);
                long offset = ctrlT - (long) approachTime;
                ScheduledSpawn ss = new ScheduledSpawn();
                ss.offset = offset;
                ss.x = ts.ctrlPts.get(k).x;
                ss.y = ts.ctrlPts.get(k).y;
                scheduledSpawns.add(ss);
            }
             // Preview за 1000ms до ts.time, затем сам слайдер длится totalDur
        sliderLasers.add(new SliderLaser(
            ts.ctrlPts,
            ts.time,
            1000,       // ровно 1 сек до startTime — показываем синий
            totalDur    // длительность самого опасного лазера
        ));
        }
        scheduledSpawns.sort(Comparator.comparingLong(s -> s.offset));
    }

    private void stopMusic() {
        if (musicClip != null) {
            musicClip.stop();
            musicClip.close();
            musicClip = null;
        }
    }

    private void startMusic() {
        if (musicClip != null) {
            musicClip.setFramePosition(0);
            musicClip.start();
        }
    }


@Override
public void run() {
    // 1) Настраиваем triple-buffering
    createBufferStrategy(3);
    BufferStrategy bs = getBufferStrategy();

    // 2) Читаем лимит FPS и считаем наносекунды на кадр
    int fpsLimit    = Config.getMaxFPS();                      // например, 60
    long nsPerFrame = fpsLimit > 0 ? 1_000_000_000L / fpsLimit : 0;

    // 3) Инициализируем переменные для подсчёта FPS
    long lastTime = System.nanoTime();
    fpsTimer = lastTime;
    frames   = 0;

    // 4) Игровой цикл
    while (running) {
        // Метка начала кадра
        long frameStart = System.nanoTime();

        // Логика и рендер
        update();
        renderFrame(bs);

        // FPS-счётчик
        frames++;
        if (frameStart - fpsTimer >= 1_000_000_000L) {
            fps        = frames;
            frames     = 0;
            fpsTimer  += 1_000_000_000L;
        }

        // По желанию синхронизируемся через Toolkit (не настоящий V-Sync, но может помочь)
        if (Config.isVSyncEnabled()) {
            Toolkit.getDefaultToolkit().sync();
        }

        // 5) Ждём остаток времени до следующей итерации, чтобы не превышать fpsLimit
        if (nsPerFrame > 0) {
            long frameTime = System.nanoTime() - frameStart;
            long sleepNs   = nsPerFrame - frameTime;
            if (sleepNs > 0) {
                try {
                    Thread.sleep(sleepNs / 1_000_000L, (int)(sleepNs % 1_000_000L));
                } catch (InterruptedException ignored) {
                }
            } else {
                // если мы уже опоздали, даём другим потокам шанс
                Thread.yield();
            }
        }
    }
}



private void update() {
    if (paused) return;

    // 1) вычисляем реальное прошедшее время
    long elapsed = (musicClip != null
         ? musicClip.getMicrosecondPosition() / 1000
         : System.currentTimeMillis() - startTime);
    // считаем дельта-время между кадрами в секундах
    double dtSec = prevElapsedTime >= 0
        ? (elapsed - prevElapsedTime) / 1000.0
        : 0.0;
    prevElapsedTime = elapsed;


    // 2) проверяем состояние бомбы и обновляем
    boolean wasActive = Bomb.isActive();
    Bomb.update(elapsed);
    boolean nowActive = Bomb.isActive();

    // 3) при старте бомбы запоминаем индексы спавна
    if (!wasActive && nowActive) {
        savedSpawnIndex    = spawnIndex;
        savedScheduleIndex = scheduleIndex;
    }

    // 4) если бомба активна — очищаем только пули и грид, выходим
    if (nowActive) {
        bullets.clear();
        clearGrid();
        return;
    }

    // 5) при окончании бомбы пропускаем все события спавна, что должны были произойти
    if (wasActive && !nowActive) {
        while (spawnIndex < hitObjects.size() &&
               hitObjects.get(spawnIndex).time - approachTime <= elapsed) {
            spawnIndex++;
        }
        while (scheduleIndex < scheduledSpawns.size() &&
               scheduledSpawns.get(scheduleIndex).offset <= elapsed) {
            scheduleIndex++;
        }
    }

    // 6) сброс неуязвимости
    if (invulnerable && elapsed - lastDamageTime >= INV_DURATION) {
        invulnerable = false;
    }

    // 7) спавн пулевых объектов
    while (spawnIndex < hitObjects.size() &&
           hitObjects.get(spawnIndex).time - approachTime <= elapsed) {
        spawnBullet(hitObjects.get(spawnIndex++));
    }

    // 8) спавн лазерных пуль
    while (scheduleIndex < scheduledSpawns.size() &&
           elapsed >= scheduledSpawns.get(scheduleIndex).offset) {
        ScheduledSpawn ss = scheduledSpawns.get(scheduleIndex++);
        spawnSliderBullet(ss.x, ss.y);
    }

    // 9) обновление спиннеров
    for (int i = spinnerManagers.size() - 1; i >= 0; i--) {
        SpinnerManager mgr = spinnerManagers.get(i);
        if (!mgr.update(elapsed, bullets, bulletPool, bulletSize)) {
            spinnerManagers.remove(i);
        }
    }

    // 10) обновление пуль и грида (с учётом dtSec)
for (int i = bullets.size() - 1; i >= 0; i--) {
    Bullet bullet = bullets.get(i);
    double oldX = bullet.getX(), oldY = bullet.getY();
    int oldGX = (int)(oldX / CELL), oldGY = (int)(oldY / CELL);

    // перемещаем пулю с учётом дельта-времени
    boolean removedBullet = bullet.updateAndCheck(WIDTH, HEIGHT, dtSec);
    if (removedBullet) {
        bulletPool.addLast(bullets.remove(i));
        if (oldGX >= 0 && oldGX < cols && oldGY >= 0 && oldGY < rows) {
            grid[oldGX][oldGY].remove(bullet);
        }
        continue;
    }

    // обновляем положение в сетке, если клетка изменилась
    int newGX = (int)(bullet.getX() / CELL), newGY = (int)(bullet.getY() / CELL);
    if (newGX != oldGX || newGY != oldGY) {
        if (oldGX >= 0 && oldGX < cols && oldGY >= 0 && oldGY < rows) {
            grid[oldGX][oldGY].remove(bullet);
        }
        if (newGX >= 0 && newGX < cols && newGY >= 0 && newGY < rows) {
            grid[newGX][newGY].add(bullet);
        }
    }
}



    // 11) проверка столкновений и урон от пуль
    int pcx = (int)((playerX + playerSize / 2.0) / CELL);
    int pcy = (int)((playerY + playerSize / 2.0) / CELL);
    for (int dx = -1; dx <= 1; dx++) {
        for (int dy = -1; dy <= 1; dy++) {
            int gx = pcx + dx, gy = pcy + dy;
            if (gx < 0 || gy < 0 || gx >= cols || gy >= rows) continue;
            for (Bullet b : grid[gx][gy]) {
                if (!invulnerable) {
                    double cx = playerX + playerSize / 2.0;
                    double cy = playerY + playerSize / 2.0;
                    double dx2 = b.getX() - cx;
                    double dy2 = b.getY() - cy;
                    double rsum = b.getSize() / 2.0 + hitboxRadius;
                    if (dx2 * dx2 + dy2 * dy2 <= rsum * rsum) {
                        invulnerable = true;
                        lastDamageTime = elapsed;
                        lives--;
                        if (lives <= 0) {
                            gameOver();
                            return;
                        }
                    }
                }
            }
        }
    }

    // 12) проверка столкновений и урон от лазеров (новый код)
    for (SliderLaser sl : sliderLasers) {
    Shape laserShape = sl.getCollisionShape(WIDTH, HEIGHT, elapsed);
    if (laserShape != null) {
        Rectangle2D playerBox =
            new Rectangle2D.Double(playerX, playerY, playerSize, playerSize);
        if (!invulnerable && laserShape.intersects(playerBox)) {
            invulnerable   = true;
            lastDamageTime = elapsed;
            lives--;
            if (lives <= 0) {
                gameOver();
                return;
            }
        }
    }
}

    // 13) движение игрока
    double unitsPerSec = slowMode ? slowSpeedPerSec : playerSpeedPerSec;
    double moveDist   = unitsPerSec * dtSec;
    if (left)  playerX = Math.max(0, playerX - moveDist);
    if (right) playerX = Math.min(WIDTH - playerSize, playerX + moveDist);
    if (up)    playerY = Math.max(0, playerY - moveDist);
    if (down)  playerY = Math.min(HEIGHT - playerSize, playerY + moveDist);
}



private void renderFrame(BufferStrategy bs) {
    Graphics2D g = (Graphics2D) bs.getDrawGraphics();
    if (!aaDisabled) {
        g.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_OFF);
        g.setRenderingHint(RenderingHints.KEY_TEXT_ANTIALIASING, RenderingHints.VALUE_TEXT_ANTIALIAS_OFF);
        aaDisabled = true;
    }
    // background...
    if (backgroundImage != null) {
        g.drawImage(backgroundImage, 0, 0, WIDTH, HEIGHT, null);
        Composite oldComp = g.getComposite();
        g.setComposite(AlphaComposite.getInstance(AlphaComposite.SRC_OVER, backgroundDim));
        g.setColor(Color.BLACK);
        g.fillRect(0, 0, WIDTH, HEIGHT);
        g.setComposite(oldComp);
    } else {
        g.setColor(Color.BLACK);
        g.fillRect(0, 0, WIDTH, HEIGHT);
    }

    long elapsed = (musicClip != null)
        ? musicClip.getMicrosecondPosition() / 1000
        : System.currentTimeMillis() - startTime;

    // HUD
    g.setColor(Color.WHITE);
    g.setFont(hudFont);
    g.drawString(mapTitle, 20, 20);
    g.drawString("Lives: " + lives, WIDTH - 100, 20);
    g.drawString("FPS: " + fps, 20, HEIGHT - 20);
    // player draw...
    boolean drawPlayer = true;
    if (invulnerable && elapsed - lastDamageTime < INV_DURATION) {
        if (((elapsed - lastDamageTime) / BLINK_INTERVAL) % 2 == 0) {
            drawPlayer = false;
        }
    }
    int px = (int) playerX, py = (int) playerY;
    if (drawPlayer) {
        if (playerTexture != null) {
            g.drawImage(playerTexture, px, py, playerSize, playerSize, null);
        } else {
            g.fillRect(px, py, playerSize, playerSize);
        }
    }
    g.setComposite(hitboxComposite);
    g.setStroke(hitboxStroke);
    g.drawOval(px + playerSize/2 - hitboxRadius, py + playerSize/2 - hitboxRadius,
               hitboxRadius*2, hitboxRadius*2);
    g.setComposite(defaultComposite);

    // HUD + fullscreen-эффект бомбы
    Bomb.render(g, elapsed);

    // draw bullets and lasers only if not in bomb
    if (!Bomb.isActive()) {
        for (Bullet b : bullets) {
            int bx = (int)(b.getX() - b.getSize()/2);
            int by = (int)(b.getY() - b.getSize()/2);
            BufferedImage sprite = b.isSpinner() ? spinnerBulletSprite : bulletSprite;
            g.drawImage(sprite, bx, by, null);
        }
        for (SliderLaser sl : sliderLasers) {
            sl.render(g, WIDTH, HEIGHT, (int) elapsed);
        }
    }

    g.dispose();
    bs.show();
}



    private void spawnBullet(OsuParser.HitObject ho) {
        Bullet b = bulletPool.pollFirst();
        if (b == null) b = new Bullet(bulletSize);
        b.setSpinner(false);
        b.initRandom(
            WIDTH,
            playerX + playerSize / 2.0,
            playerY + playerSize / 2.0,
            bulletSpeed,
            (long) approachTime
        );
        bullets.add(b);
        int gx = (int) (b.getX() / CELL);
        int gy = (int) (b.getY() / CELL);
        if (gx >= 0 && gx < cols && gy >= 0 && gy < rows) {
            grid[gx][gy].add(b);
        }
    }

    private void spawnSliderBullet(int sx, int sy) {
        Bullet b = bulletPool.pollFirst();
        if (b == null) b = new Bullet(bulletSize);
        b.setSpinner(false);
        b.initAt(
            sx,
            sy,
            playerX + playerSize / 2.0,
            playerY + playerSize / 2.0,
            bulletSpeed,
            (long) approachTime
        );
        bullets.add(b);
        int gx = (int) (b.getX() / CELL);
        int gy = (int) (b.getY() / CELL);
        if (gx >= 0 && gx < cols && gy >= 0 && gy < rows) {
            grid[gx][gy].add(b);
        }
    }

    private void gameOver() {
        running = false;
        SwingUtilities.invokeLater(() -> {
            int res = JOptionPane.showOptionDialog(
                this,
                "You lost!",
                "Game Over",
                JOptionPane.YES_NO_OPTION,
                JOptionPane.INFORMATION_MESSAGE,
                null,
                new String[]{"Retry", "Exit"},
                "Retry"
            );
            if (res == JOptionPane.YES_OPTION) {
                setMap(currentSetName, currentOsuFile);
            } else {
                Window w = SwingUtilities.getWindowAncestor(this);
                if (w != null) w.dispose();
                System.exit(0);
            }
        });
    }

    @Override
    public void keyPressed(KeyEvent e) {
        int code = e.getKeyCode();
        if (code == keyLeft) left = true;
        else if (code == keyRight) right = true;
        else if (code == keyUp) up = true;
        else if (code == keyDown) down = true;
        else if (code == KeyEvent.VK_SHIFT) slowMode = true;
        else if (code == KeyEvent.VK_P) {
            if (musicClip != null) {
                paused = !paused;
                if (paused) musicClip.stop();
                else musicClip.start();
            }
        } else if (code == KeyEvent.VK_X) {
        long elapsed = (musicClip != null
            ? musicClip.getMicrosecondPosition()/1000
            : System.currentTimeMillis() - startTime);
        Bomb.activate(playerX + playerSize/2.0, playerY + playerSize/2.0, elapsed);
}  else if (code == KeyEvent.VK_ESCAPE) {
            Window w = SwingUtilities.getWindowAncestor(this);
            if (w != null) w.dispose();
            System.exit(0);
        }
    }

    @Override
    public void keyReleased(KeyEvent e) {
        int code = e.getKeyCode();
        if (code == keyLeft) left = false;
        else if (code == keyRight) right = false;
        else if (code == keyUp) up = false;
        else if (code == keyDown) down = false;
        else if (code == KeyEvent.VK_SHIFT) slowMode = false;
    }

    @Override
    public void keyTyped(KeyEvent e) { }

    private static class ScheduledSpawn {
        long offset;
        int x, y;
    }
}
