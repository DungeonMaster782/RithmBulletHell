// Game.java
import java.awt.Canvas;
import java.awt.Color;
import java.awt.Dimension;
import java.awt.Font;
import java.awt.Graphics2D;
import java.awt.Composite;
import java.awt.AlphaComposite;
import java.awt.BasicStroke;
import java.awt.Window;
import java.awt.Point;
import java.awt.event.KeyEvent;
import java.awt.event.KeyListener;
import java.awt.image.BufferedImage;
import java.io.*;
import java.util.*;
import javax.imageio.ImageIO;
import javax.sound.sampled.*;
import javax.swing.*;

public class Game extends Canvas implements KeyListener, Runnable {
    private static final int WIDTH  = Config.getScreenWidth();
    private static final int HEIGHT = Config.getScreenHeight();
    private static final long INV_DURATION = 3000;

    // Игрок
    private final int playerSize = 40;
    private final int bulletSize = 12;
    private final int maxLives   = 5;

    // Конфигурация
    private final int    playerSpeed  = Config.getPlayerSpeed();
    private final double bulletSpeed  = Config.getBulletSpeed();
    private final int    slowSpeed    = Config.getSlowSpeed();
    private final int    hitboxRadius = Config.getHitboxRadius();
    private final int    keyLeft    = Config.getKeyCode("keyLeft");
    private final int    keyRight   = Config.getKeyCode("keyRight");
    private final int    keyUp      = Config.getKeyCode("keyUp");
    private final int    keyDown    = Config.getKeyCode("keyDown");
    private final BufferedImage playerTexture = Config.getPlayerTexture();

    // Тайминги и параметры слайдера
    private double approachTime;      // из AR → ms
    private double sliderMultiplier;  // из Difficulty
    private double beatLength;        // из TimingPoints → ms на бит

    // Остальное состояние
    private long startTime;
    private Clip musicClip;
    private boolean running, paused;
    private boolean left, right, up, down, slow;
    private int playerX, playerY;
    private int lives;
    private boolean invulnerable;
    private long lastDamageTime;
    private String mapTitle = "No map selected";
    private String currentSetName, currentOsuFile;

    // Hit circles
    private final List<HitObject> hitObjects = new ArrayList<>();
    private int spawnIndex = 0;

    // Слайдерные лазеры
    private final List<SliderLaser> sliderLasers = new ArrayList<>();

    // Запланированные пули из слайдера
    private class ScheduledSpawn { long offset; int x,y; }
    private final List<ScheduledSpawn> scheduledSpawns = new ArrayList<>();
    private int scheduleIndex = 0;

    // Обычные пули
    private final List<Bullet> bullets = new ArrayList<>();

    public Game() {
        setPreferredSize(new Dimension(WIDTH, HEIGHT));
        addKeyListener(this);
        setFocusable(true);
        requestFocus();
        resetPlayer();
    }

    private void resetPlayer() {
        playerX = WIDTH/2 - playerSize/2;
        playerY = HEIGHT - 60;
        lives   = maxLives;
    }

