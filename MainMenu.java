import javax.swing.*;
import javax.swing.filechooser.FileNameExtensionFilter;
import java.io.*;
import java.util.Properties;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;

public class MainMenu {

    public static JMenuBar createMenu(JFrame parent, Game game) {
        JMenuBar menuBar = new JMenuBar();

        // --- Maps menu ---
        JMenu mapMenu = new JMenu("Maps");
        JMenuItem load = new JMenuItem("Load Map...");
        load.addActionListener(e -> loadMap(parent));
        mapMenu.add(load);

        JMenuItem select = new JMenuItem("Select Map & Mode");
        select.addActionListener(e -> selectMap(parent, game));
        mapMenu.add(select);

        menuBar.add(mapMenu);

        // --- Settings menu ---
        JMenu settings = new JMenu("Settings");

        JMenuItem resItem = new JMenuItem("Screen Resolution");
        resItem.addActionListener(e -> changeResolution(parent));
        settings.add(resItem);

        JMenuItem bulletItem = new JMenuItem("Bullet Speed");
        bulletItem.addActionListener(e -> changeBulletSpeed(parent));
        settings.add(bulletItem);

        JMenuItem playerItem = new JMenuItem("Player Speed");
        playerItem.addActionListener(e -> changePlayerSpeed(parent));
        settings.add(playerItem);

        JMenuItem fpsItem = new JMenuItem("FPS Limit");
        fpsItem.addActionListener(e -> changeFPS(parent));
        settings.add(fpsItem);

        JMenuItem vsyncItem = new JMenuItem("VSync (on/off)");
        vsyncItem.addActionListener(e -> changeVSync(parent));
        settings.add(vsyncItem);

        menuBar.add(settings);
        return menuBar;
    }

    private static void loadMap(JFrame parent) {
        JFileChooser chooser = new JFileChooser();
        chooser.setFileFilter(new FileNameExtensionFilter("Osu archives (.osz, .zip)", "osz", "zip"));
        if (chooser.showOpenDialog(parent) != JFileChooser.APPROVE_OPTION) return;

        File archive = chooser.getSelectedFile();
        try {
            if (!Main.BEATMAPS_DIR.exists()) Main.BEATMAPS_DIR.mkdir();
            String base = archive.getName().replaceFirst("\\.(osz|zip)$", "");
            File dest = new File(Main.BEATMAPS_DIR, base);
            if (!dest.exists()) unzipArchive(archive, dest);
            JOptionPane.showMessageDialog(parent,
                "Карта распакована в: " + dest.getPath(),
                "Успешно", JOptionPane.INFORMATION_MESSAGE);
        } catch (IOException ex) {
            ex.printStackTrace();
            JOptionPane.showMessageDialog(parent,
                "Ошибка распаковки:\n" + ex.getMessage(),
                "Ошибка", JOptionPane.ERROR_MESSAGE);
        }
    }

    private static void selectMap(JFrame parent, Game game) {
        if (!Main.BEATMAPS_DIR.exists() || Main.BEATMAPS_DIR.listFiles() == null) {
            JOptionPane.showMessageDialog(parent,
                "Папка beatmaps пуста. Сначала загрузите карту.",
                "Нет карт", JOptionPane.WARNING_MESSAGE);
            return;
        }

        String[] sets = Main.BEATMAPS_DIR.list((d, name) -> new File(d, name).isDirectory());
        if (sets == null || sets.length == 0) {
            JOptionPane.showMessageDialog(parent,
                "Нет распакованных наборов карт.",
                "Нет карт", JOptionPane.WARNING_MESSAGE);
            return;
        }
        String setChoice = (String) JOptionPane.showInputDialog(
            parent, "Выберите набор карт:", "Select Map Set",
            JOptionPane.PLAIN_MESSAGE, null, sets, sets[0]
        );
        if (setChoice == null) return;

        File setDir = new File(Main.BEATMAPS_DIR, setChoice);
        String[] osuFiles = setDir.list((d, name) -> name.toLowerCase().endsWith(".osu"));
        if (osuFiles == null || osuFiles.length == 0) {
            JOptionPane.showMessageDialog(parent,
                "В выбранном наборе нет .osu-файлов.",
                "Нет режимов", JOptionPane.WARNING_MESSAGE);
            return;
        }
        String fileChoice = (String) JOptionPane.showInputDialog(
            parent, "Выберите режим (файл .osu):", "Select Mode",
            JOptionPane.PLAIN_MESSAGE, null, osuFiles, osuFiles[0]
        );
        if (fileChoice == null) return;

        game.setMap(setChoice, fileChoice);
    }

    private static void changeResolution(JFrame parent) {
        File cfg = new File("config.properties");
        Properties p = new Properties();
        if (cfg.exists()) {
            try (FileInputStream in = new FileInputStream(cfg)) {
                p.load(in);
            } catch (IOException ignored) {}
        }
        String sw = JOptionPane.showInputDialog(parent,
            "Screen width:", p.getProperty("screenWidth", "800"));
        if (sw == null) return;
        String sh = JOptionPane.showInputDialog(parent,
            "Screen height:", p.getProperty("screenHeight", "600"));
        if (sh == null) return;
        try {
            Integer.parseInt(sw);
            Integer.parseInt(sh);
            p.setProperty("screenWidth", sw);
            p.setProperty("screenHeight", sh);
            try (FileOutputStream out = new FileOutputStream(cfg)) {
                p.store(out, null);
            }
            JOptionPane.showMessageDialog(parent,
                "Разрешение сохранено. Перезапустите игру для применения.",
                "Settings", JOptionPane.INFORMATION_MESSAGE);
        } catch (NumberFormatException | IOException ex) {
            JOptionPane.showMessageDialog(parent,
                "Ошибка: " + ex.getMessage(),
                "Error", JOptionPane.ERROR_MESSAGE);
        }
    }

