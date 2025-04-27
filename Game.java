import java.awt.Canvas;
import java.awt.Color;
import java.awt.Dimension;
import java.awt.Font;
import java.awt.Graphics2D;
import java.awt.image.BufferStrategy;
import java.awt.event.KeyEvent;
import java.awt.event.KeyListener;
import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;
import java.util.Properties;
import java.util.Random;
import javax.imageio.ImageIO;
import java.awt.image.BufferedImage;
import javax.sound.sampled.AudioInputStream;
import javax.sound.sampled.AudioSystem;
import javax.sound.sampled.Clip;
import javax.sound.sampled.UnsupportedAudioFileException;
import javax.swing.JOptionPane;
import javax.swing.SwingUtilities;
import java.awt.Window;

public class Game extends Canvas implements KeyListener, Runnable {
    private static int WIDTH = 800;
    private static int HEIGHT = 600;

    private long startTime;
    private double approachTime;
    private final List<HitObject> hitObjects = new ArrayList<>();
    private int spawnIndex;

    private Clip musicClip;

    private int playerX;
    private int playerY;
    private final int playerSize = 40;
    private int playerSpeed;

    private final List<Bullet> bullets = new ArrayList<>();
    private double bulletSpeed;
    private final int bulletSize = 12;

    private boolean running;
    private boolean paused;
    private boolean left, right, up, down;

    private String mapTitle = "No map selected";
    private String currentSetName;
    private String currentOsuFile;

    private int lives;
    private final int maxLives = 5;
    private boolean invulnerable;
    private long lastDamageTime;
    private static final long INVULNERABLE_DURATION = 3000;

    private BufferedImage hitboxTexture;
    private int hitboxRadius;

    public Game() {
        loadConfig();
        setPreferredSize(new Dimension(WIDTH, HEIGHT));
        addKeyListener(this);
        setFocusable(true);
        requestFocus();

        playerX = WIDTH / 2 - playerSize / 2;
        playerY = HEIGHT - 60;
        lives = maxLives;
    }

    private void loadConfig() {
        Properties props = new Properties();
        File cfgFile = new File("config.properties");
        boolean updated = false;
        if (cfgFile.exists()) {
            try (FileInputStream in = new FileInputStream(cfgFile)) {
                props.load(in);
            } catch (IOException e) {
                e.printStackTrace();
            }
        }
        if (!props.containsKey("playerSpeed")) { props.setProperty("playerSpeed", "5"); updated = true; }
        if (!props.containsKey("bulletSpeed")) { props.setProperty("bulletSpeed", "4"); updated = true; }
        if (!props.containsKey("screenWidth")) { props.setProperty("screenWidth", String.valueOf(WIDTH)); updated = true; }
        if (!props.containsKey("screenHeight")) { props.setProperty("screenHeight", String.valueOf(HEIGHT)); updated = true; }
        if (!props.containsKey("hitboxTexture")) { props.setProperty("hitboxTexture", ""); updated = true; }
        if (!props.containsKey("hitboxRadius")) { props.setProperty("hitboxRadius", String.valueOf(playerSize / 4)); updated = true; }
        if (updated) {
            try (FileOutputStream out = new FileOutputStream(cfgFile)) {
                props.store(out, null);
            } catch (IOException e) {
                e.printStackTrace();
            }
        }
        playerSpeed = Integer.parseInt(props.getProperty("playerSpeed", "5"));
        bulletSpeed = Double.parseDouble(props.getProperty("bulletSpeed", "4"));
        try {
            WIDTH = Integer.parseInt(props.getProperty("screenWidth", String.valueOf(WIDTH)));
            HEIGHT = Integer.parseInt(props.getProperty("screenHeight", String.valueOf(HEIGHT)));
        } catch (NumberFormatException e) {
            System.err.println("Invalid resolution in config, using defaults.");
        }
        String texPath = props.getProperty("hitboxTexture", "");
        if (!texPath.isEmpty()) {
            try {
                hitboxTexture = ImageIO.read(new File(texPath));
            } catch (IOException e) {
                e.printStackTrace();
            }
        }
        try {
            hitboxRadius = Integer.parseInt(props.getProperty("hitboxRadius", String.valueOf(playerSize / 4)));
        } catch (NumberFormatException e) {
            hitboxRadius = playerSize / 4;
        }
    }

