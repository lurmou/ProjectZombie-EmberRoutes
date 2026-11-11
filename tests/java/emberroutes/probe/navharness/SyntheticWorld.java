package emberroutes.probe.navharness;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

import zombie.iso.IsoCell;
import zombie.iso.IsoChunk;
import zombie.iso.IsoChunkMap;
import zombie.iso.IsoGridSquare;
import zombie.iso.IsoWorld;
import zombie.iso.SliceY;
import zombie.iso.SpriteDetails.IsoFlagType;

import emberroutes.probe.nav.EmberNavGrid;

/**
 * Headless synthetic world builder for the nav harness (mini-Zomboid test rig).
 *
 * <p>Builds a real {@link IsoWorld} / {@link IsoCell} / {@link IsoChunk} in-memory,
 * with no game client, no map files and no sprite loading, so the Ember
 * pathfinder and movement code can be exercised against vanilla geometry
 * (rooms, walls, doors, windows, fences, stairs, broken glass).
 *
 * <p>Verified facts this builder is built on (see /tmp/nav-spike/Spike1c,
 * Spike2, Spike2b, SpikeFloor, SpikeBounds2 — all run headless on JDK 25
 * against projectzomboid.jar):
 * <ul>
 *   <li>{@code IsoWorld.instance} must be set and {@code world.currentCell}
 *       must point at a new {@code IsoCell(30, 30)}.</li>
 *   <li>The chunk map needs {@code setInitialPos(0, 0)}; the {@link IsoChunk}
 *       needs {@code wx = wy = 0} and {@code chunk.refs} MUST contain the
 *       chunk map, otherwise {@code setChunkDirect} does not register it.</li>
 *   <li>Squares are placed with {@code IsoChunkMap.setGridSquare} using world
 *       coordinates and read back with {@code IsoCell.getGridSquare} — the
 *       lookup subtracts the world's min-tile offset (worldXMinTiles = -48),
 *       so only coordinates inside the registered chunk round-trip.</li>
 *   <li>A single registered chunk covers exactly {@value #CHUNK_TILES} x
 *       {@value #CHUNK_TILES} tiles: world {@code 0..7} in x and y. Coordinate
 *       8+ does NOT round-trip. Registering neighbour chunks is a future
 *       extension, not done here.</li>
 *   <li>Multi-floor placement works: a square placed at {@code z = 1}
 *       round-trips through {@code getGridSquare}, even though the chunk
 *       reports a single level ({@code minLevel = maxLevel = 0}). Only
 *       {@code z = 1} was verified; higher z is untested.</li>
 *   <li>Flag-only geometry is enough for the grid queries: a {@code solid}
 *       square is not walkable, a {@code WallN}/{@code WallW} flag blocks
 *       {@code isWallTo} from that side (Spike2b), {@code HoppableN} /
 *       {@code HoppableW} read as a LOW fence via
 *       {@link EmberNavGrid#fenceEdgeKind}, and a {@code WallN}/{@code WallW}
 *       flag on a walkable floor square reads as a TALL fence (the
 *       TallHoppable flags alone are NOT read by {@code fenceEdgeKind}).</li>
 * </ul>
 *
 * <p>Known limits (TODO, not silently worked around):
 * <ul>
 *   <li>Real {@code IsoDoor} / {@code IsoWindow} objects cannot be built
 *       headless: sprite lookup returns null (no tilesets loaded) and the
 *       constructors throw {@code NullPointerException} /
 *       {@code ExceptionInInitializerError} ({@code SandboxOptions} needs
 *       game init). Doors and windows here are flag-level: a closed door is
 *       a {@code solid} square with a {@code DoorWallN}/{@code DoorWallW}
 *       flag (verified to block {@code canStep}); an open door is a plain
 *       walkable floor square recorded in {@link #doors()}. A window is a
 *       floor square with a {@code WindowN}/{@code WindowW} flag recorded in
 *       {@link #windows()}. {@code NavCost.doorEdgeCost} /
 *       {@code windowEdgeCost} return {@code CLEAR} for these, because they
 *       read real objects via {@code getDoorTo}/{@code getWindowTo}.</li>
 *   <li>Real broken glass ({@code IsoGridSquare.addBrokenGlass()}) cannot be
 *       built headless either: {@code IsoBrokenGlass}'s constructor calls
 *       {@code Rand.Next} and the game randomizer is null without game init.
 *       {@link #brokenGlass} therefore records the hazard in this world's
 *       own registry (and still attempts the real call, so a fuller harness
 *       that initialises {@code Rand} gets the real object for free).
 *       {@link #hasBrokenGlass} consults both the registry and the square.</li>
 *   <li>Real stairs ({@code IsoGridSquare.AddStairs}) also fail headless
 *       ({@code SandboxOptions} init). {@link #staircase} places the
 *       two floors and records the link; {@code EmberNavGrid} stair linkage
 *       reads real stair objects, so it returns null for these until real
 *       stair objects can be built.</li>
 * </ul>
 */
