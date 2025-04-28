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
import java.awt.event.KeyEvent;
import java.awt.event.KeyListener;
import java.awt.image.BufferedImage;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.InputStreamReader;
import java.io.IOException;

import java.util.List;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.Comparator;

import javax.imageio.ImageIO;
import javax.sound.sampled.AudioInputStream;
import javax.sound.sampled.AudioSystem;
import javax.sound.sampled.Clip;
import javax.sound.sampled.UnsupportedAudioFileException;
import javax.swing.JOptionPane;
import javax.swing.SwingUtilities;

public class Game extends Canvas implements KeyListener, Runnable {
    private static final int WIDTH  = Config.getScreenWidth();
    private static final int HEIGHT = Config.getScreenHeight();

    private final int playerSize = 40;
    private final int bulletSize = 12;
    private final int maxLives   = 5;
    private static final long INV_DURATION = 3000;

    // из Config
    private final int    playerSpeed  = Config.getPlayerSpeed();
    private final double bulletSpeed  = Config.getBulletSpeed();
    private final int    slowSpeed    = Config.getSlowSpeed();
    private final int    hitboxRadius = Config.getHitboxRadius();

    private final int keyLeft    = Config.getKeyCode("keyLeft");
    private final int keyRight   = Config.getKeyCode("keyRight");
    private final int keyUp      = Config.getKeyCode("keyUp");
    private final int keyDown    = Config.getKeyCode("keyDown");
    private final BufferedImage playerTexture = Config.getPlayerTexture();

    // игровое состояние
    private long startTime;
    private double approachTime;
    private final List<HitObject> hitObjects = new ArrayList<>();
    private int spawnIndex;
    private Clip musicClip;

    private int playerX, playerY;
    private final List<Bullet> bullets = new ArrayList<>();

    private boolean running, paused;
    private boolean left, right, up, down, slow;  // slow = Shift

    private String mapTitle = "No map selected";
    private String currentSetName, currentOsuFile;

    private int lives;
    private boolean invulnerable;
    private long lastDamageTime;

    public Game() {
        setPreferredSize(new Dimension(WIDTH, HEIGHT));
        addKeyListener(this);
        setFocusable(true);
        requestFocus();

        playerX = WIDTH/2 - playerSize/2;
        playerY = HEIGHT - 60;
        lives   = maxLives;
    }

    public void setMap(String setName, String osuFile) {
        stopMusic();
        currentSetName = setName;
        currentOsuFile = osuFile;
        mapTitle       = setName + " | " + osuFile;
        lives          = maxLives;
        invulnerable   = false;
        lastDamageTime = 0;
        spawnIndex     = 0;
        hitObjects.clear();
        bullets.clear();

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
        hitObjects.clear();
        approachTime = 1500;
        double ar = 5;
        File osuFile = new File(dir, fileName);
        try (BufferedReader reader = new BufferedReader(
                new InputStreamReader(new FileInputStream(osuFile), "UTF-8"))) {
            String line;
            boolean inDiff = false, inHits = false;
            while ((line = reader.readLine()) != null) {
                if (!inHits) {
                    if (line.equals("[Difficulty]")) inDiff = true;
                    else if (inDiff) {
                        if (line.startsWith("ApproachRate:"))
                            ar = Double.parseDouble(line.split(":",2)[1].trim());
                        else if (line.startsWith("[")) inDiff = false;
                    } else if (line.equals("[HitObjects]")) {
                        inHits = true;
                    }
                } else if (!line.isBlank()) {
                    String[] parts = line.split(",");
                    hitObjects.add(new HitObject(
                        Integer.parseInt(parts[0]),
                        Integer.parseInt(parts[1]),
                        Long.parseLong(parts[2])
                    ));
                }
            }
        } catch (IOException e) {
            e.printStackTrace();
        }
        hitObjects.sort(Comparator.comparingLong(h -> h.time));
        approachTime = (ar <= 5) ? 1800 - 120*ar : 1200 - 150*(ar - 5);

        // загрузка музыки с фоллбэком для OGG
        String audioName;
        try {
            audioName = getAudioFilename(new File(dir, fileName));
        } catch (IOException e) {
            System.err.println("Не удалось прочитать AudioFilename: " + e.getMessage());
            return;
        }
        if (audioName == null) return;
        File audioFile = new File(dir, audioName);
        try {
            AudioInputStream ais = AudioSystem.getAudioInputStream(audioFile);
            musicClip = AudioSystem.getClip();
            musicClip.open(ais);
        } catch (UnsupportedAudioFileException uafe) {
            // OGG → WAV через ffmpeg
            try {
                File wav = new File(dir, "__temp.wav");
                new ProcessBuilder("ffmpeg","-y","-i",
                    audioFile.getAbsolutePath(),
                    wav.getAbsolutePath()
                ).inheritIO().start().waitFor();
                AudioInputStream ais2 = AudioSystem.getAudioInputStream(wav);
                musicClip = AudioSystem.getClip();
                musicClip.open(ais2);
                wav.deleteOnExit();
            } catch (Exception ex) {
                System.err.println("Фоллбэк ffmpeg не удался: " + ex.getMessage());
            }
        } catch (Exception e) {
            System.err.println("Не удалось загрузить аудио: " + e.getMessage());
        }
    }

    private String getAudioFilename(File osu) throws IOException {
        try (BufferedReader reader = new BufferedReader(
                new InputStreamReader(new FileInputStream(osu), "UTF-8"))) {
            String line;
            while ((line = reader.readLine()) != null) {
                if (line.startsWith("AudioFilename:")) {
                    return line.split(":",2)[1].trim();
                }
            }
        }
        return null;
    }

