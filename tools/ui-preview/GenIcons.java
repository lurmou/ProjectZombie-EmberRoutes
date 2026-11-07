import java.awt.*;
import java.awt.geom.*;
import java.awt.image.BufferedImage;
import java.nio.file.*;
import java.util.ArrayList;
import java.util.List;
import javax.imageio.ImageIO;

/** Generates the 32x32 antialiased white UI icon set (transparent background).
 *  Design language follows CleanUI's icon set: heavy rounded strokes (~15-18%
 *  of canvas), full solid geometry, generous margins. Each icon is audited at
 *  generation time (ink coverage + antialias evidence) so a broken shape fails
 *  loudly instead of shipping.
 *  Consumed at 10-16px via drawTextureScaled (linear downsampling). */
final class GenIcons {
    static final int SIZE = 32;
    static Path outDir;
    static final List<String> AUDIT = new ArrayList<>();

    public static void main(String[] args) throws Exception {
        outDir = Paths.get(args[0]);
        Files.createDirectories(outDir);
        icon("check", GenIcons::check);
        icon("disc", (g, pen, brush) -> g.fill(ellipse(4, 4, 24, 24)));
        icon("ring", (g, pen, brush) -> { g.setStroke(pen(5)); g.draw(ellipse(6, 6, 20, 20)); });
        icon("pause", (g, pen, brush) -> { g.fill(round(7, 6, 7, 20, 3)); g.fill(round(18, 6, 7, 20, 3)); });
        icon("warn", GenIcons::warn);
        icon("square", (g, pen, brush) -> { g.setStroke(pen(5)); g.draw(round(6, 6, 20, 20, 4)); });
        icon("diamond", GenIcons::diamond);
        icon("transit", GenIcons::transit);
        icon("return", GenIcons::ret);
        icon("plus", GenIcons::plus);
        icon("minus", (g, pen, brush) -> g.fill(round(5, 13, 22, 6, 3)));
        icon("bullet", (g, pen, brush) -> g.fill(ellipse(9, 9, 14, 14)));
        icon("chevronUp", (g, pen, brush) -> { g.setStroke(pen(6)); g.draw(poly(new double[]{6,21, 16,10, 26,21}, false)); });
        icon("chevronDown", (g, pen, brush) -> { g.setStroke(pen(6)); g.draw(poly(new double[]{6,11, 16,22, 26,11}, false)); });
        icon("box", GenIcons::box);
        icon("hammer", GenIcons::hammer);
        icon("arrowDown", GenIcons::arrowDown);
        icon("arrowRight", GenIcons::arrowRight);
        icon("moon", GenIcons::moon);
        System.out.println("icons generated: " + Files.list(outDir).count());
        System.out.println("audit: all " + AUDIT.size() + " icons passed ink/antialias checks");
    }

    interface Painter { void paint(Graphics2D g, BasicStroke pen, Color white); }

    static void icon(String name, Painter painter) throws Exception {
        BufferedImage img = new BufferedImage(SIZE, SIZE, BufferedImage.TYPE_INT_ARGB);
        Graphics2D g = img.createGraphics();
        g.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
        g.setRenderingHint(RenderingHints.KEY_STROKE_CONTROL, RenderingHints.VALUE_STROKE_PURE);
        g.setColor(Color.WHITE);
        painter.paint(g, pen(5), Color.WHITE);
        g.dispose();
        audit(name, img);
        ImageIO.write(img, "png", outDir.resolve(name + ".png").toFile());
    }

    /** Fails the build when an icon is empty, smeared solid, or hard-edged. */
    static void audit(String name, BufferedImage img) {
        int ink = 0, soft = 0;
        for (int y = 0; y < SIZE; y++) for (int x = 0; x < SIZE; x++) {
            int a = (img.getRGB(x, y) >>> 24);
            if (a > 200) ink++;
            else if (a > 40) soft++;
        }
        double pct = ink / (double) (SIZE * SIZE);
        if (pct < 0.05 || pct > 0.72) throw new IllegalStateException(name + " ink " + pct);
        if (soft < 4) throw new IllegalStateException(name + " no antialias evidence (" + soft + ")");
        AUDIT.add(name);
        System.out.printf("  %-11s ink=%4.1f%% soft=%d%n", name, pct * 100, soft);
    }

