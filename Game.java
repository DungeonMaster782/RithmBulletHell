import java.awt.Canvas;
import java.awt.Color;
import java.awt.Dimension;
import java.awt.Font;
import java.awt.Graphics2D;
import java.awt.Composite;
import java.awt.AlphaComposite;
import java.awt.BasicStroke;
import java.awt.RenderingHints;
import java.awt.Toolkit;
import java.awt.geom.Path2D;
import java.awt.event.KeyEvent;
import java.awt.event.KeyListener;
import java.awt.image.BufferStrategy;
import java.awt.image.BufferedImage;
import java.awt.Point;
import java.awt.Window;
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

/**
 * Основной игровой класс с uniform grid для коллизий и оптимизированным рендерингом пуль.
 */
public class Game extends Canvas implements KeyListener, Runnable {
    static {
        System.setProperty("sun.java2d.opengl", "true");
        System.setProperty("sun.java2d.d3d",    "true");
    }

    private static final int WIDTH           = Config.getScreenWidth();
    private static final int HEIGHT          = Config.getScreenHeight();
    private static final long INV_DURATION   = 3000;
    private static final int  BLINK_INTERVAL = 200;

    private final int playerSize = 40;
    private final int bulletSize = 12;
    private final int maxLives   = 5;

    // дробные скорости и хитбокс
    private final double playerSpeed = Config.getPlayerSpeed();
    private final double slowSpeed   = Config.getSlowSpeed();
    private final double bulletSpeed = Config.getBulletSpeed();
    private final int    hitboxRadius= Config.getHitboxRadius();

    // клавиши управления
    private final int keyLeft  = Config.getKeyCode("keyLeft");
    private final int keyRight = Config.getKeyCode("keyRight");
    private final int keyUp    = Config.getKeyCode("keyUp");
    private final int keyDown  = Config.getKeyCode("keyDown");

    // текстуры: игрок и фон
    private final BufferedImage playerTexture = Config.getPlayerTexture();
    private BufferedImage backgroundImage = null;
    private final float backgroundDim = Config.getBackgroundDim();

    // параметры карты
    private double approachTime, sliderMultiplier, beatLength;

    // аудио и тайминг
    private Clip   musicClip;
    private long   startTime;
    private boolean running, paused;

    // состояние игрока
    private double playerX, playerY;
    private boolean left, right, up, down, slowMode, invulnerable;
    private int lives;
    private long lastDamageTime;

    private String mapTitle = "No map selected";
    private String currentSetName, currentOsuFile;

    // HIT-объекты
    private final List<OsuParser.HitObject> hitObjects = new ArrayList<>();
    private int spawnIndex = 0;

    // слайдер-лазеры и их пули
    private final List<SliderLaser> sliderLasers       = new ArrayList<>();
    private final List<ScheduledSpawn> scheduledSpawns  = new ArrayList<>();
    private int scheduleIndex = 0;

    // пули и uniform grid для коллизий
    private final Deque<Bullet> bulletPool = new ArrayDeque<>();
    private final List<Bullet>  bullets    = new ArrayList<>();
    private final int CELL = 100;
    private final int cols = (WIDTH + CELL - 1) / CELL;
    private final int rows = (HEIGHT + CELL - 1) / CELL;
    @SuppressWarnings("unchecked")
    private final List<Bullet>[][] grid = new List[cols][rows];

    // оптимизированный спрайт для пули
    private final BufferedImage bulletSprite;

    // HUD
    private final Font        hudFont          = new Font("Arial", Font.BOLD, 14);
    private final BasicStroke hitboxStroke     = new BasicStroke(2f);
    private final Composite   defaultComposite = AlphaComposite.getInstance(AlphaComposite.SRC_OVER,1f);
    private final Composite   hitboxComposite  = AlphaComposite.getInstance(AlphaComposite.SRC_OVER,0.5f);

    private boolean aaDisabled = false;

    public Game() {
        setPreferredSize(new Dimension(WIDTH, HEIGHT));
        setBackground(Color.BLACK);
        initGrid();
        bulletSprite = createBulletSprite();
        addKeyListener(this);
        setFocusable(true);
        requestFocus();
        resetPlayer();
    }

    private void initGrid() {
        for (int x = 0; x < cols; x++)
            for (int y = 0; y < rows; y++)
                grid[x][y] = new ArrayList<>();
    }