public final class SyntheticWorld {

    /** Tiles per side covered by the single registered chunk (world 0..7). */
    public static final int CHUNK_TILES = 8;

    /** Which edge of a square a wall / door / window / fence sits on. */
    public enum Edge {
        /** North edge: blocks movement from the square to the north (y - 1). */
        NORTH,
        /** West edge: blocks movement from the square to the west (x - 1). */
        WEST
    }

    /** A door placed by {@link #door}; {@code open} doors are walkable floor. */
    public record Door(int x, int y, int z, Edge edge, boolean open) {}

    /** A window placed by {@link #window}. */
    public record Window(int x, int y, int z, Edge edge) {}

    /** A fence placed by {@link #fence}; {@code tall} uses TallHoppable flags. */
    public record Fence(int x, int y, int z, Edge edge, boolean tall) {}

    /** A stair link recorded by {@link #staircase} (flag-level only, see class doc). */
    public record StairLink(int x0, int y0, int z0, int x1, int y1, int z1, Edge edge) {}

    private final IsoWorld world;
    private final IsoCell cell;
    private final IsoChunkMap chunkMap;
    private final IsoChunk chunk;
    private final SliceY slice;

    private final List<Door> doors = new ArrayList<>();
    private final List<Window> windows = new ArrayList<>();
    private final List<Fence> fences = new ArrayList<>();
    private final List<StairLink> stairLinks = new ArrayList<>();
    private final Set<Long> brokenGlass = new HashSet<>();

    private SyntheticWorld(IsoWorld world, IsoCell cell, IsoChunkMap chunkMap,
                           IsoChunk chunk, SliceY slice) {
        this.world = world;
        this.cell = cell;
        this.chunkMap = chunkMap;
        this.chunk = chunk;
        this.slice = slice;
    }

    /**
     * Bootstraps a fresh headless world and registers its single chunk.
     * Replaces any previous world: {@code IsoWorld.instance} is global.
     */
    public static SyntheticWorld create() {
        IsoWorld world = new IsoWorld();
        IsoWorld.instance = world;
        IsoCell cell = new IsoCell(30, 30);
        world.currentCell = cell;
        IsoChunkMap cm = cell.getChunkMap(0);
        cm.setInitialPos(0, 0);
        IsoChunk chunk = new IsoChunk(cell);
        chunk.wx = 0;
        chunk.wy = 0;
        // REQUIRED: chunk.refs must contain the map, or setChunkDirect fails to register.
        chunk.refs.add(cm);
        if (!cm.setChunkDirect(chunk, false)) {
            throw new IllegalStateException("SyntheticWorld: chunk registration failed");
        }
        return new SyntheticWorld(world, cell, cm, chunk, new SliceY());
    }

    public IsoWorld world() { return world; }
    public IsoCell cell() { return cell; }
    public IsoChunkMap chunkMap() { return chunkMap; }
    public IsoChunk chunk() { return chunk; }

    public List<Door> doors() { return Collections.unmodifiableList(doors); }
    public List<Window> windows() { return Collections.unmodifiableList(windows); }
    public List<Fence> fences() { return Collections.unmodifiableList(fences); }
    public List<StairLink> stairLinks() { return Collections.unmodifiableList(stairLinks); }

    /** Reads a square back through the vanilla lookup ({@link EmberNavGrid#getSquare}). */
    public IsoGridSquare getSquare(int x, int y, int z) {
        return EmberNavGrid.getSquare(x, y, z);
    }

    /** Vanilla walkability of the square at these coordinates. */
    public boolean isWalkable(int x, int y, int z) {
        return EmberNavGrid.isWalkable(getSquare(x, y, z));
    }

    /** Builds a walkable-floor room at the origin (0, 0, z = 0). */
    public SyntheticWorld room(int w, int h) {
        return roomAt(0, 0, w, h, 0);
    }

