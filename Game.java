import java.awt.Canvas;
import java.awt.Color;
import java.awt.Dimension;
import java.awt.Font;
import java.awt.Graphics2D;
import java.awt.RenderingHints;
import java.awt.image.BufferStrategy;
import java.awt.event.KeyEvent;
import java.awt.event.KeyListener;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;
import java.util.Properties;
import java.util.Random;
import javax.sound.sampled.*;

public class Game extends Canvas implements KeyListener, Runnable {
    private static int WIDTH = 800, HEIGHT = 600;

    private long startTime;
    private final List<HitObject> hitObjects = new ArrayList<>();
    private int spawnIndex = 0;
    private double approachTime;

    private Clip musicClip;

    private int playerX, playerY;
    private final int playerSize = 40;
    private int playerSpeed;

    private final List<Bullet> bullets = new ArrayList<>();
    private double bulletSpeed;
    private final int bulletSize = 12;

    private boolean running, left, right, up, down;
    private String mapTitle = "No map selected";

    public Game() {
        loadConfig();
        setPreferredSize(new Dimension(WIDTH, HEIGHT));
        addKeyListener(this);
        setFocusable(true);
        requestFocus();
        playerX = WIDTH / 2 - playerSize / 2;
        playerY = HEIGHT - 60;
    }

    private void loadConfig() {
        Properties p = new Properties();
        File cfg = new File("config.properties");
        if (cfg.exists()) {
            try (FileInputStream in = new FileInputStream(cfg)) {
                p.load(in);
            } catch (IOException e) {
                e.printStackTrace();
            }
        } else {
            p.setProperty("playerSpeed", "5");
            p.setProperty("bulletSpeed", "4");
            p.setProperty("screenWidth", String.valueOf(WIDTH));
            p.setProperty("screenHeight", String.valueOf(HEIGHT));
            try (FileOutputStream out = new FileOutputStream(cfg)) {
                p.store(out, null);
            } catch (IOException e) {
                e.printStackTrace();
            }
        }
        playerSpeed = Integer.parseInt(p.getProperty("playerSpeed", "5"));
        bulletSpeed = Double.parseDouble(p.getProperty("bulletSpeed", "4"));
        try {
            WIDTH = Integer.parseInt(p.getProperty("screenWidth", String.valueOf(WIDTH)));
            HEIGHT = Integer.parseInt(p.getProperty("screenHeight", String.valueOf(HEIGHT)));
        } catch (NumberFormatException ex) {
            System.err.println("Invalid screen size in config, using defaults.");
        }
    }

    public void setMap(String setName, String osuFile) {
        mapTitle = setName + " | " + osuFile;
        parseOsu(new File(Main.BEATMAPS_DIR, setName), osuFile);
        spawnIndex = 0;
        if (musicClip != null) {
            musicClip.stop();
            musicClip.setFramePosition(0);
            musicClip.start();
        } else {
            startTime = System.currentTimeMillis();
        }
        if (!running) {
            running = true;
            new Thread(this, "GameLoop").start();
        }
    }

    private void parseOsu(File dir, String fileName) {
        hitObjects.clear();
        musicClip = null;
        approachTime = 1500;
        double ar = 5;

        File osu = new File(dir, fileName);
        try (BufferedReader r = new BufferedReader(
             new InputStreamReader(new FileInputStream(osu), StandardCharsets.UTF_8))) {
            String line;
            boolean inDiff = false, inHits = false;
            while ((line = r.readLine()) != null) {
                if (!inHits) {
                    if (line.equals("[Difficulty]")) { inDiff = true; continue; }
                    if (inDiff) {
                        if (line.startsWith("ApproachRate:")) {
                            ar = Double.parseDouble(line.split(":")[1].trim());
                        } else if (line.startsWith("[")) {
                            inDiff = false;
                        }
                    }
                    if (line.equals("[HitObjects]")) { inHits = true; continue; }
                } else if (!line.isBlank()) {
                    String[] p = line.split(",");
                    hitObjects.add(new HitObject(
                        Integer.parseInt(p[0]),
                        Integer.parseInt(p[1]),
                        Long.parseLong(p[2])
                    ));
                }
            }
        } catch (IOException e) {
            e.printStackTrace();
        }

        hitObjects.sort((o1, o2) -> Long.compare(o1.time, o2.time));
        approachTime = (ar <= 5) ? 1800 - 120 * ar : 1200 - 150 * (ar - 5);

        // Audio loading with OGG support + ffmpeg fallback
        try {
            String audioName = getAudioFilename(osu);
            if (audioName != null) {
                File ogg = new File(dir, audioName);
                try {
                    AudioInputStream ais = AudioSystem.getAudioInputStream(ogg);
                    musicClip = AudioSystem.getClip();
                    musicClip.open(ais);
                } catch (UnsupportedAudioFileException ex) {
                    File wav = new File(dir, "__temp.wav");
                    Process p = new ProcessBuilder("ffmpeg", "-y",
                        "-i", ogg.getAbsolutePath(),
                        wav.getAbsolutePath())
                        .redirectErrorStream(true)
                        .start();
                    p.waitFor();
                    AudioInputStream ais2 = AudioSystem.getAudioInputStream(wav);
                    musicClip = AudioSystem.getClip();
                    musicClip.open(ais2);
                    wav.deleteOnExit();
                }
            }
        } catch (Exception ex) {
            System.err.println("Audio load failed: " + ex.getMessage());
        }
    }