    private BufferedImage createBulletSprite() {
        BufferedImage img = new BufferedImage(bulletSize, bulletSize, BufferedImage.TYPE_INT_ARGB);
        Graphics2D g = img.createGraphics();
        g.setColor(Color.RED);
        g.fillOval(0, 0, bulletSize, bulletSize);
        g.dispose();
        return img;
    }

    @Override public void addNotify() {
        super.addNotify();
        SwingUtilities.invokeLater(() -> {
            Window w = SwingUtilities.getWindowAncestor(this);
            if (w instanceof JFrame) {
                JFrame f = (JFrame)w;
                f.setResizable(false);
                f.getContentPane().setBackground(Color.BLACK);
            }
        });
    }

    private void resetPlayer() {
        playerX = WIDTH/2.0 - playerSize/2.0;
        playerY = HEIGHT - 60.0;
        lives = maxLives;
        left=right=up=down=slowMode=invulnerable=false;
        lastDamageTime = 0;
    }

    public void setMap(String setName, String osuFile) {
        stopMusic();
        currentSetName = setName;
        currentOsuFile = osuFile;
        mapTitle = setName + " | " + osuFile;
        hitObjects.clear(); bullets.clear(); scheduledSpawns.clear(); sliderLasers.clear(); bulletPool.clear();
        clearGrid(); spawnIndex = scheduleIndex = 0;
        resetPlayer();

        OsuParser.OsuMapData mapData = new OsuParser().parse(
            new File(Main.BEATMAPS_DIR, setName), osuFile
        );
        approachTime     = mapData.approachTime;
        sliderMultiplier = mapData.sliderMultiplier;
        beatLength       = mapData.beatLength;
        musicClip        = mapData.musicClip;
        hitObjects.addAll(mapData.hitObjects);

        loadBackground(setName);
        scheduleSliderLasers(mapData);
        startMusic();
        startTime = System.currentTimeMillis();
        if (!running) { running = true; new Thread(this, "GameLoop").start(); }
    }

    private void clearGrid() {
        for (int x = 0; x < cols; x++)
            for (int y = 0; y < rows; y++)
                grid[x][y].clear();
    }

    private void loadBackground(String setName) {
        backgroundImage = null;
        try {
            File dir = new File(Main.BEATMAPS_DIR, setName);
            File[] imgs = dir.listFiles((d,n) -> n.toLowerCase().matches(".*\\.(jpg|png|jpeg|bmp)$"));
            if (imgs != null && imgs.length > 0) {
                backgroundImage = ImageIO.read(imgs[0]);
            }
        } catch (IOException ignored) {}
    }

    private void scheduleSliderLasers(OsuParser.OsuMapData mapData) {
        double sliderVelocity = sliderMultiplier * 100;
        for (OsuParser.TempSlider ts : mapData.tempSliders) {
            double singleDur = ts.pixelLen / sliderVelocity * beatLength;
            double totalDur  = singleDur * ts.repeats;
            int nPts = ts.ctrlPts.size();
            for (int k = 1; k < nPts; k++) {
                double frac = (double)k/(nPts-1);
                long ctrlTime = (long)(ts.time + frac*singleDur);
                long offset = ctrlTime - (long)approachTime;
                ScheduledSpawn ss = new ScheduledSpawn(); ss.offset = offset;
                ss.x = ts.ctrlPts.get(k).x; ss.y = ts.ctrlPts.get(k).y;
                scheduledSpawns.add(ss);
            }
            sliderLasers.add(new SliderLaser(ts.ctrlPts, ts.time, approachTime, totalDur));
        }
        scheduledSpawns.sort(Comparator.comparingLong(s->s.offset));
    }

    private void stopMusic() {
        if (musicClip!=null) { musicClip.stop(); musicClip.close(); musicClip=null; }
    }
    private void startMusic() {
        if (musicClip!=null) { musicClip.setFramePosition(0); musicClip.start(); }
    }

    @Override public void run() {
        createBufferStrategy(3);
        BufferStrategy bs = getBufferStrategy();
        long lastTime = System.nanoTime();
        int fpsLimit = Config.getMaxFPS();
        long nsPerFrame = fpsLimit>0 ? 1_000_000_000L/fpsLimit : 0;
        while (running) {
            long now = System.nanoTime();
            boolean doFrame = fpsLimit<=0 || now-lastTime>=nsPerFrame;
            if (doFrame) {
                lastTime = now; update(); renderFrame(bs);
                if (Config.isVSyncEnabled()) Toolkit.getDefaultToolkit().sync();
            } else {
                long sleepNs = nsPerFrame - (now-lastTime);
                if (sleepNs>0) try { Thread.sleep(sleepNs/1_000_000,(int)(sleepNs%1_000_000)); } catch (InterruptedException ignored){}
                else Thread.yield();
            }
        }
    }