    /** Builds a walkable-floor room at the origin on level {@code z}. */
    public SyntheticWorld upperFloor(int w, int h) {
        return roomAt(0, 0, w, h, 1);
    }

    /** Builds a walkable-floor room at ({@code x0}, {@code y0}) on level {@code z}. */
    public SyntheticWorld roomAt(int x0, int y0, int w, int h, int z) {
        for (int x = x0; x < x0 + w; x++) {
            for (int y = y0; y < y0 + h; y++) {
                floor(x, y, z);
            }
        }
        return this;
    }

    /** Places one walkable floor square. */
    public IsoGridSquare floor(int x, int y, int z) {
        return place(x, y, z, IsoFlagType.solidfloor);
    }

    /** Places one solid (not walkable) wall square. */
    public IsoGridSquare wall(int x, int y) {
        return wall(x, y, 0);
    }

    /** Places one solid (not walkable) wall square on level {@code z}. */
    public IsoGridSquare wall(int x, int y, int z) {
        return place(x, y, z, IsoFlagType.solid, IsoFlagType.solidfloor);
    }

    /**
     * Places a solid wall segment along one axis, inclusive of both ends.
     * Either {@code x0 == x1} (vertical) or {@code y0 == y1} (horizontal).
     */
    public SyntheticWorld wallSegment(int x0, int y0, int x1, int y1) {
        return wallSegment(x0, y0, x1, y1, 0);
    }

    /** Same as {@link #wallSegment(int, int, int, int)} on level {@code z}. */
    public SyntheticWorld wallSegment(int x0, int y0, int x1, int y1, int z) {
        if (x0 != x1 && y0 != y1) {
            throw new IllegalArgumentException("wallSegment must be axis-aligned: ("
                    + x0 + "," + y0 + ")-(" + x1 + "," + y1 + ")");
        }
        int dx = Integer.compare(x1, x0);
        int dy = Integer.compare(y1, y0);
        int x = x0;
        int y = y0;
        while (true) {
            wall(x, y, z);
            if (x == x1 && y == y1) break;
            x += dx;
            y += dy;
        }
        return this;
    }

    /**
     * Places a door in a wall line. An open door is a walkable floor square;
     * a closed door is a solid square with a {@code DoorWallN} /
     * {@code DoorWallW} flag (verified to block {@code canStep}).
     * The square is recorded in {@link #doors()} either way.
     */
    public IsoGridSquare door(int x, int y, Edge edge, boolean open) {
        return door(x, y, 0, edge, open);
    }

    /** Same as {@link #door(int, int, Edge, boolean)} on level {@code z}. */
    public IsoGridSquare door(int x, int y, int z, Edge edge, boolean open) {
        IsoGridSquare sq;
        if (open) {
            sq = floor(x, y, z);
        } else {
            sq = place(x, y, z, IsoFlagType.solid, IsoFlagType.solidfloor,
                    edge == Edge.NORTH ? IsoFlagType.DoorWallN : IsoFlagType.DoorWallW);
        }
        doors.add(new Door(x, y, z, edge, open));
        return sq;
    }

    /**
     * Places a window: a walkable floor square carrying a {@code WindowN} /
     * {@code WindowW} flag, recorded in {@link #windows()}. Flag-only: it does
     * not block movement (no real {@code IsoWindow} object headless).
     */
    public IsoGridSquare window(int x, int y, Edge edge) {
        return window(x, y, 0, edge);
    }

    /** Same as {@link #window(int, int, Edge)} on level {@code z}. */
    public IsoGridSquare window(int x, int y, int z, Edge edge) {
        IsoGridSquare sq = place(x, y, z, IsoFlagType.solidfloor,
                edge == Edge.NORTH ? IsoFlagType.WindowN : IsoFlagType.WindowW);
        windows.add(new Window(x, y, z, edge));
        return sq;
    }

    /**
     * Marks broken glass on a square. Attempts the real
     * {@code IsoGridSquare.addBrokenGlass()} first; headless that throws
     * (game {@code Rand} not initialised), in which case only this world's
     * registry records the hazard. Either way {@link #hasBrokenGlass} is true
     * afterwards.
     */
    public IsoGridSquare brokenGlass(int x, int y) {
        return brokenGlass(x, y, 0);
    }

