// Main.java
import javax.swing.*;
import java.awt.BorderLayout;
import java.io.File;

public class Main {
    public static final File BEATMAPS_DIR = new File("beatmaps");

    public static void main(String[] args) {
        SwingUtilities.invokeLater(() -> {
            // Генерируем недостающие режимы
            Converter.convertAll();

            // Создаём окно и канву
            JFrame frame = new JFrame("Beatmap Game Multi");
            frame.setDefaultCloseOperation(JFrame.EXIT_ON_CLOSE);
            frame.setLayout(new BorderLayout());

            Game canvas = new Game();
            frame.add(canvas, BorderLayout.CENTER);

            // Меню
            frame.setJMenuBar(MainMenu.createMenu(frame, canvas));

            frame.pack();
            frame.setLocationRelativeTo(null);
            frame.setVisible(true);
        });
    }
}