    private void update() {
        if (paused) return;
        long elapsed = musicClip!=null? musicClip.getMicrosecondPosition()/1000 : System.currentTimeMillis()-startTime;
        if (invulnerable && elapsed-lastDamageTime>=INV_DURATION) invulnerable=false;
        // spawn hit objects
        while (spawnIndex<hitObjects.size() && hitObjects.get(spawnIndex).time-approachTime<=elapsed) {
            spawnBullet(hitObjects.get(spawnIndex++));
        }
        // spawn slider bullets
        while (scheduleIndex<scheduledSpawns.size() && elapsed>=scheduledSpawns.get(scheduleIndex).offset) {
            ScheduledSpawn ss = scheduledSpawns.get(scheduleIndex++);
            spawnSliderBullet(ss.x, ss.y);
        }
        // update bullets
        for (int i=bullets.size()-1;i>=0;i--) {
            Bullet b = bullets.get(i);
            double oldX=b.getX(), oldY=b.getY();
            int oldGX=(int)(oldX/CELL), oldGY=(int)(oldY/CELL);
            boolean removed = b.updateAndCheck(WIDTH,HEIGHT);
            if (removed) {
                bulletPool.addLast(bullets.remove(i));
                if (oldGX>=0&&oldGX<cols&&oldGY>=0&&oldGY<rows) grid[oldGX][oldGY].remove(b);
                continue;
            }
            int newGX=(int)(b.getX()/CELL), newGY=(int)(b.getY()/CELL);
            if (newGX!=oldGX||newGY!=oldGY) {
                if (oldGX>=0&&oldGX<cols&&oldGY>=0&&oldGY<rows) grid[oldGX][oldGY].remove(b);
                if (newGX>=0&&newGX<cols&&newGY>=0&&newGY<rows) grid[newGX][newGY].add(b);
            }
        }
        // collision via grid
        int pcx=(int)((playerX+playerSize/2.0)/CELL), pcy=(int)((playerY+playerSize/2.0)/CELL);
        for(int dx=-1;dx<=1;dx++) for(int dy=-1;dy<=1;dy++) {
            int gx=pcx+dx, gy=pcy+dy;
            if (gx<0||gy<0||gx>=cols||gy>=rows) continue;
            for(Bullet b: grid[gx][gy]) {
                if (!invulnerable) {
                    double cx=playerX+playerSize/2.0, cy=playerY+playerSize/2.0;
                    double dx2=b.getX()-cx, dy2=b.getY()-cy, rsum=b.getSize()/2.0+hitboxRadius;
                    if (dx2*dx2+dy2*dy2<=rsum*rsum) {
                        invulnerable=true; lastDamageTime = elapsed;
                        lives--; if (lives<=0) { gameOver(); return; }
                    }
                }
            }
        }
        // move player
        double spd = slowMode? slowSpeed: playerSpeed;
        if (left)  playerX=Math.max(0,            playerX-spd);
        if (right) playerX=Math.min(WIDTH-playerSize, playerX+spd);
        if (up)    playerY=Math.max(0,            playerY-spd);
        if (down)  playerY=Math.min(HEIGHT-playerSize,playerY+spd);
    }