    private static void changeBulletSpeed(JFrame parent) {
        File cfg = new File("config.properties");
        Properties p = new Properties();
        if (cfg.exists()) {
            try (FileInputStream in = new FileInputStream(cfg)) {
                p.load(in);
            } catch (IOException ignored) {}
        }
        String bs = JOptionPane.showInputDialog(parent,
            "Bullet Speed:", p.getProperty("bulletSpeed", "4"));
        if (bs == null) return;
        try {
            Double.parseDouble(bs);
            p.setProperty("bulletSpeed", bs);
            try (FileOutputStream out = new FileOutputStream(cfg)) {
                p.store(out, null);
            }
            JOptionPane.showMessageDialog(parent,
                "Скорость пуль сохранена. Перезапустите игру для применения.",
                "Settings", JOptionPane.INFORMATION_MESSAGE);
        } catch (NumberFormatException | IOException ex) {
            JOptionPane.showMessageDialog(parent,
                "Ошибка: " + ex.getMessage(),
                "Error", JOptionPane.ERROR_MESSAGE);
        }
    }

    private static void changePlayerSpeed(JFrame parent) {
        File cfg = new File("config.properties");
        Properties p = new Properties();
        if (cfg.exists()) {
            try (FileInputStream in = new FileInputStream(cfg)) {
                p.load(in);
            } catch (IOException ignored) {}
        }
        String ps = JOptionPane.showInputDialog(parent,
            "Player Speed:", p.getProperty("playerSpeed", "5"));
        if (ps == null) return;
        try {
            Integer.parseInt(ps);
            p.setProperty("playerSpeed", ps);
            try (FileOutputStream out = new FileOutputStream(cfg)) {
                p.store(out, null);
            }
            JOptionPane.showMessageDialog(parent,
                "Скорость игрока сохранена. Перезапустите игру для применения.",
                "Settings", JOptionPane.INFORMATION_MESSAGE);
        } catch (NumberFormatException | IOException ex) {
            JOptionPane.showMessageDialog(parent,
                "Ошибка: " + ex.getMessage(),
                "Error", JOptionPane.ERROR_MESSAGE);
        }
    }

    private static void changeFPS(JFrame parent) {
        File cfg = new File("config.properties");
        Properties p = new Properties();
        if (cfg.exists()) {
            try (FileInputStream in = new FileInputStream(cfg)) {
                p.load(in);
            } catch (IOException ignored) {}
        }
        String cur = p.getProperty("maxFPS", "60");
        String s = JOptionPane.showInputDialog(parent,
            "Max FPS (0 = unlimited):", cur);
        if (s == null) return;
        try {
            int value = Integer.parseInt(s);
            p.setProperty("maxFPS", Integer.toString(value));
            try (FileOutputStream out = new FileOutputStream(cfg)) {
                p.store(out, null);
            }
        } catch (NumberFormatException | IOException ex) {
            JOptionPane.showMessageDialog(parent,
                "Ошибка: " + ex.getMessage(),
                "Error", JOptionPane.ERROR_MESSAGE);
        }
    }

    private static void changeVSync(JFrame parent) {
        File cfg = new File("config.properties");
        Properties p = new Properties();
        if (cfg.exists()) {
            try (FileInputStream in = new FileInputStream(cfg)) {
                p.load(in);
            } catch (IOException ignored) {}
        }
        String cur = p.getProperty("vsync", "true");
        String s = JOptionPane.showInputDialog(parent,
            "Enable VSync? (true/false):", cur);
        if (s == null) return;
        try {
            boolean value = Boolean.parseBoolean(s);
            p.setProperty("vsync", Boolean.toString(value));
            try (FileOutputStream out = new FileOutputStream(cfg)) {
                p.store(out, null);
            }
        } catch (IOException ex) {
            JOptionPane.showMessageDialog(parent,
                "Ошибка: " + ex.getMessage(),
                "Error", JOptionPane.ERROR_MESSAGE);
        }
    }

    private static void unzipArchive(File src, File dest) throws IOException {
        if (!dest.exists()) dest.mkdirs();
        try (ZipInputStream zis = new ZipInputStream(new FileInputStream(src))) {
            ZipEntry entry;
            while ((entry = zis.getNextEntry()) != null) {
                File out = new File(dest, entry.getName());
                if (entry.isDirectory()) {
                    out.mkdirs();
                } else {
                    out.getParentFile().mkdirs();
                    try (BufferedOutputStream bos = new BufferedOutputStream(new FileOutputStream(out))) {
                        byte[] buf = new byte[4096];
                        int len;
                        while ((len = zis.read(buf)) > 0) {
                            bos.write(buf, 0, len);
                        }
                    }
                }
                zis.closeEntry();
            }
        }
    }
}