    private String getAudioFilename(File osu) throws IOException {
        try (BufferedReader r = new BufferedReader(
             new InputStreamReader(new FileInputStream(osu), StandardCharsets.UTF_8))) {
            String line;
            while ((line = r.readLine()) != null) {
                if (line.startsWith("AudioFilename:")) {
                    return line.split(":")[1].trim();
                }
            }
        }
        return null;
    }

    @Override
    public void run() {
        createBufferStrategy(2);
        BufferStrategy bs = getBufferStrategy();
        long last = System.nanoTime(), nsPerFrame = 1_000_000_000L / 60;
        while (running) {
            long now = System.nanoTime();
            if (now - last >= nsPerFrame) {
                update();
                render(bs);
                last = now;
            } else {
                Thread.yield();
            }
        }
    }

    private void update() {
        long elapsed = (musicClip != null)
            ? musicClip.getMicrosecondPosition() / 1000
            : System.currentTimeMillis() - startTime;

        while (spawnIndex < hitObjects.size()
            && hitObjects.get(spawnIndex).time - approachTime <= elapsed) {
            spawnBullet(hitObjects.get(spawnIndex));
            spawnIndex++;
        }

        Iterator<Bullet> it = bullets.iterator();
        while (it.hasNext()) {
            if (it.next().updateAndCheck(WIDTH, HEIGHT)) {
                it.remove();
            }
        }

        if (left)  playerX = Math.max(0, playerX - playerSpeed);
        if (right) playerX = Math.min(WIDTH - playerSize, playerX + playerSpeed);
        if (up)    playerY = Math.max(0, playerY - playerSpeed);
        if (down)  playerY = Math.min(HEIGHT - playerSize, playerY + playerSpeed);
    }

    private void render(BufferStrategy bs) {
        Graphics2D g = (Graphics2D) bs.getDrawGraphics();
        g.setColor(Color.BLACK);
        g.fillRect(0, 0, WIDTH, HEIGHT);

        g.setColor(Color.WHITE);
        g.setFont(new Font("Arial", Font.BOLD, 14));
        g.drawString(mapTitle, 20, 20);

        g.setColor(Color.GREEN);
        g.fillRect(playerX, playerY, playerSize, playerSize);

        g.setColor(Color.RED);
        for (Bullet b : bullets) {
            g.fillOval((int) b.x - bulletSize/2, (int) b.y - bulletSize/2, bulletSize, bulletSize);
        }

        g.dispose();
        bs.show();
    }

    private void spawnBullet(HitObject ho) {
        double cx = playerX + playerSize / 2.0;
        double cy = playerY + playerSize / 2.0;
        double x, y;
        switch (new Random().nextInt(3)) {
            case 0: x = Math.random() * WIDTH; y = -bulletSize; break;
            case 1: x = -bulletSize;           y = Math.random() * HEIGHT; break;
            default: x = WIDTH + bulletSize;   y = Math.random() * HEIGHT; break;
        }
        double dx = (cx - x) / approachTime * bulletSpeed;
        double dy = (cy - y) / approachTime * bulletSpeed;
        bullets.add(new Bullet(x, y, dx, dy, bulletSize));
    }

    @Override
    public void keyPressed(KeyEvent e) {
        switch (e.getKeyCode()) {
            case KeyEvent.VK_A: case KeyEvent.VK_LEFT:  left = true;  break;
            case KeyEvent.VK_D: case KeyEvent.VK_RIGHT: right = true; break;
            case KeyEvent.VK_W: case KeyEvent.VK_UP:    up = true;    break;
            case KeyEvent.VK_S: case KeyEvent.VK_DOWN:  down = true;  break;
        }
    }

    @Override
    public void keyReleased(KeyEvent e) {
        switch (e.getKeyCode()) {
            case KeyEvent.VK_A: case KeyEvent.VK_LEFT:  left = false; break;
            case KeyEvent.VK_D: case KeyEvent.VK_RIGHT: right = false; break;
            case KeyEvent.VK_W: case KeyEvent.VK_UP:    up = false;    break;
            case KeyEvent.VK_S: case KeyEvent.VK_DOWN:  down = false;  break;
        }
    }

    @Override public void keyTyped(KeyEvent e) {}

    private static class HitObject {
        final int x, y; final long time;
        HitObject(int x, int y, long time) { this.x = x; this.y = y; this.time = time; }
    }

    private static class Bullet {
        double x, y, dx, dy; int size;
        Bullet(double x, double y, double dx, double dy, int size) {
            this.x = x; this.y = y; this.dx = dx; this.dy = dy; this.size = size;
        }
        boolean updateAndCheck(int w, int h) {
            x += dx; y += dy;
            return y > h + size || x < -size || x > w + size;
        }
    }
}