    public void setMap(String setName, String osuFile) {
        stopMusic();
        currentSetName = setName;
        currentOsuFile = osuFile;
        mapTitle       = setName + " | " + osuFile;
        invulnerable   = false;
        lastDamageTime = 0;
        spawnIndex     = 0;
        scheduleIndex  = 0;

        hitObjects.clear();
        bullets.clear();
        sliderLasers.clear();
        scheduledSpawns.clear();
        resetPlayer();

        parseOsu(new File(Main.BEATMAPS_DIR, setName), osuFile);
        startMusic();
        startTime = System.currentTimeMillis();

        if (!running) {
            running = true;
            new Thread(this, "GameLoop").start();
        }
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

    private void parseOsu(File dir, String fileName) {
        // Дефолты
        approachTime      = 1500;
        sliderMultiplier  = 1.4;
        beatLength        = 500;

        // Временные хранилища
        class TempSlider {
            long time;
            int repeats;
            double pixelLen;
            List<Point> ctrlPts;
        }
        List<TempSlider> tempSliders = new ArrayList<>();

        boolean inDiff = false, inTiming = false, inHits = false;
        File osu = new File(dir, fileName);

        try (BufferedReader r = new BufferedReader(new InputStreamReader(new FileInputStream(osu), "UTF-8"))) {
            String line;
            while ((line = r.readLine()) != null) {
                // --- Difficulty ---
                if (!inHits && !inTiming) {
                    if (line.equals("[Difficulty]")) { inDiff = true; continue; }
                    if (line.equals("[TimingPoints]")) { inTiming = true; inDiff = false; }
                }
                if (inDiff) {
                    if (line.startsWith("ApproachRate:"))
                        approachTime     = (line.contains(":")?
                            1800 - 120 * Double.parseDouble(line.split(":",2)[1].trim())
                            : approachTime);
                    if (line.startsWith("SliderMultiplier:"))
                        sliderMultiplier = Double.parseDouble(line.split(":",2)[1].trim());
                    if (line.startsWith("[")) inDiff = false;
                    continue;
                }
                // --- TimingPoints (берём первую «основную») ---
                if (inTiming) {
                    if (line.startsWith("[")) { inTiming = false; continue; }
                    if (!line.isBlank()) {
                        String[] tp = line.split(",");
                        if (tp.length > 6 && Integer.parseInt(tp[6].trim()) == 1) {
                            beatLength = Double.parseDouble(tp[1].trim());
                            inTiming = false;
                        }
                    }
                    continue;
                }
                // --- HitObjects ---
                if (!inHits && line.equals("[HitObjects]")) { inHits = true; continue; }
                if (inHits && line.isBlank()) continue;
                if (inHits) {
                    String[] p = line.split(",");
                    int x    = Integer.parseInt(p[0]), y    = Integer.parseInt(p[1]);
                    long t   = Long.parseLong(p[2]);
                    int type = Integer.parseInt(p[3]);

                    // Слайдер
                    if ((type & 2) != 0 && p.length > 7) {
                        TempSlider ts = new TempSlider();
                        ts.time     = t;
                        ts.repeats  = Integer.parseInt(p[6]);
                        ts.pixelLen = Double.parseDouble(p[7]);

                        // Контрольные точки (включая стартовую)
                        String[] sd = p[5].split("\\|");
                        ts.ctrlPts = new ArrayList<>();
                        ts.ctrlPts.add(new Point(x, y));         // старт
                        for (int i = 1; i < sd.length; i++) {
                            String[] xy = sd[i].split(":");
                            ts.ctrlPts.add(new Point(
                                Integer.parseInt(xy[0]),
                                Integer.parseInt(xy[1])
                            ));
                        }

                        tempSliders.add(ts);
                    }
                    // Круги
                    else if ((type & 1) != 0) {
                        hitObjects.add(new HitObject(x, y, t));
                    }
                }
            }
        } catch (IOException ex) {
            ex.printStackTrace();
        }

        // По каждому временному слайдеру строим Laser + события пуль
        double sliderVelocity = sliderMultiplier * 100; // px/beat
        for (TempSlider ts : tempSliders) {
            // длительность одного прохода
            double singleDur = ts.pixelLen / sliderVelocity * beatLength;
            double totalDur  = singleDur * ts.repeats;

            // 1) Scheduler: по мере движения по CtrlPts (только вперёд) спавним пули
            int nPts = ts.ctrlPts.size();
            for (int k = 1; k < nPts; k++) {
                long offset = (long)( (k / (double)(nPts - 1)) * singleDur );
                ScheduledSpawn ss = new ScheduledSpawn();
                ss.offset = offset;
                ss.x      = ts.ctrlPts.get(k).x;
                ss.y      = ts.ctrlPts.get(k).y;
                scheduledSpawns.add(ss);
            }

            // 2) создаём сам лазер
            sliderLasers.add(new SliderLaser(
                ts.ctrlPts,
                ts.time,
                approachTime,
                totalDur
            ));
        }
        // Сортируем по времени
        scheduledSpawns.sort(Comparator.comparingLong(s->s.offset));

        // --- загрузка музыки (как было) ---
        // --- загрузка аудио с фолбэком для OGG ---
       // … внутри parseOsu, после разбора слайдеров и перед закрывающей скобкой метода …
    try {
        String audioName = getAudioFilename(osu);
        if (audioName != null) {
            File audioFile = new File(dir, audioName);
            try (AudioInputStream ais = AudioSystem.getAudioInputStream(audioFile)) {
                // эти две строки теперь могут бросать LineUnavailableException
                musicClip = AudioSystem.getClip();
                musicClip.open(ais);
            }
        }
    }
    catch (UnsupportedAudioFileException uafe) {
        System.err.println("Unsupported format, trying ffmpeg fallback: " + uafe.getMessage());
        // … ваш ffmpeg-фолбэк, как раньше …
        try {
            File audioFile = new File(dir, getAudioFilename(osu));
            File wav = new File(dir, "__temp.wav");
            new ProcessBuilder(
                "ffmpeg", "-y",
                "-i", audioFile.getAbsolutePath(),
                wav.getAbsolutePath()
            ).inheritIO().start().waitFor();
            try (AudioInputStream ais2 = AudioSystem.getAudioInputStream(wav)) {
                musicClip = AudioSystem.getClip();
                musicClip.open(ais2);
            }
            wav.deleteOnExit();
        } catch (Exception ex) {
            System.err.println("ffmpeg fallback failed: " + ex.getMessage());
        }
    }
    catch (LineUnavailableException lue) {
        System.err.println("Audio line unavailable: " + lue.getMessage());
    }
    catch (IOException ioe) {
        System.err.println("I/O error loading audio: " + ioe.getMessage());
    }
}  // конец parseOsu()

private String getAudioFilename(File osu) throws IOException {
    try (BufferedReader r = new BufferedReader(new InputStreamReader(new FileInputStream(osu), "UTF-8"))) {
        String line;
        while ((line = r.readLine()) != null) {
            if (line.startsWith("AudioFilename:")) {
                return line.split(":", 2)[1].trim();
            }
        }
    }
    return null;
}


    @Override public void run() {
        createBufferStrategy(2);
        long lastTime = System.nanoTime();
        long nsPerFrame = 1_000_000_000L / 60;

        while (running) {
            long now = System.nanoTime();
            if (now - lastTime >= nsPerFrame) {
                update();
                renderFrame();
                lastTime = now;
            } else {
                Thread.yield();
            }
        }
    }

    private void update() {
        if (paused) return;
        long elapsed = (musicClip!=null
            ? musicClip.getMicrosecondPosition()/1000
            : System.currentTimeMillis() - startTime);

        // Снимаем неуязвимость
        if (invulnerable && elapsed - lastDamageTime >= INV_DURATION)
            invulnerable = false;

        // Спавн пуль из hit circles
        while (spawnIndex < hitObjects.size()
            && hitObjects.get(spawnIndex).time - approachTime <= elapsed) {
            spawnBullet(hitObjects.get(spawnIndex++));
        }

        // Спавн пуль из слайдерных точек
        while (scheduleIndex < scheduledSpawns.size()
            && elapsed >= scheduledSpawns.get(scheduleIndex).offset) {
            ScheduledSpawn ss = scheduledSpawns.get(scheduleIndex++);
            spawnSliderBullet(ss.x, ss.y);
        }

        // Обновляем все пули
        Iterator<Bullet> it = bullets.iterator();
        while (it.hasNext()) {
            Bullet b = it.next();
            if (b.updateAndCheck(WIDTH, HEIGHT)) {
                it.remove();
                continue;
            }
            // Проверка на игрока
            if (!invulnerable) {
                double cx = playerX + playerSize/2.0;
                double cy = playerY + playerSize/2.0;
                double dx = b.x - cx, dy = b.y - cy;
                double rsum = b.size/2.0 + hitboxRadius;
                if (dx*dx + dy*dy <= rsum*rsum) {
                    it.remove();
                    lives--;
                    invulnerable   = true;
                    lastDamageTime = elapsed;
                    if (lives <= 0) { gameOver(); return; }
                }
            }
        }

        // Движение игрока
        int spd = slow ? slowSpeed : playerSpeed;
        if (left)  playerX = Math.max(0, playerX - spd);
        if (right) playerX = Math.min(WIDTH - playerSize, playerX + spd);
        if (up)    playerY = Math.max(0, playerY - spd);
        if (down)  playerY = Math.min(HEIGHT - playerSize, playerY + spd);
    }

    private void renderFrame() {
        Graphics2D g = (Graphics2D) getBufferStrategy().getDrawGraphics();
        // Фон
        g.setColor(Color.BLACK);
        g.fillRect(0,0,WIDTH,HEIGHT);
        // HUD
        g.setColor(Color.WHITE);
        g.setFont(new Font("Arial",Font.BOLD,14));
        g.drawString(mapTitle, 20,20);
        g.drawString("Lives: "+lives, WIDTH-100,20);
        // Игрок
        if (playerTexture != null)
            g.drawImage(playerTexture, playerX, playerY, playerSize,playerSize,null);
        else {
            g.setColor(Color.WHITE);
            g.fillRect(playerX, playerY, playerSize,playerSize);
        }
        // Хитбокс
        Composite orig = g.getComposite();
        g.setComposite(AlphaComposite.getInstance(AlphaComposite.SRC_OVER, 0.5f));
        g.setStroke(new BasicStroke(2));
        g.setColor(Color.WHITE);
        int cx = playerX + playerSize/2, cy = playerY + playerSize/2;
        g.drawOval(cx-hitboxRadius, cy-hitboxRadius, hitboxRadius*2, hitboxRadius*2);
        g.setComposite(orig);

        // Пули
        g.setColor(Color.RED);
        for (Bullet b : bullets)
            g.fillOval((int)b.x - bulletSize/2, (int)b.y - bulletSize/2, bulletSize, bulletSize);

        // Лазеры
        long elapsed = (musicClip!=null
            ? musicClip.getMicrosecondPosition()/1000
            : System.currentTimeMillis() - startTime);
        for (SliderLaser sl : sliderLasers)
            sl.render(g, WIDTH, HEIGHT, elapsed);

        // Пауза
        if (paused) {
            g.setColor(Color.YELLOW);
            g.setFont(new Font("Arial",Font.BOLD,48));
            g.drawString("PAUSED", WIDTH/2-100, HEIGHT/2);
        }

        g.dispose();
        getBufferStrategy().show();
    }

    private void spawnBullet(HitObject ho) {
        double cx = playerX + playerSize/2.0;
        double cy = playerY + playerSize/2.0;
        double x = Math.random()*WIDTH, y = -bulletSize;
        double dx = (cx - x)/approachTime * bulletSpeed;
        double dy = (cy - y)/approachTime * bulletSpeed;
        bullets.add(new Bullet(x,y,dx,dy,bulletSize));
    }

    private void spawnSliderBullet(int sx, int sy) {
        double cx = playerX + playerSize/2.0;
        double cy = playerY + playerSize/2.0;
        double dx = (cx - sx)/approachTime * bulletSpeed;
        double dy = (cy - sy)/approachTime * bulletSpeed;
        bullets.add(new Bullet(sx,sy,dx,dy,bulletSize));
    }

    private void gameOver() {
        running = false;
        SwingUtilities.invokeLater(() -> {
            int res = JOptionPane.showOptionDialog(
                this, "You lost!", "Game Over",
                JOptionPane.YES_NO_OPTION,
                JOptionPane.INFORMATION_MESSAGE,
                null,
                new String[]{"Retry","Exit"},
                "Retry"
            );
            if (res == JOptionPane.YES_OPTION)
                setMap(currentSetName, currentOsuFile);
            else {
                Window w = SwingUtilities.getWindowAncestor(this);
                if (w!=null) w.dispose();
                System.exit(0);
            }
        });
    }

    @Override public void keyPressed(KeyEvent e) {
        int kc = e.getKeyCode();
        if (kc==keyLeft)   left  = true;
        if (kc==keyRight)  right = true;
        if (kc==keyUp)     up    = true;
        if (kc==keyDown)   down  = true;
        if (kc==KeyEvent.VK_SHIFT) slow = true;
        if (kc==KeyEvent.VK_P && musicClip!=null) {
            paused = !paused;
            if (paused) musicClip.stop(); else musicClip.start();
        }
        if (kc==KeyEvent.VK_ESCAPE) {
            Window w = SwingUtilities.getWindowAncestor(this);
            if (w!=null) w.dispose();
            System.exit(0);
        }
    }
    @Override public void keyReleased(KeyEvent e) {
        int kc = e.getKeyCode();
        if (kc==keyLeft)   left  = false;
        if (kc==keyRight)  right = false;
        if (kc==keyUp)     up    = false;
        if (kc==keyDown)   down  = false;
        if (kc==KeyEvent.VK_SHIFT) slow = false;
    }
    @Override public void keyTyped(KeyEvent e) {}

    private static class HitObject {
        final int x,y; final long time;
        HitObject(int x,int y,long t){ this.x=x; this.y=y; this.time=t;}
    }
    private static class Bullet {
        double x,y,dx,dy; int size;
        Bullet(double x,double y,double dx,double dy,int sz){
            this.x=x;this.y=y;this.dx=dx;this.dy=dy;this.size=sz;
        }
        boolean updateAndCheck(int w,int h){
            x+=dx; y+=dy;
            return y>h+size || x<-size || x>w+size;
        }
    }
}
