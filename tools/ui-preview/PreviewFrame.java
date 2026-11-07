package zombie.ui;

/** Tool-only package bridge for the same per-frame stencil reset as UIManager.render.
 * This class is on the preview classpath only; no game class/JAR is replaced. */
public final class PreviewFrame {
    private PreviewFrame() {}
    public static void resetStencilDepth() { UIElement.stencilLevel=0; }
    public static void flushPendingUI() {
        UIManager.getUI().removeAll(UIManager.toRemove);
        UIManager.toRemove.clear();
        UIManager.getUI().addAll(UIManager.toAdd);
        UIManager.toAdd.clear();
    }
}