    private void renderFrame(BufferStrategy bs) {
        Graphics2D g=(Graphics2D)bs.getDrawGraphics();
        if (!aaDisabled) {
            g.setRenderingHint(RenderingHints.KEY_ANTIALIASING,RenderingHints.VALUE_ANTIALIAS_OFF);
            g.setRenderingHint(RenderingHints.KEY_TEXT_ANTIALIASING,RenderingHints.VALUE_TEXT_ANTIALIAS_OFF);
            aaDisabled=true;
        }
        // background
        if (backgroundImage!=null) {
            g.drawImage(backgroundImage,0,0,WIDTH,HEIGHT,null);
            Composite old=g.getComposite();
            g.setComposite(AlphaComposite.getInstance(AlphaComposite.SRC_OVER,backgroundDim));
            g.setColor(Color.BLACK); g.fillRect(0,0,WIDTH,HEIGHT);
            g.setComposite(old);
        } else {
            g.setColor(Color.BLACK); g.fillRect(0,0,WIDTH,HEIGHT);
        }
        long elapsed=musicClip!=null?musicClip.getMicrosecondPosition()/1000:System.currentTimeMillis()-startTime;
        // HUD
        g.setColor(Color.WHITE); g.setFont(hudFont);
        g.drawString(mapTitle,20,20);
        g.drawString("Lives: "+lives,WIDTH-100,20);
        // player
        boolean draw=true;
        if (invulnerable && elapsed-lastDamageTime<INV_DURATION)
            if(((elapsed-lastDamageTime)/BLINK_INTERVAL)%2==0) draw=false;
        int ix=(int)playerX, iy=(int)playerY;
        if(draw) {
            if(playerTexture!=null) g.drawImage(playerTexture,ix,iy,playerSize,playerSize,null);
            else g.fillRect(ix,iy,playerSize,playerSize);
        }
        int cxi=ix+playerSize/2, cyi=iy+playerSize/2;
        g.setComposite(hitboxComposite); g.setStroke(hitboxStroke);
        g.drawOval(cxi-hitboxRadius,cyi-hitboxRadius,hitboxRadius*2,hitboxRadius*2);
        g.setComposite(defaultComposite);
        // bullets
        for(Bullet b: bullets) {
            int bx=(int)(b.getX()-b.getSize()/2), by=(int)(b.getY()-b.getSize()/2);
            g.drawImage(bulletSprite,bx,by,null);
        }
        // sliders
        for(SliderLaser sl:sliderLasers) sl.render(g,WIDTH,HEIGHT,(int)(musicClip!=null?musicClip.getMicrosecondPosition()/1000:System.currentTimeMillis()-startTime));
        g.dispose(); bs.show();
    }

    private void spawnBullet(OsuParser.HitObject ho) {
        Bullet b=bulletPool.pollFirst(); if(b==null) b=new Bullet(bulletSize);
        b.initRandom(WIDTH,playerX+playerSize/2.0,playerY+playerSize/2.0,bulletSpeed,(long)approachTime);
        bullets.add(b);
        int gx=(int)(b.getX()/CELL), gy=(int)(b.getY()/CELL);
        if(gx>=0&&gx<cols&&gy>=0&&gy<rows) grid[gx][gy].add(b);
    }
    private void spawnSliderBullet(int sx,int sy) {
        Bullet b=bulletPool.pollFirst(); if(b==null) b=new Bullet(bulletSize);
        b.initAt(sx,sy,playerX+playerSize/2.0,playerY+playerSize/2.0,bulletSpeed,(long)approachTime);
        bullets.add(b);
        int gx=(int)(b.getX()/CELL), gy=(int)(b.getY()/CELL);
        if(gx>=0&&gx<cols&&gy>=0&&gy<rows) grid[gx][gy].add(b);
    }

    private void gameOver() {
        running=false; SwingUtilities.invokeLater(() -> {
            int res=JOptionPane.showOptionDialog(this,"You lost!","Game Over",
                JOptionPane.YES_NO_OPTION,JOptionPane.INFORMATION_MESSAGE,
                null,new String[]{"Retry","Exit"},"Retry");
            if(res==JOptionPane.YES_OPTION) setMap(currentSetName,currentOsuFile);
            else { Window w=SwingUtilities.getWindowAncestor(this); if(w!=null) w.dispose(); System.exit(0);}
        });
    }

    @Override public void keyPressed(KeyEvent e) {
        int code=e.getKeyCode();
        if(code==keyLeft)         left=true;
        else if(code==keyRight)   right=true;
        else if(code==keyUp)      up=true;
        else if(code==keyDown)    down=true;
        else if(code==KeyEvent.VK_SHIFT) slowMode=true;
        else if(code==KeyEvent.VK_P) {
            if(musicClip!=null) { paused=!paused; if(paused) musicClip.stop(); else musicClip.start(); }
        } else if(code==KeyEvent.VK_ESCAPE) {
            Window w=SwingUtilities.getWindowAncestor(this); if(w!=null) w.dispose(); System.exit(0);
        }
    }
    @Override public void keyReleased(KeyEvent e) {
        int code=e.getKeyCode();
        if(code==keyLeft)         left=false;
        else if(code==keyRight)   right=false;
        else if(code==keyUp)      up=false;
        else if(code==keyDown)    down=false;
        else if(code==KeyEvent.VK_SHIFT) slowMode=false;
    }
    @Override public void keyTyped(KeyEvent e) { }

    private static class ScheduledSpawn {
        long offset;
        int x,y;
    }
}