    public void setMap(String setName, String osuFile) {
        if (musicClip != null) {
            musicClip.stop();
            musicClip.close();
        }
        currentSetName = setName;
        currentOsuFile = osuFile;
        mapTitle = setName + " | " + osuFile;
        lives = maxLives;
        invulnerable = false;
        lastDamageTime = 0;
        spawnIndex = 0;
        hitObjects.clear();
        bullets.clear();
        parseOsu(new File(Main.BEATMAPS_DIR, setName), osuFile);
        if (musicClip != null) {
            musicClip.setFramePosition(0);
            musicClip.start();
        }
        startTime = System.currentTimeMillis();
        if (!running) {
            running = true;
            new Thread(this, "GameLoop").start();
        }
    }

    private void parseOsu(File dir, String fileName) {
        hitObjects.clear();
        approachTime = 1500;
        double ar = 5;
        File osuFile = new File(dir, fileName);
        try (BufferedReader reader = new BufferedReader(
                new InputStreamReader(new FileInputStream(osuFile), StandardCharsets.UTF_8))) {
            String line;
            boolean inDiff = false, inHits = false;
            while ((line = reader.readLine()) != null) {
                if (!inHits) {
                    if (line.equals("[Difficulty]")) inDiff = true;
                    else if (inDiff) {
                        if (line.startsWith("ApproachRate:")) ar = Double.parseDouble(line.split(":")[1].trim());
                        else if (line.startsWith("[")) inDiff = false;
                    } else if (line.equals("[HitObjects]")) inHits = true;
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
        hitObjects.sort((a, b) -> Long.compare(a.time, b.time));
        approachTime = (ar <= 5) ? 1800 - 120 * ar : 1200 - 150 * (ar - 5);
        try {
            String audioName = getAudioFilename(osuFile);
            if (audioName != null) {
                File audioFile = new File(dir, audioName);
                try {
                    AudioInputStream ais = AudioSystem.getAudioInputStream(audioFile);
                    musicClip = AudioSystem.getClip();
                    musicClip.open(ais);
                } catch (UnsupportedAudioFileException ex) {
                    File ogg = new File(dir, audioName);
                    File wav = new File(dir, "__temp.wav");
                    Process p = new ProcessBuilder("ffmpeg", "-y", "-i",
                            ogg.getAbsolutePath(), wav.getAbsolutePath())
                            .redirectErrorStream(true).start();
                    p.waitFor();
                    AudioInputStream ais2 = AudioSystem.getAudioInputStream(wav);
                    musicClip = AudioSystem.getClip();
                    musicClip.open(ais2);
                    wav.deleteOnExit();
                }
            }
        } catch (Exception e) {
            System.err.println("Audio load failed: " + e.getMessage());
        }
    }

    private String getAudioFilename(File osu) throws IOException {
        try (BufferedReader reader = new BufferedReader(
                new InputStreamReader(new FileInputStream(osu), StandardCharsets.UTF_8))) {
            String line;
            while ((line = reader.readLine()) != null) {
                if (line.startsWith("AudioFilename:")) {
                    return line.split(":", 2)[1].trim();
                }
            }
        }
        return null;
    }

    @Override
    public void run() {
        createBufferStrategy(2);
        BufferStrategy bs = getBufferStrategy();
        long last = System.nanoTime();
        long nsPerFrame = 1_000_000_000L / 60;
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
        if (paused) return;
        long elapsed = (musicClip != null)
                ? musicClip.getMicrosecondPosition() / 1000
                : System.currentTimeMillis() - startTime;
        if (invulnerable && elapsed - lastDamageTime >= INVULNERABLE_DURATION) {
            invulnerable = false;
        }
        while (spawnIndex < hitObjects.size()
                && hitObjects.get(spawnIndex).time - approachTime <= elapsed) {
            spawnBullet(hitObjects.get(spawnIndex));
            spawnIndex++;
        }
        Iterator<Bullet> it = bullets.iterator();
        while (it.hasNext()) {
            Bullet b = it.next();
            boolean out = b.updateAndCheck(WIDTH, HEIGHT);
            if (out) { it.remove(); continue; }
            if (!invulnerable) {
                double cx = playerX + playerSize / 2.0;
                double cy = playerY + playerSize / 2.0;
                double dx = b.x - cx;
                double dy = b.y - cy;
                double distSq = dx * dx + dy * dy;
                double rSum = b.size / 2.0 + hitboxRadius;
                if (distSq <= rSum * rSum) {
                    it.remove();
                    lives--;
                    invulnerable = true;
                    lastDamageTime = elapsed;
                    if (lives <= 0) {
                        gameOver();
                        return;
                    }
                }
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
        g.drawString("Lives: " + lives, WIDTH - 100, 20);

        int cx = playerX + playerSize / 2;
        int cy = playerY + playerSize / 2;
        if (hitboxTexture != null) {
            g.drawImage(hitboxTexture, cx - hitboxRadius, cy - hitboxRadius,
                    hitboxRadius * 2, hitboxRadius * 2, null);
        } else {
            g.setColor(Color.WHITE);
            g.fillOval(cx - hitboxRadius, cy - hitboxRadius,
                    hitboxRadius * 2, hitboxRadius * 2);
        }

        g.setColor(Color.RED);
        for (Bullet b : bullets) {
            g.fillOval((int) b.x - bulletSize / 2, (int) b.y - bulletSize / 2,
                    bulletSize, bulletSize);
        }

        if (paused) {
            g.setColor(Color.YELLOW);
            g.setFont(new Font("Arial", Font.BOLD, 48));
            g.drawString("PAUSED", WIDTH / 2 - 100, HEIGHT / 2);
        }

        g.dispose();
        bs.show();
    }

    private void spawnBullet(HitObject ho) {
        double cx = playerX + playerSize / 2.0;
        double cy = playerY + playerSize / 2.0;
        double x, y;
        switch (new Random().nextInt(3)) {
            case 0 -> { x = Math.random() * WIDTH; y = -bulletSize; }
            case 1 -> { x = -bulletSize; y = Math.random() * HEIGHT; }
            default -> { x = WIDTH + bulletSize; y = Math.random() * HEIGHT; }
        }
        double dx = (cx - x) / approachTime * bulletSpeed;
        double dy = (cy - y) / approachTime * bulletSpeed;
        bullets.add(new Bullet(x, y, dx, dy, bulletSize));
    }

    private void gameOver() {
        running = false;
        SwingUtilities.invokeLater(() -> {
            int result = JOptionPane.showOptionDialog(this,
                "You lost!",
                "Game Over",
                JOptionPane.YES_NO_OPTION,
                JOptionPane.INFORMATION_MESSAGE,
                null,
                new String[]{"Retry", "Exit"},
                "Retry");
            if (result == JOptionPane.YES_OPTION) {
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
        switch (e.getKeyCode()) {
            case KeyEvent.VK_A, KeyEvent.VK_LEFT  -> left  = true;
            case KeyEvent.VK_D, KeyEvent.VK_RIGHT -> right = true;
            case KeyEvent.VK_W, KeyEvent.VK_UP    -> up    = true;
            case KeyEvent.VK_S, KeyEvent.VK_DOWN  -> down  = true;

            case KeyEvent.VK_P -> {
                paused = !paused;
                if (musicClip != null) {
                    if (paused) {
                        musicClip.stop();
                    } else {
                        musicClip.start();
                    }
                }
            }

        case KeyEvent.VK_ESCAPE -> {
            Window w = SwingUtilities.getWindowAncestor(this);
            if (w != null) w.dispose();
            System.exit(0);
        }
    }
}


    @Override
    public void keyReleased(KeyEvent e) {
        switch (e.getKeyCode()) {
            case KeyEvent.VK_A, KeyEvent.VK_LEFT -> left = false;
            case KeyEvent.VK_D, KeyEvent.VK_RIGHT -> right = false;
            case KeyEvent.VK_W, KeyEvent.VK_UP -> up = false;
            case KeyEvent.VK_S, KeyEvent.VK_DOWN -> down = false;
        }
    }

    @Override
    public void keyTyped(KeyEvent e) {}

    private static class HitObject {
        final int x, y;
        final long time;
        HitObject(int x, int y, long time) {
            this.x = x;
            this.y = y;
            this.time = time;
        }
    }

    private static class Bullet {
        double x, y, dx, dy;
        int size;
        Bullet(double x, double y, double dx, double dy, int size) {
            this.x = x;
            this.y = y;
            this.dx = dx;
            this.dy = dy;
            this.size = size;
        }
        boolean updateAndCheck(int w, int h) {
            x += dx;
            y += dy;
            return y > h + size || x < -size || x > w + size;
        }
    }
}