    /** Same as {@link #brokenGlass(int, int)} on level {@code z}. */
    public IsoGridSquare brokenGlass(int x, int y, int z) {
        IsoGridSquare sq = getSquare(x, y, z);
        if (sq == null) {
            sq = floor(x, y, z);
        }
        try {
            sq.addBrokenGlass();
        } catch (Throwable ignored) {
            // Headless: IsoBrokenGlass needs game Rand; registry below is the fallback.
        }
        brokenGlass.add(key(x, y, z));
        return sq;
    }

    /** True if broken glass was recorded here, or the square carries a real one. */
    public boolean hasBrokenGlass(int x, int y, int z) {
        if (brokenGlass.contains(key(x, y, z))) return true;
        IsoGridSquare sq = getSquare(x, y, z);
        return sq != null && sq.getBrokenGlass() != null;
    }

    /**
     * Places a fence on a walkable floor square: {@code HoppableN} /
     * {@code HoppableW} for a low fence. A tall fence additionally carries the
     * {@code WallN} / {@code WallW} flag plus {@code TallHoppableN} /
     * {@code TallHoppableW}: {@link EmberNavGrid#fenceEdgeKind} reads
     * {@code WallN}/{@code WallW} as {@code TALL} (it does not check the
     * TallHoppable flags), and the wall flag is bypassed for the fence edge
     * by {@code canStep}'s special-edge rule, so the square stays crossable
     * at climb cost rather than blocked.
     */
    public IsoGridSquare fence(int x, int y, Edge edge, boolean tall) {
        return fence(x, y, 0, edge, tall);
    }

    /** Same as {@link #fence(int, int, Edge, boolean)} on level {@code z}. */
    public IsoGridSquare fence(int x, int y, int z, Edge edge, boolean tall) {
        IsoFlagType[] flags;
        if (edge == Edge.NORTH) {
            flags = tall
                    ? new IsoFlagType[] {IsoFlagType.solidfloor, IsoFlagType.WallN, IsoFlagType.TallHoppableN}
                    : new IsoFlagType[] {IsoFlagType.solidfloor, IsoFlagType.HoppableN};
        } else {
            flags = tall
                    ? new IsoFlagType[] {IsoFlagType.solidfloor, IsoFlagType.WallW, IsoFlagType.TallHoppableW}
                    : new IsoFlagType[] {IsoFlagType.solidfloor, IsoFlagType.HoppableW};
        }
        IsoGridSquare sq = place(x, y, z, flags);
        fences.add(new Fence(x, y, z, edge, tall));
        return sq;
    }

    /**
     * Places a flag-level staircase: floor on both levels plus an
     * {@code attachtostairs} marker on the lower square, and records the
     * link in {@link #stairLinks()}. TODO: real {@code IsoThumpable} stair
     * objects via {@code AddStairs} need game init ({@code SandboxOptions});
     * until then {@code EmberNavGrid} stair linkage returns null for these.
     */
    public StairLink staircase(int x, int y, int z, Edge edge) {
        IsoGridSquare lower = place(x, y, z, IsoFlagType.solidfloor, IsoFlagType.attachtostairs);
        if (lower == null) throw new IllegalStateException("staircase: no square at " + x + "," + y + "," + z);
        floor(x, y, z + 1);
        StairLink link = new StairLink(x, y, z, x, y, z + 1, edge);
        stairLinks.add(link);
        return link;
    }

    private IsoGridSquare place(int x, int y, int z, IsoFlagType... flags) {
        checkBounds(x, y, z);
        IsoGridSquare sq = new IsoGridSquare(cell, slice, x, y, z);
        for (IsoFlagType flag : flags) {
            sq.getProperties().set(flag);
        }
        chunkMap.setGridSquare(sq, x, y, z);
        return sq;
    }

    private static void checkBounds(int x, int y, int z) {
        if (x < 0 || x >= CHUNK_TILES || y < 0 || y >= CHUNK_TILES) {
            throw new IllegalArgumentException("SyntheticWorld: single chunk covers 0.."
                    + (CHUNK_TILES - 1) + ", got (" + x + "," + y + ")");
        }
        if (z < 0) {
            throw new IllegalArgumentException("SyntheticWorld: z must be >= 0, got " + z);
        }
    }

    private static long key(int x, int y, int z) {
        return ((long) x << 40) | ((long) y << 20) | (z & 0xFFFFF);
    }
}
