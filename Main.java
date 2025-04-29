import javax.swing.*;
import java.awt.BorderLayout;
import java.io.File;

public class Main {
    public static final File BEATMAPS_DIR = new File("beatmaps");

    public static void main(String[] args) {
        // Включаем аппаратное ускорение Java2D (OpenGL/D3D) до инициализации Swing
        System.setProperty("sun.java2d.opengl", "true");
        System.setProperty("sun.java2d.d3d",    "true");

        SwingUtilities.invokeLater(() -> {
            JFrame frame = new JFrame("Beatmap Game Multi");
            frame.setDefaultCloseOperation(JFrame.EXIT_ON_CLOSE);
            frame.setLayout(new BorderLayout());

            Game canvas = new Game();
            frame.add(canvas, BorderLayout.CENTER);

            frame.setJMenuBar(MainMenu.createMenu(frame, canvas));

            frame.pack();
            frame.setLocationRelativeTo(null);
            frame.setVisible(true);
        });
    }
}
