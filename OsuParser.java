import java.io.*;
import java.util.*;
import java.awt.Point;
import javax.sound.sampled.*;

/**
 * Парсер .osu-файлов с поддержкой загрузки аудио.
 */
public class OsuParser {

    /**
     * DTO-класс для результатов парсинга:
     * хит-объекты, слайдеры, тайминги и аудио.
     */
    public static class OsuMapData {
        public final List<HitObject> hitObjects;
        public final List<TempSlider> tempSliders;
        public final double approachTime;
        public final double sliderMultiplier;
        public final double beatLength;
        public final Clip   musicClip;

        public OsuMapData(List<HitObject> hitObjects,
                          List<TempSlider> tempSliders,
                          double approachTime,
                          double sliderMultiplier,
                          double beatLength,
                          Clip musicClip) {
            this.hitObjects      = hitObjects;
            this.tempSliders     = tempSliders;
            this.approachTime    = approachTime;
            this.sliderMultiplier= sliderMultiplier;
            this.beatLength      = beatLength;
            this.musicClip       = musicClip;
        }
    }

    /**
     * Логика парсинга .osu-файла и загрузки аудио.
     * @param dir директория с картой
     * @param osuFile имя .osu-файла
     * @return собранные данные по карте
     */
    public OsuMapData parse(File dir, String osuFile) {
        double approachTime     = 1500;
        double sliderMultiplier = 1.4;
        double beatLength       = 500;

        List<HitObject> hitObjects   = new ArrayList<>();
        List<TempSlider> tempSliders = new ArrayList<>();

        boolean inDiff = false, inTiming = false, inHits = false;
        File osu = new File(dir, osuFile);
        try (BufferedReader r = new BufferedReader(new InputStreamReader(new FileInputStream(osu), "UTF-8"))) {
            String line;
            while ((line = r.readLine()) != null) {
                if (!inHits && !inTiming) {
                    if (line.equals("[Difficulty]"))   { inDiff=true;    continue; }
                    if (line.equals("[TimingPoints]")) { inTiming=true; inDiff=false; continue; }
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

        // Загрузка аудио с fallback через ffmpeg
        Clip musicClip = null;
        try {
            String audioName = getAudioFilename(osu);
            if (audioName != null) {
                File audioFile = new File(dir, audioName);
                AudioInputStream ais;
                try {
                    ais = AudioSystem.getAudioInputStream(audioFile);
                } catch (UnsupportedAudioFileException|IOException e1) {
                    File wav = new File(dir, "__temp.wav");
                    new ProcessBuilder("ffmpeg","-y",
                        "-i", audioFile.getAbsolutePath(),
                        wav.getAbsolutePath()
                    ).inheritIO().start().waitFor();
                    ais = AudioSystem.getAudioInputStream(wav);
                    wav.deleteOnExit();
                }
                musicClip = AudioSystem.getClip();
                musicClip.open(ais);
                if (musicClip.isControlSupported(FloatControl.Type.MASTER_GAIN)) {
                    FloatControl gain = (FloatControl) musicClip.getControl(FloatControl.Type.MASTER_GAIN);
                    float vol = Config.getMusicVolume();
                    float dB  = 20f * (float)Math.log10(Math.max(vol, 0.0001f));
                    gain.setValue(dB);
                }
            }
        } catch (Exception e) {
            e.printStackTrace();
        }

        return new OsuMapData(hitObjects, tempSliders, approachTime, sliderMultiplier, beatLength, musicClip);
    }

    private String getAudioFilename(File osu) throws IOException {
        try (BufferedReader r = new BufferedReader(new InputStreamReader(new FileInputStream(osu), "UTF-8"))) {
            String line;
            while ((line = r.readLine()) != null) {
                if (line.startsWith("AudioFilename:"))
                    return line.split(":",2)[1].trim();
            }
        }
        return null;
    }

    /** Вспомогательный класс для хит-объектов */
    public static class HitObject {
        public final int x, y;
        public final long time;
        public HitObject(int x, int y, long time) {
            this.x = x; this.y = y; this.time = time;
        }
    }

    /** Вспомогательный класс для временных слайдеров */
    public static class TempSlider {
        public long time;
        public int    repeats;
        public double pixelLen;
        public List<Point> ctrlPts;
    }
}