    static BasicStroke pen(float w) { return new BasicStroke(w, BasicStroke.CAP_ROUND, BasicStroke.JOIN_ROUND); }

    static Ellipse2D ellipse(double x, double y, double w, double h) { return new Ellipse2D.Double(x, y, w, h); }
    static Rectangle2D rect(double x, double y, double w, double h) { return new Rectangle2D.Double(x, y, w, h); }
    static RoundRectangle2D round(double x, double y, double w, double h, double r) { return new RoundRectangle2D.Double(x, y, w, h, r, r); }

    static Path2D poly(double[] pts, boolean close) {
        Path2D p = new Path2D.Double();
        p.moveTo(pts[0], pts[1]);
        for (int i = 2; i < pts.length; i += 2) p.lineTo(pts[i], pts[i + 1]);
        if (close) p.closePath();
        return p;
    }

    static void check(Graphics2D g, BasicStroke pen, Color w) {
        g.setStroke(pen(6));
        g.draw(poly(new double[]{6,17, 13,24, 26,8}, false));
    }

    static void warn(Graphics2D g, BasicStroke pen, Color w) {
        // Solid triangle with an exclamation mark punched out (EvenOdd): at
        // 12px the tinted silhouette stays readable, holes never smear.
        Path2D p = new Path2D.Double(Path2D.WIND_EVEN_ODD);
        p.append(poly(new double[]{16,2, 30.5,28.5, 1.5,28.5, 16,2}, true), false);
        p.append(round(13.8, 10, 4.4, 10, 2), false);
        p.append(ellipse(13.6, 22.2, 4.8, 4.8), false);
        g.fill(p);
    }

    static void diamond(Graphics2D g, BasicStroke pen, Color w) {
        g.fill(poly(new double[]{16,3, 28,16, 16,29, 4,16}, true));
    }

    static void transit(Graphics2D g, BasicStroke pen, Color w) {
        g.setStroke(pen(5));
        g.draw(poly(new double[]{3,16, 16,16}, false));
        g.fill(poly(new double[]{15,6.5, 28.5,16, 15,25.5}, true));
    }

    static void ret(Graphics2D g, BasicStroke pen, Color w) {
        g.setStroke(pen(5));
        g.draw(poly(new double[]{27,13, 12,13, 12,27}, false));
        g.fill(poly(new double[]{13,4, 2.5,13, 13,22}, true));
    }

    static void plus(Graphics2D g, BasicStroke pen, Color w) {
        g.fill(round(13.5, 5, 6, 22, 3));
        g.fill(round(5, 13.5, 22, 6, 3));
    }

    static void box(Graphics2D g, BasicStroke pen, Color w) {
        g.setStroke(pen(4));
        g.draw(round(5, 7, 22, 20, 3));
        g.setStroke(pen(4));
        g.draw(poly(new double[]{5,14, 27,14}, false));
        g.fill(round(14, 11.5, 4, 5.5, 2));
    }

    static void hammer(Graphics2D g, BasicStroke pen, Color w) {
        Shape head = round(6, 4, 20, 9, 3);
        Shape handle = round(13.5, 12, 5, 16, 2);
        AffineTransform at = AffineTransform.getRotateInstance(Math.toRadians(-40), 16, 16);
        g.fill(at.createTransformedShape(head));
        g.fill(at.createTransformedShape(handle));
    }

    static void arrowDown(Graphics2D g, BasicStroke pen, Color w) {
        g.fill(round(13.5, 3, 5, 13, 2.5));
        g.fill(poly(new double[]{4,14, 28,14, 16,28.5}, true));
    }

    static void arrowRight(Graphics2D g, BasicStroke pen, Color w) {
        g.fill(round(3, 13.5, 13, 5, 2.5));
        g.fill(poly(new double[]{14,4, 28.5,16, 14,28}, true));
    }

    static void moon(Graphics2D g, BasicStroke pen, Color w) {
        g.setStroke(pen(5));
        g.draw(poly(new double[]{7,7.5, 25,7.5, 7,24.5, 25,24.5}, false));
    }
}
