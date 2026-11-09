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

        // Core UI Status & Navigation Glyphs
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
        icon("arrowDown", GenIcons::arrowDown);
        icon("arrowRight", GenIcons::arrowRight);
        icon("moon", GenIcons::moon);

        // Industrial & Domain Entities
        icon("box", GenIcons::box);
        icon("hammer", GenIcons::hammer);
        icon("gear", GenIcons::gear);
        icon("shield", GenIcons::shield);
        icon("heart", GenIcons::heart);
        icon("person", GenIcons::person);
        icon("cart", GenIcons::cart);
        icon("wrench", GenIcons::wrench);
        icon("book", GenIcons::book);

        // Settlement Resources & Semantics (Flat 2.0 Vector Parity)
        icon("droplet", GenIcons::droplet);
        icon("apple", GenIcons::apple);
        icon("cross", GenIcons::cross);
        icon("tree", GenIcons::tree);

        // Controls, Utilities & Actions
        icon("search", GenIcons::search);
        icon("eye", GenIcons::eye);
        icon("filter", GenIcons::filter);
        icon("clock", GenIcons::clock);
        icon("lock", GenIcons::lock);
        icon("trash", GenIcons::trash);
        icon("bell", GenIcons::bell);
        icon("star", GenIcons::star);
        icon("info", GenIcons::info);

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

    static void gear(Graphics2D g, BasicStroke pen, Color w) {
        Path2D p = new Path2D.Double(Path2D.WIND_EVEN_ODD);
        p.append(ellipse(5, 5, 22, 22), false);
        p.append(ellipse(13, 13, 6, 6), false);
        g.fill(p);
        for (int i = 0; i < 8; i++) {
            AffineTransform at = AffineTransform.getRotateInstance(Math.toRadians(i * 45), 16, 16);
            g.fill(at.createTransformedShape(round(13.5, 1.5, 5, 6, 1.5)));
        }
    }

    static void shield(Graphics2D g, BasicStroke pen, Color w) {
        Path2D p = new Path2D.Double();
        p.moveTo(16, 3);
        p.lineTo(27, 7);
        p.curveTo(27, 18, 21, 25, 16, 29);
        p.curveTo(11, 25, 5, 18, 5, 7);
        p.closePath();
        g.fill(p);
    }

    static void heart(Graphics2D g, BasicStroke pen, Color w) {
        Path2D p = new Path2D.Double();
        p.moveTo(16, 8);
        p.curveTo(16, 3, 5, 3, 5, 12);
        p.curveTo(5, 19, 13, 25, 16, 28.5);
        p.curveTo(19, 25, 27, 19, 27, 12);
        p.curveTo(27, 3, 16, 3, 16, 8);
        p.closePath();
        g.fill(p);
    }

    static void person(Graphics2D g, BasicStroke pen, Color w) {
        g.fill(ellipse(10.5, 3.5, 11, 11));
        Path2D p = new Path2D.Double();
        p.moveTo(5, 28);
        p.curveTo(5, 19, 10, 16.5, 16, 16.5);
        p.curveTo(22, 16.5, 27, 19, 27, 28);
        p.closePath();
        g.fill(p);
    }

    static void cart(Graphics2D g, BasicStroke pen, Color w) {
        g.setStroke(pen(3.5f));
        g.draw(poly(new double[]{4,7, 9,7, 13,19, 25,19, 27,10, 10,10}, false));
        g.fill(ellipse(12, 22.5, 5, 5));
        g.fill(ellipse(22, 22.5, 5, 5));
    }

    static void wrench(Graphics2D g, BasicStroke pen, Color w) {
        Shape handle = round(13.5, 11, 5, 16, 2);
        Shape jaw = round(9.5, 3.5, 13, 10, 2.5);
        AffineTransform at = AffineTransform.getRotateInstance(Math.toRadians(-45), 16, 16);
        Path2D p = new Path2D.Double();
        p.append(at.createTransformedShape(handle), false);
        p.append(at.createTransformedShape(jaw), false);
        g.fill(p);
    }

    static void book(Graphics2D g, BasicStroke pen, Color w) {
        g.setStroke(pen(3.5f));
        g.draw(round(6, 4, 20, 24, 3));
        g.setStroke(pen(3f));
        g.draw(poly(new double[]{11,10, 21,10}, false));
        g.draw(poly(new double[]{11,16, 21,16}, false));
        g.draw(poly(new double[]{11,22, 18,22}, false));
    }

    static void droplet(Graphics2D g, BasicStroke pen, Color w) {
        Path2D p = new Path2D.Double();
        p.moveTo(16, 3);
        p.curveTo(16, 3, 6.5, 14, 6.5, 20.5);
        p.curveTo(6.5, 25.8, 10.8, 29, 16, 29);
        p.curveTo(21.2, 29, 25.5, 25.8, 25.5, 20.5);
        p.curveTo(25.5, 14, 16, 3, 16, 3);
        p.closePath();
        g.fill(p);
    }

    static void apple(Graphics2D g, BasicStroke pen, Color w) {
        Path2D p = new Path2D.Double();
        p.moveTo(16, 9);
        p.curveTo(12, 5.5, 5, 7.5, 5, 16.5);
        p.curveTo(5, 24, 10, 28.5, 16, 27.5);
        p.curveTo(22, 28.5, 27, 24, 27, 16.5);
        p.curveTo(27, 7.5, 20, 5.5, 16, 9);
        p.closePath();
        g.fill(p);
        g.setStroke(pen(3f));
        g.draw(poly(new double[]{16,9, 19,3.5}, false));
    }

    static void cross(Graphics2D g, BasicStroke pen, Color w) {
        g.fill(round(12, 4, 8, 24, 3));
        g.fill(round(4, 12, 24, 8, 3));
    }

    static void tree(Graphics2D g, BasicStroke pen, Color w) {
        Path2D p = new Path2D.Double();
        p.moveTo(16, 3);
        p.lineTo(25, 12); p.lineTo(21, 12);
        p.lineTo(26, 19); p.lineTo(21, 19);
        p.lineTo(27, 25); p.lineTo(5, 25);
        p.lineTo(11, 19); p.lineTo(6, 19);
        p.lineTo(11, 12); p.lineTo(7, 12);
        p.closePath();
        g.fill(p);
        g.fill(round(13.5, 25, 5, 4.5, 1));
    }

    static void search(Graphics2D g, BasicStroke pen, Color w) {
        g.setStroke(pen(4));
        g.draw(ellipse(5, 5, 15, 15));
        g.fill(poly(new double[]{16.5,16.5, 26,26, 23.5,28.5, 14,19}, true));
    }

    static void eye(Graphics2D g, BasicStroke pen, Color w) {
        Path2D p = new Path2D.Double();
        p.moveTo(3, 16);
        p.curveTo(8, 7, 24, 7, 29, 16);
        p.curveTo(24, 25, 8, 25, 3, 16);
        p.closePath();
        g.setStroke(pen(3.5f));
        g.draw(p);
        g.fill(ellipse(12, 12, 8, 8));
    }

    static void filter(Graphics2D g, BasicStroke pen, Color w) {
        Path2D p = new Path2D.Double();
        p.moveTo(4, 5);
        p.lineTo(28, 5);
        p.lineTo(18.5, 16);
        p.lineTo(18.5, 25);
        p.lineTo(13.5, 27.5);
        p.lineTo(13.5, 16);
        p.closePath();
        g.fill(p);
    }

    static void clock(Graphics2D g, BasicStroke pen, Color w) {
        Path2D p = new Path2D.Double(Path2D.WIND_EVEN_ODD);
        p.append(ellipse(4, 4, 24, 24), false);
        p.append(ellipse(7.5, 7.5, 17, 17), false);
        g.fill(p);
        g.fill(round(14, 8, 4, 9, 2));
        g.fill(round(14, 14, 8, 4, 2));
    }

    static void lock(Graphics2D g, BasicStroke pen, Color w) {
        g.setStroke(pen(4));
        g.draw(poly(new double[]{9,15, 9,9, 23,9, 23,15}, false));
        Path2D p = new Path2D.Double(Path2D.WIND_EVEN_ODD);
        p.append(round(6, 13, 20, 15, 3), false);
        p.append(ellipse(14, 18, 4, 4), false);
        p.append(round(14.5, 20, 3, 5, 1), false);
        g.fill(p);
    }

    static void trash(Graphics2D g, BasicStroke pen, Color w) {
        g.fill(round(5, 6, 22, 4, 2));
        g.fill(round(11, 2.5, 10, 3.5, 1.5));
        g.setStroke(pen(3f));
        g.draw(poly(new double[]{8,10, 9.5,27.5, 22.5,27.5, 24,10}, false));
        g.draw(poly(new double[]{13,13, 13.5,24}, false));
        g.draw(poly(new double[]{19,13, 18.5,24}, false));
    }

    static void bell(Graphics2D g, BasicStroke pen, Color w) {
        Path2D p = new Path2D.Double();
        p.moveTo(16, 4);
        p.curveTo(11, 4, 8, 12, 8, 20);
        p.lineTo(4.5, 23.5);
        p.lineTo(27.5, 23.5);
        p.lineTo(24, 20);
        p.curveTo(24, 12, 21, 4, 16, 4);
        p.closePath();
        g.fill(p);
        g.fill(ellipse(13, 24.5, 6, 4.5));
    }

    static void star(Graphics2D g, BasicStroke pen, Color w) {
        Path2D p = new Path2D.Double();
        double rOuter = 13.5, rInner = 6.0;
        double cx = 16, cy = 16.5;
        for (int i = 0; i < 10; i++) {
            double angle = -Math.PI / 2 + i * Math.PI / 5;
            double r = (i % 2 == 0) ? rOuter : rInner;
            double x = cx + r * Math.cos(angle);
            double y = cy + r * Math.sin(angle);
            if (i == 0) p.moveTo(x, y); else p.lineTo(x, y);
        }
        p.closePath();
        g.fill(p);
    }

    static void info(Graphics2D g, BasicStroke pen, Color w) {
        Path2D p = new Path2D.Double(Path2D.WIND_EVEN_ODD);
        p.append(ellipse(4, 4, 24, 24), false);
        p.append(ellipse(7.5, 7.5, 17, 17), false);
        g.fill(p);
        g.fill(ellipse(13.8, 8.5, 4.4, 4.4));
        g.fill(round(13.8, 14.5, 4.4, 9, 2));
    }
}
