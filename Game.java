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
import java.awt.Point;
import java.awt.Window;
import java.io.*;
import java.util.*;
import javax.sound.sampled.*;
import javax.sound.sampled.FloatControl;
import javax.swing.JFrame;
import javax.swing.JOptionPane;
import javax.swing.SwingUtilities;

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

    private final int    playerSpeed = Config.getPlayerSpeed();
    private final double bulletSpeed = Config.getBulletSpeed();
    private final int    slowSpeed   = Config.getSlowSpeed();
    private final int    hitboxRadius= Config.getHitboxRadius();
    private final int    keyLeft     = Config.getKeyCode("keyLeft");
    private final int    keyRight    = Config.getKeyCode("keyRight");
    private final int    keyUp       = Config.getKeyCode("keyUp");
    private final int    keyDown     = Config.getKeyCode("keyDown");
    private final java.awt.image.BufferedImage playerTexture = Config.getPlayerTexture();

    private double approachTime, sliderMultiplier, beatLength;

    private long   startTime;
    private Clip   musicClip;
    private boolean running, paused;
    private boolean left, right, up, down, slow;
    private int     playerX, playerY, lives;
    private boolean invulnerable;
    private long    lastDamageTime;
    private String  mapTitle = "No map selected";
    private String  currentSetName, currentOsuFile;

    private final List<HitObject> hitObjects        = new ArrayList<>();
    private int spawnIndex = 0;

    private final List<SliderLaser> sliderLasers      = new ArrayList<>();
    private final List<ScheduledSpawn> scheduledSpawns = new ArrayList<>();
    private int scheduleIndex = 0;

    private final List<Bullet> bullets     = new ArrayList<>();
    private final Deque<Bullet> bulletPool = new ArrayDeque<>();

    private final Font        hudFont          = new Font("Arial", Font.BOLD, 14);
    private final BasicStroke hitboxStroke     = new BasicStroke(2f);
    private final Composite   defaultComposite = AlphaComposite.getInstance(AlphaComposite.SRC_OVER,1f);
    private final Composite   hitboxComposite  = AlphaComposite.getInstance(AlphaComposite.SRC_OVER,0.5f);

    private boolean aaDisabled = false;

    public Game() {
        setPreferredSize(new Dimension(WIDTH, HEIGHT));
        setBackground(Color.BLACK);
        addKeyListener(this);
        setFocusable(true);
        requestFocus();
        resetPlayer();
    }

    @Override
    public void addNotify() {
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
        playerX = WIDTH/2 - playerSize/2;
        playerY = HEIGHT - 60;
        lives         = maxLives;
        invulnerable  = false;
        lastDamageTime= 0;
    }

    public void setMap(String setName, String osuFile) {
        stopMusic();
        currentSetName = setName;
        currentOsuFile = osuFile;
        mapTitle       = setName + " | " + osuFile;
        hitObjects.clear();
        bullets.clear();
        sliderLasers.clear();
        scheduledSpawns.clear();
        bulletPool.clear();
        spawnIndex = scheduleIndex = 0;
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
        approachTime     = 1500;
        sliderMultiplier = 1.4;
        beatLength       = 500;

        class TempSlider {
            long time; int repeats; double pixelLen; List<Point> ctrlPts;
        }
        List<TempSlider> tempSliders = new ArrayList<>();

        boolean inDiff=false, inTiming=false, inHits=false;
        File osu = new File(dir, fileName);
        try (BufferedReader r = new BufferedReader(new InputStreamReader(new FileInputStream(osu), "UTF-8"))) {
            String line;
            while ((line = r.readLine()) != null) {
                if (!inHits && !inTiming) {
                    if (line.equals("[Difficulty]"))    { inDiff=true; continue; }
                    if (line.equals("[TimingPoints]"))  { inTiming=true; inDiff=false; continue; }
                }
                if (inDiff) {
                    if (line.startsWith("ApproachRate:"))
                        approachTime = 1800 - 120 * Double.parseDouble(line.split(":",2)[1].trim());
                    if (line.startsWith("SliderMultiplier:"))
                        sliderMultiplier = Double.parseDouble(line.split(":",2)[1].trim());
                    if (line.startsWith("[")) inDiff=false;
                    continue;
                }
                if (inTiming) {
                    if (line.startsWith("[")) { inTiming=false; continue; }
                    if (!line.isBlank()) {
                        String[] tp = line.split(",");
                        if (tp.length>6 && Integer.parseInt(tp[6].trim())==1) {
                            beatLength = Double.parseDouble(tp[1].trim());
                            inTiming=false;
                        }
                    }
                    continue;
                }
                if (!inHits && line.equals("[HitObjects]")) { inHits=true; continue; }
                if (inHits && line.isBlank()) continue;
                if (inHits) {
                    String[] p = line.split(",");
                    int x = Integer.parseInt(p[0]), y = Integer.parseInt(p[1]);
                    long t = Long.parseLong(p[2]);
                    int type = Integer.parseInt(p[3]);
                    if ((type & 2)!=0 && p.length>7) {
                        TempSlider ts = new TempSlider();
                        ts.time     = t;
                        ts.repeats  = Integer.parseInt(p[6]);
                        ts.pixelLen = Double.parseDouble(p[7]);
                        String[] sd = p[5].split("\\|");
                        ts.ctrlPts  = new ArrayList<>();
                        ts.ctrlPts.add(new Point(x,y));
                        for (int i=1;i<sd.length;i++){
                            String[] xy=sd[i].split(":");
                            ts.ctrlPts.add(new Point(
                                Integer.parseInt(xy[0]),
                                Integer.parseInt(xy[1])
                            ));
                        }
                        tempSliders.add(ts);
                    } else if ((type & 1)!=0) {
                        hitObjects.add(new HitObject(x,y,t));
                    }
                }
            }
        } catch (IOException ex) {
            ex.printStackTrace();
        }

        double sliderVelocity = sliderMultiplier * 100;
        for (TempSlider ts: tempSliders) {
            double singleDur = ts.pixelLen/sliderVelocity*beatLength;
            double totalDur  = singleDur*ts.repeats;
            int nPts = ts.ctrlPts.size();
            for (int k=1;k<nPts;k++){
                double frac = k/(double)(nPts-1);
                long ctrlTime = (long)(ts.time + frac*singleDur);
                long offset   = ctrlTime - (long)approachTime;
                ScheduledSpawn ss = new ScheduledSpawn();
                ss.offset = offset;
                ss.x      = ts.ctrlPts.get(k).x;
                ss.y      = ts.ctrlPts.get(k).y;
                scheduledSpawns.add(ss);
            }
            sliderLasers.add(new SliderLaser(
                ts.ctrlPts, ts.time, (long)approachTime, totalDur
            ));
        }
        scheduledSpawns.sort(Comparator.comparingLong(s->s.offset));

        // === AUDIO LOADING WITH OGG SUPPORT & VOLUME CONTROL ===
        try {
    String audioName;
    try {
        audioName = getAudioFilename(osu);
    } catch (IOException e) {
        e.printStackTrace();
        audioName = null;
    }
    if (audioName != null) {
        File audioFile = new File(dir, audioName);
        AudioInputStream ais = null;
        try {
            // native attempt (OGG/MP3)
            ais = AudioSystem.getAudioInputStream(audioFile);
        } catch (UnsupportedAudioFileException | IOException e1) {
            // fallback: ffmpeg → WAV
            File wav = new File(dir, "__temp.wav");
            try {
                new ProcessBuilder("ffmpeg", "-y",
                        "-i", audioFile.getAbsolutePath(),
                        wav.getAbsolutePath())
                    .inheritIO()
                    .start()
                    .waitFor();  // InterruptedException caught below
                ais = AudioSystem.getAudioInputStream(wav);
                wav.deleteOnExit();
            } catch (IOException | InterruptedException | UnsupportedAudioFileException e2) {
                e2.printStackTrace();
                ais = null;
            }
        }
        if (ais != null) {
            try {
                musicClip = AudioSystem.getClip();
                musicClip.open(ais);  // теперь IOException и LineUnavailableException в catch-е
                // регулировка громкости
                if (musicClip.isControlSupported(FloatControl.Type.MASTER_GAIN)) {
                    FloatControl gain = (FloatControl) musicClip.getControl(FloatControl.Type.MASTER_GAIN);
                    float vol = Config.getMusicVolume();
                    float dB = 20f * (float)Math.log10(Math.max(vol, 0.0001f));
                    gain.setValue(dB);
                }
            } catch (LineUnavailableException | IOException e3) {
                e3.printStackTrace();
            }
        }
    }
} catch (Exception e) {
    // На всякий случай ловим всё остальное
    e.printStackTrace();
}
    }

    private String getAudioFilename(File osu) throws IOException {
        try (BufferedReader r = new BufferedReader(new InputStreamReader(new FileInputStream(osu), "UTF-8"))) {
            String line;
            while ((line = r.readLine()) != null) {
                if (line.startsWith("AudioFilename:")) {
                    return line.split(":",2)[1].trim();
                }
            }
        }
        return null;
    }

    @Override public void run() {
        createBufferStrategy(2);
        BufferStrategy bs = getBufferStrategy();
        long lastTime = System.nanoTime();
        int fpsLimit = Config.getMaxFPS();
        long nsPerFrame = fpsLimit>0 ? 1_000_000_000L/fpsLimit : 0;

        while (running) {
            long now = System.nanoTime();
            boolean doFrame = fpsLimit<=0 || now-lastTime>=nsPerFrame;
            if (doFrame) {
                lastTime = now;
                update();
                renderFrame(bs);
                if (Config.isVSyncEnabled()) Toolkit.getDefaultToolkit().sync();
            } else {
                long sleepNs = nsPerFrame - (now-lastTime);
                if (sleepNs>0) {
                    try { Thread.sleep(sleepNs/1_000_000,(int)(sleepNs%1_000_000)); }
                    catch(InterruptedException ignored){}
                } else Thread.yield();
            }
        }
    }

    private void update() {
        if (paused) return;
        long elapsed = (musicClip != null)
            ? musicClip.getMicrosecondPosition()/1000
            : System.currentTimeMillis()-startTime;

        if (invulnerable && elapsed-lastDamageTime>=INV_DURATION)
            invulnerable=false;

        while (spawnIndex<hitObjects.size()
            && hitObjects.get(spawnIndex).time-(long)approachTime<=elapsed) {
            spawnBullet(hitObjects.get(spawnIndex++));
        }
        while (scheduleIndex<scheduledSpawns.size()
            && elapsed>=scheduledSpawns.get(scheduleIndex).offset) {
            ScheduledSpawn ss=scheduledSpawns.get(scheduleIndex++);
            spawnSliderBullet(ss.x, ss.y);
        }

        for (int i=bullets.size()-1;i>=0;i--){
            Bullet b=bullets.get(i);
            if (b.updateAndCheck(WIDTH,HEIGHT)){
                removeBullet(i);
                continue;
            }
            if (!invulnerable){
                double cx=playerX+playerSize/2.0, cy=playerY+playerSize/2.0;
                double dx=b.x-cx, dy=b.y-cy, rsum=b.size/2.0+hitboxRadius;
                if (dx*dx+dy*dy<=rsum*rsum){
                    removeBullet(i);
                    lives--; invulnerable=true; lastDamageTime=elapsed;
                    System.out.printf("Hit by bullet at (%.1f,%.1f); lives=%d%n",b.x,b.y,lives);
                    if (lives<=0){ gameOver(); return; }
                }
            }
        }

        double cx=playerX+playerSize/2.0, cy=playerY+playerSize/2.0;
        for (SliderLaser sl: sliderLasers) {
            if (elapsed < sl.getFullOpacityTime()) continue;
            Path2D coll = sl.getCollisionPath(WIDTH,HEIGHT,elapsed);
            if (coll!=null && coll.intersects(cx-hitboxRadius,cy-hitboxRadius,hitboxRadius*2,hitboxRadius*2)){
                if (!invulnerable){
                    lives--; invulnerable=true; lastDamageTime=elapsed;
                    System.out.printf("Hit by slider at %d ms; lives=%d%n", elapsed, lives);
                    if (lives<=0){ gameOver(); return; }
                }
            }
        }

        int spd = slow? slowSpeed: playerSpeed;
        if (left)  playerX=Math.max(0,playerX-spd);
        if (right) playerX=Math.min(WIDTH-playerSize,playerX+spd);
        if (up)    playerY=Math.max(0,playerY-spd);
        if (down)  playerY=Math.min(HEIGHT-playerSize,playerY+spd);
    }

    private void renderFrame(BufferStrategy bs) {
        Graphics2D g = (Graphics2D) bs.getDrawGraphics();
        if (!aaDisabled){
            g.setRenderingHint(RenderingHints.KEY_ANTIALIASING,RenderingHints.VALUE_ANTIALIAS_OFF);
            g.setRenderingHint(RenderingHints.KEY_TEXT_ANTIALIASING,RenderingHints.VALUE_TEXT_ANTIALIAS_OFF);
            aaDisabled=true;
        }
        long elapsed = (musicClip!=null)
            ? musicClip.getMicrosecondPosition()/1000
            : System.currentTimeMillis()-startTime;

        g.setColor(Color.BLACK);
        g.fillRect(0,0,WIDTH,HEIGHT);

        g.setColor(Color.WHITE);
        g.setFont(hudFont);
        g.drawString(mapTitle,20,20);
        g.drawString("Lives: "+lives,WIDTH-100,20);

        boolean draw = true;
        if (invulnerable && elapsed-lastDamageTime<INV_DURATION){
            if (((elapsed-lastDamageTime)/BLINK_INTERVAL)%2==0) draw=false;
        }
        if (draw){
            if (playerTexture!=null) g.drawImage(playerTexture,playerX,playerY,playerSize,playerSize,null);
            else g.fillRect(playerX,playerY,playerSize,playerSize);
        }

        int cxI=playerX+playerSize/2, cyI=playerY+playerSize/2;
        g.setComposite(hitboxComposite);
        g.setStroke(hitboxStroke);
        g.drawOval(cxI-hitboxRadius,cyI-hitboxRadius,hitboxRadius*2,hitboxRadius*2);
        g.setComposite(defaultComposite);

        g.setColor(Color.RED);
        for (Bullet b: bullets){
            g.fillOval((int)(b.x-b.size/2),(int)(b.y-b.size/2),b.size,b.size);
        }

        for (SliderLaser sl: sliderLasers){
            sl.render(g,WIDTH,HEIGHT,elapsed);
        }

        if (paused){
            g.setColor(Color.YELLOW);
            g.setFont(new Font("Arial",Font.BOLD,48));
            g.drawString("PAUSED",WIDTH/2-100,HEIGHT/2);
        }

        g.dispose();
        bs.show();
    }

    private void spawnBullet(HitObject ho){
        Bullet b = bulletPool.pollFirst();
        if (b==null) b=new Bullet(bulletSize);
        b.init(ho,playerX+playerSize/2.0,playerY+playerSize/2.0,bulletSpeed,approachTime);
        bullets.add(b);
    }

    private void spawnSliderBullet(int sx,int sy){
        Bullet b = bulletPool.pollFirst();
        if (b==null) b=new Bullet(bulletSize);
        b.init(sx,sy,playerX+playerSize/2.0,playerY+playerSize/2.0,bulletSpeed,approachTime);
        bullets.add(b);
    }

    private void removeBullet(int idx){
        bulletPool.addLast(bullets.remove(idx));
    }

    private void gameOver(){
        running=false;
        SwingUtilities.invokeLater(() -> {
            int res = JOptionPane.showOptionDialog(
                this,"You lost!","Game Over",
                JOptionPane.YES_NO_OPTION,JOptionPane.INFORMATION_MESSAGE,
                null,new String[]{"Retry","Exit"},"Retry");
            if (res==JOptionPane.YES_OPTION){
                setMap(currentSetName,currentOsuFile);
            } else {
                Window w=SwingUtilities.getWindowAncestor(this);
                if (w!=null) w.dispose();
                System.exit(0);
            }
        });
    }

    @Override public void keyPressed(KeyEvent e){
        switch(e.getKeyCode()){
            case KeyEvent.VK_LEFT:   left=true; break;
            case KeyEvent.VK_RIGHT:  right=true;break;
            case KeyEvent.VK_UP:     up=true;   break;
            case KeyEvent.VK_DOWN:   down=true; break;
            case KeyEvent.VK_SHIFT:  slow=true; break;
            case KeyEvent.VK_P:
                if (musicClip!=null){
                    paused=!paused;
                    if (paused) musicClip.stop(); else musicClip.start();
                }
                break;
            case KeyEvent.VK_ESCAPE:
                Window w=SwingUtilities.getWindowAncestor(this);
                if (w!=null) w.dispose();
                System.exit(0);
        }
    }
    @Override public void keyReleased(KeyEvent e){
        switch(e.getKeyCode()){
            case KeyEvent.VK_LEFT:   left=false; break;
            case KeyEvent.VK_RIGHT:  right=false;break;
            case KeyEvent.VK_UP:     up=false;   break;
            case KeyEvent.VK_DOWN:   down=false; break;
            case KeyEvent.VK_SHIFT:  slow=false; break;
        }
    }
    @Override public void keyTyped(KeyEvent e){}

    private static class HitObject {
        final int x,y; final long time;
        HitObject(int x,int y,long t){this.x=x;this.y=y;this.time=t;}
    }

    private static class ScheduledSpawn {
        long offset; int x,y;
    }

    private static class Bullet {
        double x,y,dx,dy; final int size;
        Bullet(int size){this.size=size;}
        void init(HitObject ho,double px,double py,double speed,double approach){
            this.x=Math.random()*WIDTH;
            this.y=-this.size;
            this.dx=(px-x)/approach*speed;
            this.dy=(py-y)/approach*speed;
        }
        void init(int sx,int sy,double px,double py,double speed,double approach){
            this.x=sx; this.y=sy;
            this.dx=(px-x)/approach*speed;
            this.dy=(py-y)/approach*speed;
        }
        boolean updateAndCheck(int w,int h){
            x+=dx; y+=dy;
            return y>h+size||x<-size||x>w+size;
        }
    }
}