    @Override
    public void run() {
        createBufferStrategy(2);
        long last = System.nanoTime();
        long nsPerFrame = 1_000_000_000L / 60;
        while (running) {
            long now = System.nanoTime();
            if (now - last >= nsPerFrame) {
                update();

                // Рендер напрямую, без использования переменной BufferStrategy
                Graphics2D g = (Graphics2D) getBufferStrategy().getDrawGraphics();
                // очистка
                g.setColor(Color.BLACK);
                g.fillRect(0, 0, WIDTH, HEIGHT);

                // HUD
                g.setColor(Color.WHITE);
                g.setFont(new Font("Arial", Font.BOLD, 14));
                g.drawString(mapTitle, 20, 20);
                g.drawString("Lives: " + lives, WIDTH - 100, 20);

                // спрайт игрока
                if (playerTexture != null) {
                    g.drawImage(playerTexture, playerX, playerY, playerSize, playerSize, null);
                } else {
                    g.setColor(Color.WHITE);
                    g.fillRect(playerX, playerY, playerSize, playerSize);
                }

                // хитбокс поверх спрайта
                Composite orig = g.getComposite();
                g.setComposite(AlphaComposite.getInstance(AlphaComposite.SRC_OVER, 0.5f));
                g.setStroke(new BasicStroke(2));
                g.setColor(Color.WHITE);
                int cx = playerX + playerSize/2, cy = playerY + playerSize/2;
                g.drawOval(cx - hitboxRadius, cy - hitboxRadius, hitboxRadius*2, hitboxRadius*2);
                g.setComposite(orig);

                // пули
                g.setColor(Color.RED);
                for (Bullet b : bullets) {
                    g.fillOval((int) b.x - bulletSize/2, (int) b.y - bulletSize/2, bulletSize, bulletSize);
                }

                // пауза
                if (paused) {
                    g.setColor(Color.YELLOW);
                    g.setFont(new Font("Arial", Font.BOLD, 48));
                    g.drawString("PAUSED", WIDTH/2 - 100, HEIGHT/2);
                }

                g.dispose();
                getBufferStrategy().show();

                last = now;
            } else {
                Thread.yield();
            }
        }
    }

    private void update() {
        if (paused) return;
        long elapsed = musicClip != null
            ? musicClip.getMicrosecondPosition()/1000
            : System.currentTimeMillis() - startTime;

        if (invulnerable && elapsed - lastDamageTime >= INV_DURATION) {
            invulnerable = false;
        }

        while (spawnIndex < hitObjects.size()
               && hitObjects.get(spawnIndex).time - approachTime <= elapsed) {
            spawnBullet(hitObjects.get(spawnIndex++));
        }

        Iterator<Bullet> it = bullets.iterator();
        while (it.hasNext()) {
            Bullet b = it.next();
            if (b.updateAndCheck(WIDTH, HEIGHT)) {
                it.remove();
                continue;
            }
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
                    if (lives <= 0) {
                        gameOver();
                        return;
                    }
                }
            }
        }

        int speed = slow ? slowSpeed : playerSpeed;
        if (left)  playerX = Math.max(0, playerX - speed);
        if (right) playerX = Math.min(WIDTH - playerSize, playerX + speed);
        if (up)    playerY = Math.max(0, playerY - speed);
        if (down)  playerY = Math.min(HEIGHT - playerSize, playerY + speed);
    }

    private void spawnBullet(HitObject ho) {
        double cx = playerX + playerSize/2.0;
        double cy = playerY + playerSize/2.0;
        double x, y;
        switch (new java.util.Random().nextInt(3)) {
            case 0 -> { x = Math.random() * WIDTH;       y = -bulletSize; }
            case 1 -> { x = -bulletSize;                 y = Math.random() * HEIGHT; }
            default -> { x = WIDTH + bulletSize;         y = Math.random() * HEIGHT; }
        }
        double dx = (cx - x) / approachTime * bulletSpeed;
        double dy = (cy - y) / approachTime * bulletSpeed;
        bullets.add(new Bullet(x, y, dx, dy, bulletSize));
    }

    private void gameOver() {
        running = false;
        SwingUtilities.invokeLater(() -> {
            int res = JOptionPane.showOptionDialog(
                this, "You lost!", "Game Over",
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

    @Override public void keyPressed(KeyEvent e) {
        int kc = e.getKeyCode();
        if (kc == keyLeft)   left = true;
        if (kc == keyRight)  right = true;
        if (kc == keyUp)     up = true;
        if (kc == keyDown)   down = true;
        if (kc == KeyEvent.VK_SHIFT) slow = true;
        if (kc == KeyEvent.VK_P && musicClip != null) {
            paused = !paused;
            if (paused) musicClip.stop(); else musicClip.start();
        }
        if (kc == KeyEvent.VK_ESCAPE) {
            Window w = SwingUtilities.getWindowAncestor(this);
            if (w != null) w.dispose();
            System.exit(0);
        }
    }

    @Override public void keyReleased(KeyEvent e) {
        int kc = e.getKeyCode();
        if (kc == keyLeft)   left = false;
        if (kc == keyRight)  right = false;
        if (kc == keyUp)     up = false;
        if (kc == keyDown)   down = false;
        if (kc == KeyEvent.VK_SHIFT) slow = false;
    }

    @Override public void keyTyped(KeyEvent e) {}

    private static class HitObject {
        final int x, y;
        final long time;
        HitObject(int x, int y, long time) { this.x = x; this.y = y; this.time = time; }
    }

    private static class Bullet {
        double x, y, dx, dy;
        int size;
        Bullet(double x, double y, double dx, double dy, int size) {
            this.x = x; this.y = y; this.dx = dx; this.dy = dy; this.size = size;
        }
        boolean updateAndCheck(int w, int h) {
            x += dx; y += dy;
            return y > h + size || x < -size || x > w + size;
        }
    }
}
