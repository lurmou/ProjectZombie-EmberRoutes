package emberroutes.probe;

import java.util.Objects;
import java.util.function.Consumer;
import java.util.function.Supplier;

/** Single game-thread ownership; retain a failed cleanup for explicit retry. */
public final class ProbeSession<T> {
    private T body;
    public T get() { return body; }

    public T spawn(Supplier<T> factory) {
        if (body == null) body = Objects.requireNonNull(factory.get(), "factory returned null");
        return body;
    }

    public boolean remove(Consumer<T> cleanup) {
        if (body == null) return false;
        cleanup.accept(body);
        body = null;
        return true;
    }
}
