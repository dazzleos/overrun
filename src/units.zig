//! The armies: what each kind of unit and building is, and how they move,
//! build and are made. Everything is in one list (`World.things`), each a
//! `Thing` of a `Kind`, belonging to a player.

const std = @import("std");
const math = @import("math.zig");
const map_mod = @import("map.zig");
const nav = @import("nav.zig");
const combat = @import("combat.zig");
const flight = @import("flight.zig");

const V3 = math.V3;
const Map = map_mod.Map;

pub const Kind = enum(u8) {
    /// On two legs: quick and cheap.
    walker,
    /// On tracks: slow, tough; too big to go between trees.
    tank,
    /// Flying on four rotors: hovers, over water and hills alike.
    drone,
    /// On six wheels: builds buildings (see `Thing.order`); too wide to
    /// go between trees.
    builder,
    /// A large drone that builds buildings, flying to them over trees and
    /// water.
    air_builder,
    /// Winged, on two tilting rotors: hovers; flies fast, in runs over
    /// what is on the ground, three bombs a run.
    bomber,
    /// Like the bomber, smaller: goes after what flies, its gun firing the
    /// way it flies.
    fighter,
    /// On tracks, four guns pointing up: shoots at what flies.
    flak,
    /// A missile, launched from a silo: rising, arcing high across the
    /// map, and diving onto where it was sent, where it bursts (see
    /// `World.flyMissile`).
    missile,
    /// Guards the base: a gun on a column.
    tower,
    /// Makes units that go on the ground (see `Thing.queue`).
    factory,
    /// Makes energy.
    power,
    /// Digs metal.
    mine,
    /// Builds a missile (one at a time), and launches it anywhere.
    silo,
    /// Stores energy (see `battery_storage`).
    battery,
    /// Makes units that fly.
    air_factory,

    /// Whether it makes units.
    pub fn isFactory(k: Kind) bool {
        return k == .factory or k == .air_factory;
    }

    pub fn isBuilding(k: Kind) bool {
        return @intFromEnum(k) >= @intFromEnum(Kind.tower);
    }

    pub fn flies(k: Kind) bool {
        return k == .drone or k == .air_builder or k == .bomber or k == .fighter or k == .missile;
    }

    /// Whether it flies on wings (see `World.fly`): hovering, or tilted
    /// forward, flying fast.
    pub fn winged(k: Kind) bool {
        return k == .bomber or k == .fighter;
    }

    /// How high over the ground (or water) it flies.
    pub fn altitude(k: Kind) f32 {
        return switch (k) {
            .bomber => 5.5,
            .fighter => 4.5,
            else => 3,
        };
    }

    /// Whether trees are in its way (those on tracks and wheels are too
    /// big to go between them; walkers and fliers are not).
    pub fn blockedByTrees(k: Kind) bool {
        return k == .tank or k == .builder or k == .flak;
    }

    /// How much bigger than its model is drawn (see models.zig).
    pub fn scale(k: Kind) f32 {
        return switch (k) {
            .tank, .builder, .flak => 1.4,
            .air_builder => 1.3,
            .missile => 1.6,
            else => 1,
        };
    }

    /// How it finds its way (none: it flies straight).
    pub fn navClass(k: Kind) ?nav.Class {
        return switch (k) {
            .walker => .foot,
            .tank, .builder, .flak => .wheels,
            else => null,
        };
    }

    /// Whether it builds buildings.
    pub fn builds(k: Kind) bool {
        return k == .builder or k == .air_builder;
    }

    pub fn name(k: Kind) []const u8 {
        return switch (k) {
            .walker => "Walker",
            .tank => "Tank",
            .drone => "Drone",
            .builder => "Builder",
            .air_builder => "Air builder",
            .bomber => "Bomber",
            .fighter => "Fighter",
            .flak => "AA tank",
            .tower => "Tower",
            .factory => "Factory",
            .power => "Power plant",
            .mine => "Mine",
            .missile => "Missile",
            .silo => "Missile silo",
            .battery => "Battery",
            .air_factory => "Drone factory",
        };
    }

    /// Its name, short (for buttons).
    pub fn shortName(k: Kind) []const u8 {
        return switch (k) {
            .power => "Power",
            else => k.name(),
        };
    }

    /// Blocks a second, at its best.
    pub fn speed(k: Kind) f32 {
        return switch (k) {
            .walker => 3.2,
            .tank => 2.0,
            .drone => 4.5,
            .builder => 1.8,
            .air_builder => 3.0,
            .bomber => 9,
            .fighter => 12,
            .flak => 2.0,
            else => 0,
        };
    }

    /// How far round it is (for picking it, and keeping apart).
    pub fn radius(k: Kind) f32 {
        return switch (k) {
            .walker => 0.45,
            .tank => 0.84,
            .drone => 0.5,
            .builder => 0.84,
            .air_builder => 0.85,
            .bomber => 1.0,
            .fighter => 0.7,
            .flak => 0.84,
            .tower => 0.8,
            .factory => 2.2,
            .power => 1.4,
            .mine => 1.4,
            .missile => 0.4,
            .silo => 1.7,
            .battery => 1.0,
            .air_factory => 2.1,
        };
    }

    /// How tall it is (for picking it on the screen).
    pub fn height(k: Kind) f32 {
        return switch (k) {
            .walker => 1.1,
            .tank => 1.0,
            .drone => 0.5,
            .builder => 1.1,
            .air_builder => 0.8,
            .bomber => 0.6,
            .fighter => 0.45,
            .flak => 1.1,
            .tower => 2.4,
            .factory => 2.2,
            .power => 2.0,
            .mine => 2.6,
            .missile => 0.5,
            .silo => 1.0,
            .battery => 1.4,
            .air_factory => 1.7,
        };
    }

    /// What making one costs, and how long it takes (seconds).
    pub fn cost(k: Kind) Cost {
        return switch (k) {
            .walker => .{ .metal = 40, .seconds = 4 },
            .tank => .{ .metal = 90, .seconds = 7 },
            .drone => .{ .metal = 60, .seconds = 6 },
            .builder => .{ .metal = 110, .seconds = 8 },
            .air_builder => .{ .metal = 150, .seconds = 11 },
            .bomber => .{ .metal = 180, .seconds = 12 },
            .fighter => .{ .metal = 110, .seconds = 8 },
            .flak => .{ .metal = 120, .seconds = 8 },
            .tower => .{ .metal = 120, .seconds = 12 },
            .factory => .{ .metal = 320, .seconds = 25 },
            .power => .{ .metal = 70, .seconds = 8 },
            .mine => .{ .metal = 60, .seconds = 10 },
            .silo => .{ .metal = 400, .seconds = 30 },
            .battery => .{ .metal = 80, .seconds = 8 },
            .air_factory => .{ .metal = 360, .seconds = 25 },
            .missile => .{ .metal = 300, .seconds = 40 },
        };
    }
};

/// What making one costs, in metal (energy is not spent making things:
/// buildings use it as they run, see `energyUse`).
pub const Cost = struct { metal: f32, seconds: f32 };

/// How much energy a building uses each second as it runs (less than
/// nothing: makes); with none stored (and not enough made), what uses it
/// stops.
pub fn energyUse(k: Kind) f32 {
    return switch (k) {
        .power => -12,
        .factory, .air_factory => 2,
        .mine => 1.5,
        .silo => 1,
        .tower => 0.5,
        else => 0,
    };
}

/// How much energy a player can store, and how much more each battery
/// holds.
pub const base_storage: f32 = 500;
pub const battery_storage: f32 = 1000;

/// Repairing: how much of its health a building gets back a second, and
/// the metal each point costs (a factory, from nothing: 300).
pub const repair_rate: f32 = 0.04;
pub const repair_metal: f32 = 0.25;

/// A missile's flight: a few seconds to climb and dive, and its speed
/// across the map.
const missile_seconds: f32 = 6;
const missile_speed: f32 = 28;

/// Where a missile is, `s` (0 to 1) of the way: across, slow at first
/// (rising straight up) and at the end (diving straight down); up, an arc
/// higher the further it goes.
pub fn missileAt(map: *const Map, t: Thing, s: f32) V3 {
    const across = s * s * (3 - 2 * s);
    const x = t.launch[0] + (t.rally[0] - t.launch[0]) * across;
    const z = t.launch[1] + (t.rally[1] - t.launch[1]) * across;
    const d = @sqrt((t.rally[0] - t.launch[0]) * (t.rally[0] - t.launch[0]) + (t.rally[1] - t.launch[1]) * (t.rally[1] - t.launch[1]));
    const apex = 30 + 0.12 * d;
    const start = map.heightAt(t.launch[0], t.launch[1]) + 0.5;
    const end = map.heightAt(t.rally[0], t.rally[1]);
    const base = start + (end - start) * s;
    return .{ x, base + 4 * apex * s * (1 - s), z };
}

/// What a factory makes (on the ground), and a drone factory (flying).
pub const buildable = [_]Kind{ .walker, .tank, .flak, .builder };
pub const air_buildable = [_]Kind{ .drone, .fighter, .bomber, .air_builder };

/// What factory kind `k` makes.
pub fn makes(k: Kind) []const Kind {
    return switch (k) {
        .factory => &buildable,
        .air_factory => &air_buildable,
        else => &.{},
    };
}

/// Armouring a building: what it costs (of what building it did), how
/// long it takes, and how much of what hits it then hurts.
pub const armour_share: f32 = 0.6;
pub const armour_seconds: f32 = 12;
pub const armoured_damage: f32 = 0.5;

pub fn armourCost(k: Kind) f32 {
    return k.cost().metal * armour_share;
}
/// What a builder builds.
pub const constructible = [_]Kind{ .power, .battery, .mine, .tower, .factory, .air_factory, .silo };

/// A builder's order: to build a `kind` at `at`, facing `yaw`.
pub const Order = struct {
    kind: Kind,
    at: [2]f32,
    yaw: f32 = 0,
};

/// Players' colours (their units' and buildings' marks).
pub const team_colours = [4]u24{ 0x3b82f6, 0xe64535, 0x38c26a, 0xeab72c };

pub const max_things = 512;
/// Units a factory can have waiting to be made.
pub const max_queue = 20;

pub const Thing = struct {
    kind: Kind,
    team: u2,
    /// Its middle, on the ground (or, flying, its height over it).
    pos: V3,
    /// Which way it faces, right of north.
    yaw: f32 = 0,
    /// Where it is going, if anywhere: by way of `path`'s points from
    /// `path_next` on (round what is in the way).
    goal: ?[2]f32 = null,
    path: nav.Path = .{},
    path_next: u8 = 0,
    /// How many times it has looked for a way again (stuck), since sent.
    replans: u8 = 0,
    /// How much more it can take (set to its most when added).
    health: f32 = 0,
    /// Its weapons' (see combat.zig): what each is aimed at, how long
    /// until each can fire again, and how long until it looks again for
    /// what to shoot; a tower's barrel to fire next.
    targets: [2]?u16 = .{ null, null },
    cool: [2]f32 = .{ 0, 0 },
    look: f32 = 0,
    barrel: bool = false,
    /// What it was told to attack (bombers and fighters go after it).
    attack: ?u16 = null,
    /// Winged: how far tilted forward (0, hovering, to 1, flying fast),
    /// and banked (turning); a bomber's bombs left this run, and how long
    /// until the next can drop (or, all dropped, until it turns back).
    tilt: f32 = 0,
    bank: f32 = 0,
    bombs: u8 = 3,
    run_time: f32 = 0,
    /// Shots fired (an AA tank's next barrel).
    gun: u8 = 0,
    /// A silo's: whether its missile is ready (`progress` how far it is
    /// built, while `queued`).
    armed: bool = false,
    /// A building's: being repaired (healing, paid for in metal).
    repairing: bool = false,
    /// A building's: whether it has energy to run (short of it, some are
    /// shut down).
    powered: bool = true,
    /// A building's: armoured (hurt less), or being (how far through).
    armoured: bool = false,
    armouring: bool = false,
    armour_done: f32 = 0,
    /// A unit sent with others: going no faster than the slowest of them
    /// can (0: as fast as it can).
    cap: f32 = 0,
    /// A missile's: where it was launched from (it is going to `rally`),
    /// how long its flight takes, and how long it has flown.
    launch: [2]f32 = .{ 0, 0 },
    flight: f32 = 0,
    flown: f32 = 0,
    /// How fast it is going now (it speeds up and slows down).
    moving: f32 = 0,
    /// Its legs', rotors' or drill's turn, for drawing them.
    phase: f32 = 0,
    /// A tower's gun's way.
    aim: f32 = 0,
    /// A factory's: what it is to make, in turn, and how far through the
    /// first it is (0 to 1).
    queue: [max_queue]Kind = undefined,
    queued: u8 = 0,
    progress: f32 = 0,
    /// Where a factory's units go once made.
    rally: [2]f32 = .{ 0, 0 },
    /// A building's: how far built it is (0 to 1; until 1, it does
    /// nothing).
    built: f32 = 1,
    /// A builder's: what it is to build, and (once it has started) the
    /// building.
    order: ?Order = null,
    site: ?usize = null,

    /// Its first in line, if it has one.
    pub fn making(t: *const Thing) ?Kind {
        return if (t.queued > 0) t.queue[0] else null;
    }

    /// How many of `k` are waiting to be made.
    pub fn queuedOf(t: *const Thing, k: Kind) u32 {
        var n: u32 = 0;
        for (t.queue[0..t.queued]) |q| if (q == k) {
            n += 1;
        };
        return n;
    }
};

pub const Resources = struct {
    metal: f32 = 300,
    energy: f32 = 300,
    /// How much energy can be stored (see `base_storage`), and how much
    /// more is made than used each second (less than nothing: used).
    storage: f32 = base_storage,
    net: f32 = 0,
    /// Short of energy: some buildings shut down (see `World.useEnergy`),
    /// and how many.
    short: bool = false,
    shut_down: u16 = 0,
};

/// Short of energy, which buildings are shut down changes this often
/// (seconds); and how much must be stored again before all run.
const shuffle_seconds: f32 = 4;
const recovered: f32 = 25;

/// The metal a building digs (or makes) each second (when powered).
pub fn metalIncome(k: Kind) f32 {
    return switch (k) {
        .mine => 4,
        .factory => 1,
        else => 0,
    };
}

pub const World = struct {
    map: *const Map,
    things: [max_things]Thing = undefined,
    count: usize = 0,
    resources: [4]Resources = @splat(.{}),
    /// The game's time, in seconds.
    time: f32 = 0,
    /// Shots in flight, and bursts (see combat.zig).
    shots: [combat.max_shots]combat.Shot = undefined,
    shot_count: usize = 0,
    blasts: [combat.max_blasts]combat.Blast = undefined,
    blast_count: usize = 0,
    /// Where each thing went when the destroyed were taken out (null:
    /// destroyed), if any were this step.
    moved_to: [max_things]?u16 = undefined,
    removed_any: bool = false,

    pub fn add(w: *World, t: Thing) ?usize {
        if (w.count == max_things) return null;
        var with = t;
        with.pos[1] = w.groundFor(t.kind, t.pos[0], t.pos[2]);
        if (with.health <= 0) with.health = combat.maxHealth(t.kind);
        with.aim = t.yaw;
        if (t.kind.isBuilding()) w.map.nav.building(t.pos[0], t.pos[2], t.kind.radius(), true);
        w.things[w.count] = with;
        w.count += 1;
        return w.count - 1;
    }

    pub fn all(w: *World) []Thing {
        return w.things[0..w.count];
    }

    /// Where `k` is (up and down) at (x, z): on the ground, or flying.
    pub fn groundFor(w: *const World, k: Kind, x: f32, z: f32) f32 {
        return if (k.flies()) w.map.surfaceAt(x, z) + k.altitude() else w.map.heightAt(x, z);
    }

    /// Player `team`'s base: a factory, a power plant, a mine and a tower,
    /// and a few units to start with.
    pub fn addBase(w: *World, team: u2) void {
        const b = map_mod.bases[team];
        // Towards the middle of the map.
        const out = math.normalize(.{ map_mod.centre[0] - b[0], 0, map_mod.centre[1] - b[1] });
        const side = V3{ -out[2], 0, out[0] };
        const at = struct {
            fn f(base: [2]f32, o: V3, s: V3, fwd: f32, across: f32) V3 {
                return .{ base[0] + o[0] * fwd + s[0] * across, 0, base[1] + o[2] * fwd + s[2] * across };
            }
        }.f;
        const facing = std.math.atan2(out[0], -out[2]);
        if (w.add(.{ .kind = .factory, .team = team, .pos = at(b, out, side, 0, 0), .yaw = facing })) |i| {
            const r = at(b, out, side, 5, 0);
            w.things[i].rally = .{ r[0], r[2] };
        }
        _ = w.add(.{ .kind = .power, .team = team, .pos = at(b, out, side, -2, -5), .yaw = facing });
        _ = w.add(.{ .kind = .mine, .team = team, .pos = at(b, out, side, -2, 5), .yaw = facing });
        _ = w.add(.{ .kind = .tower, .team = team, .pos = at(b, out, side, 6, -4), .yaw = facing });
        _ = w.add(.{ .kind = .tower, .team = team, .pos = at(b, out, side, 6, 4), .yaw = facing });
        for ([_]Kind{ .walker, .walker, .tank, .drone }, 0..) |k, i| {
            _ = w.add(.{ .kind = k, .team = team, .pos = at(b, out, side, 4, @as(f32, @floatFromInt(i)) * 1.5 - 2.25), .yaw = facing });
        }
    }

    /// Asks factory `i` to make a `k`, if it has room in its line.
    pub fn enqueue(w: *World, i: usize, k: Kind) bool {
        const f = &w.things[i];
        if (!f.kind.isFactory() or f.queued == max_queue) return false;
        if (std.mem.indexOfScalar(Kind, makes(f.kind), k) == null) return false;
        f.queue[f.queued] = k;
        f.queued += 1;
        return true;
    }

    /// Takes the last of `k` out of factory `i`'s line.
    pub fn dequeue(w: *World, i: usize, k: Kind) void {
        const f = &w.things[i];
        var j: usize = f.queued;
        while (j > 0) {
            j -= 1;
            if (f.queue[j] != k) continue;
            std.mem.copyForwards(Kind, f.queue[j .. f.queued - 1], f.queue[j + 1 .. f.queued]);
            f.queued -= 1;
            if (j == 0) f.progress = 0;
            return;
        }
    }

    /// Sends the units `which` to (x, z): spread out round it, so they do
    /// not all try to stand in one place.
    pub fn moveTo(w: *World, which: []const usize, x: f32, z: f32) void {
        // Builders sent elsewhere stop building (what they had started
        // stays, to be gone on with).
        for (which) |i| {
            w.things[i].order = null;
            w.things[i].site = null;
            w.things[i].attack = null;
        }
        var n: usize = 0;
        for (which) |i| {
            if (w.things[i].kind.isBuilding()) continue;
            n += 1;
        }
        if (n == 0) return;
        const across: usize = @intFromFloat(@ceil(@sqrt(@as(f32, @floatFromInt(n)))));
        // Far enough apart for the biggest of them.
        var widest: f32 = 0;
        for (which) |i| if (!w.things[i].kind.isBuilding()) {
            widest = @max(widest, w.things[i].kind.radius());
        };
        const gap: f32 = @max(1.4, 2 * widest + 0.3);
        // Together: as fast as the slowest of them can go.
        var slowest: f32 = std.math.inf(f32);
        for (which) |i| if (!w.things[i].kind.isBuilding()) {
            slowest = @min(slowest, w.things[i].kind.speed());
        };
        const cap: f32 = if (n > 1) slowest else 0;
        // One way for each class (from the middle of those of it), shared.
        var ways: [2]?nav.Path = .{ null, null };
        for (std.enums.values(nav.Class)) |class| {
            var mid: [2]f32 = .{ 0, 0 };
            var m: f32 = 0;
            for (which) |i| if (w.things[i].kind.navClass() == class) {
                mid[0] += w.things[i].pos[0];
                mid[1] += w.things[i].pos[2];
                m += 1;
            };
            if (m == 0) continue;
            var p: nav.Path = .{};
            if (w.map.nav.find(class, .{ mid[0] / m, mid[1] / m }, .{ x, z }, &p)) ways[@intFromEnum(class)] = p;
        }
        var k: usize = 0;
        for (which) |i| {
            const t = &w.things[i];
            if (t.kind.isBuilding()) continue;
            const col: f32 = @floatFromInt(k % across);
            const row: f32 = @floatFromInt(k / across);
            const half = @as(f32, @floatFromInt(across - 1)) / 2;
            const slot = [2]f32{ x + (col - half) * gap, z + (row - half) * gap };
            k += 1;
            t.goal = slot;
            t.cap = cap;
            t.replans = 0;
            t.path = .{};
            t.path_next = 0;
            const class = t.kind.navClass() orelse continue;
            const way = ways[@intFromEnum(class)] orelse continue;
            // The shared way, from its point nearest this one (of the
            // first few), to its own place at the end.
            var start: usize = 0;
            var best: f32 = std.math.inf(f32);
            for (way.points[0..@min(way.len, 4)], 0..) |p, j| {
                const d = (p[0] - t.pos[0]) * (p[0] - t.pos[0]) + (p[1] - t.pos[2]) * (p[1] - t.pos[2]);
                if (d < best) {
                    best = d;
                    start = j;
                }
            }
            for (way.points[start .. way.len - 1]) |p| {
                t.path.points[t.path.len] = p;
                t.path.len += 1;
            }
        }
    }

    /// A building being repaired: healing a little each second, paying
    /// metal for it; done when whole (waiting, when there is no metal).
    fn repair(w: *World, t: *Thing, dt: f32) void {
        const most = combat.maxHealth(t.kind);
        const r = &w.resources[t.team];
        const want = @min(most - t.health, most * repair_rate * dt);
        const can = @min(want, r.metal / repair_metal);
        t.health += can;
        r.metal -= can * repair_metal;
        if (t.health >= most - 0.01) {
            t.health = most;
            t.repairing = false;
        }
    }

    /// A building being armoured: paid for as it goes; done, armoured.
    fn armour(w: *World, t: *Thing, dt: f32) void {
        const part = dt / armour_seconds;
        const r = &w.resources[t.team];
        const cost = armourCost(t.kind) * part;
        if (r.metal < cost) return;
        r.metal -= cost;
        t.armour_done += part;
        if (t.armour_done < 1) return;
        t.armoured = true;
        t.armouring = false;
    }

    /// Armours building `i` (of `team`'s, built, not yet armoured); or, if
    /// it is being, stops (what was paid kept: it goes on from there).
    pub fn toggleArmour(w: *World, i: usize, team: u2) void {
        const t = &w.things[i];
        if (!t.kind.isBuilding() or t.team != team or t.built < 1 or t.armoured) return;
        t.armouring = !t.armouring;
    }

    /// Repairs the buildings `which` (of `team`'s, damaged); if they all
    /// are being, stops.
    pub fn toggleRepair(w: *World, which: []const usize, team: u2) void {
        var every = true;
        var any = false;
        for (which) |i| {
            const t = w.things[i];
            if (!t.kind.isBuilding() or t.team != team or t.built < 1) continue;
            if (t.health >= combat.maxHealth(t.kind) and !t.repairing) continue;
            any = true;
            if (!t.repairing) every = false;
        }
        if (!any) return;
        for (which) |i| {
            const t = &w.things[i];
            if (!t.kind.isBuilding() or t.team != team or t.built < 1) continue;
            t.repairing = !every and t.health < combat.maxHealth(t.kind);
        }
    }

    /// A silo told to: builds its missile, paying for it as it goes.
    fn buildMissile(w: *World, t: *Thing, dt: f32) void {
        t.phase += dt;
        if (t.armed or t.queued == 0) return;
        const c = Kind.missile.cost();
        const part = dt / c.seconds;
        const r = &w.resources[t.team];
        if (!t.powered or r.metal < c.metal * part) return;
        r.metal -= c.metal * part;
        t.progress += part;
        if (t.progress < 1) return;
        t.progress = 0;
        t.queued = 0;
        t.armed = true;
    }

    /// Silo `i` starts building a missile (if it has none, and is not).
    pub fn orderMissile(w: *World, i: usize) void {
        const t = &w.things[i];
        if (t.kind != .silo or t.built < 1 or t.armed) return;
        t.queued = 1;
    }

    /// Silo `i` launches its missile at `at` (anywhere on the map).
    pub fn launchMissile(w: *World, i: usize, at: [2]f32) void {
        const s = w.things[i];
        if (s.kind != .silo or !s.armed) return;
        const d = @sqrt((at[0] - s.pos[0]) * (at[0] - s.pos[0]) + (at[1] - s.pos[2]) * (at[1] - s.pos[2]));
        const m = w.add(.{ .kind = .missile, .team = s.team, .pos = s.pos, .rally = at, .launch = .{ s.pos[0], s.pos[2] }, .flight = missile_seconds + d / missile_speed }) orelse return;
        w.things[m].pos = s.pos + V3{ 0, 0.5, 0 };
        w.things[i].armed = false;
    }

    /// A missile's way: up out of its silo, high over the map, and down
    /// onto where it was sent; there, it bursts.
    fn flyMissile(w: *World, t: *Thing, dt: f32) void {
        t.flown += dt;
        const s = @min(1, t.flown / t.flight);
        const was = t.pos;
        t.pos = missileAt(w.map, t.*, s);
        // Facing the way it goes: `yaw` across, `aim` up (or down).
        const d = t.pos - was;
        const across = @sqrt(d[0] * d[0] + d[2] * d[2]);
        if (across > 1e-4) t.yaw = std.math.atan2(d[0], -d[2]);
        t.aim = std.math.atan2(d[1], @max(across, 1e-4));
        t.phase += dt * 30;
        if (s >= 1) {
            combat.missileBurst(w, t.team, t.pos);
            t.health = 0;
        }
    }

    /// Tells the units `which` to attack thing `j`: those that can, go
    /// after it (on the ground, sent to it; winged, flying at it).
    pub fn orderAttack(w: *World, which: []const usize, j: usize) void {
        const at = w.things[j].pos;
        var ground: [max_things]usize = undefined;
        var n: usize = 0;
        for (which) |i| {
            const t = w.things[i];
            if (t.kind.isBuilding() or t.kind.builds()) continue;
            if (!t.kind.winged()) {
                ground[n] = i;
                n += 1;
            }
        }
        w.moveTo(ground[0..n], at[0], at[2]);
        for (which) |i| {
            const t = &w.things[i];
            if (t.kind.isBuilding() or t.kind.builds()) continue;
            const can = for (combat.weaponsOf(t.kind)) |maybe| {
                if (maybe) |wp| if (wp.canHit(w.things[j].kind)) break true;
            } else false;
            if (!can) continue;
            t.attack = @intCast(j);
            if (t.kind.winged()) t.goal = null;
        }
    }

    /// Sends unit `i` to `to`, finding its way.
    pub fn send(w: *World, i: usize, to: [2]f32) void {
        const t = &w.things[i];
        t.goal = to;
        t.cap = 0;
        t.replans = 0;
        w.route(t);
    }

    /// Finds `t`'s way to its goal (none, flying: it goes straight).
    fn route(w: *World, t: *Thing) void {
        t.path = .{};
        t.path_next = 0;
        const goal = t.goal orelse return;
        const class = t.kind.navClass() orelse return;
        var p: nav.Path = .{};
        if (!w.map.nav.find(class, .{ t.pos[0], t.pos[2] }, goal, &p)) return;
        // (Its last point is the goal.)
        if (p.len > 0) p.len -= 1;
        t.path = p;
    }

    /// On by `dt` seconds.
    pub fn step(w: *World, dt: f32) void {
        w.time += dt;
        w.useEnergy(dt);
        for (w.all(), 0..) |*t, i| {
            if (t.built < 1) continue;
            if (t.repairing) w.repair(t, dt);
            if (t.armouring) w.armour(t, dt);
            switch (t.kind) {
                .walker, .tank, .drone, .flak => w.moveUnit(t, i, dt),
                .bomber, .fighter => flight.step(w, t, dt),
                .builder, .air_builder => {
                    w.construct(t, dt);
                    w.moveUnit(t, i, dt);
                },
                .tower => {},
                .factory, .air_factory => w.make(t, dt),
                .mine, .power => t.phase += dt * 2,
                .silo => w.buildMissile(t, dt),
                .battery => t.phase += dt,
                .missile => w.flyMissile(t, dt),
            }
            if (t.powered) w.resources[t.team].metal += metalIncome(t.kind) * dt;
        }
        combat.step(w, dt);
        w.removeDestroyed();
    }

    /// Each player's buildings make and use energy: what is stored goes up
    /// (as far as there is room for) or down. With none left, and more
    /// used than made, just enough buildings are shut down for what runs
    /// to use no more than is made: which, picked at random, changing
    /// every few seconds; all run again once some is stored.
    fn useEnergy(w: *World, dt: f32) void {
        var made: [4]f32 = @splat(0);
        var used: [4]f32 = @splat(0);
        var storage: [4]f32 = @splat(base_storage);
        for (w.things[0..w.count]) |t| {
            if (!t.kind.isBuilding() or t.built < 1) continue;
            const e = energyUse(t.kind);
            if (e < 0) made[t.team] -= e else used[t.team] += e;
            if (t.kind == .battery) storage[t.team] += battery_storage;
        }
        const slot: u32 = @intFromFloat(@max(0, w.time) / shuffle_seconds);
        for (&w.resources, 0..) |*r, team| {
            r.storage = storage[team];
            if (r.short) {
                if (r.energy >= recovered or made[team] >= used[team]) r.short = false;
            } else if (r.energy <= 0 and used[team] > made[team]) r.short = true;
            // What runs: all; or, short, as many as what is made runs (in
            // an order picked at random for this while).
            var running = used[team];
            r.shut_down = 0;
            for (w.things[0..w.count]) |*t| {
                if (t.team == team) t.powered = true;
            }
            if (r.short) {
                running = 0;
                var order: [max_things]struct { key: u32, i: u16 } = undefined;
                var n: usize = 0;
                for (w.things[0..w.count], 0..) |t, i| {
                    if (t.team != team or !t.kind.isBuilding() or t.built < 1 or energyUse(t.kind) <= 0) continue;
                    order[n] = .{ .key = shuffleKey(slot, @intCast(i), t.kind), .i = @intCast(i) };
                    n += 1;
                }
                std.mem.sort(@TypeOf(order[0]), order[0..n], {}, struct {
                    fn less(_: void, a: @TypeOf(order[0]), b: @TypeOf(order[0])) bool {
                        return a.key < b.key;
                    }
                }.less);
                for (order[0..n]) |o| {
                    const t = &w.things[o.i];
                    const e = energyUse(t.kind);
                    if (running + e <= made[team] + 1e-4) {
                        running += e;
                    } else {
                        t.powered = false;
                        r.shut_down += 1;
                    }
                }
            }
            r.net = made[team] - running;
            r.energy = std.math.clamp(r.energy + r.net * dt, 0, r.storage);
        }
    }

    pub fn addShot(w: *World, s: combat.Shot) void {
        if (w.shot_count == combat.max_shots) return;
        w.shots[w.shot_count] = s;
        w.shot_count += 1;
    }

    pub fn addBlast(w: *World, b: combat.Blast) void {
        if (w.blast_count == combat.max_blasts) return;
        w.blasts[w.blast_count] = b;
        w.blast_count += 1;
    }

    /// Takes out what has been destroyed (each bursting), keeping the rest
    /// in order; where each went is in `moved_to`.
    fn removeDestroyed(w: *World) void {
        w.removed_any = false;
        for (w.things[0..w.count]) |t| {
            if (t.health <= 0) break;
        } else return;
        var n: usize = 0;
        for (0..w.count) |i| {
            const t = w.things[i];
            if (t.health <= 0) {
                w.moved_to[i] = null;
                w.addBlast(.{ .at = t.pos + V3{ 0, t.kind.height() * 0.4, 0 }, .size = switch (combat.armourOf(t.kind)) {
                    .light => 0.8,
                    .vehicle => 1.5,
                    .building => 2.6,
                    .air => 1.4,
                } });
                if (t.kind.isBuilding()) w.map.nav.building(t.pos[0], t.pos[2], t.kind.radius(), false);
                continue;
            }
            w.moved_to[i] = @intCast(n);
            w.things[n] = t;
            n += 1;
        }
        w.count = n;
        w.removed_any = true;
        for (w.things[0..w.count]) |*t| {
            for (&t.targets) |*target| target.* = if (target.*) |j| w.moved_to[j] else null;
            t.attack = if (t.attack) |j| w.moved_to[j] else null;
            if (t.site) |s| {
                if (w.moved_to[s]) |ns| t.site = ns else {
                    // What it was building is gone.
                    t.site = null;
                    t.order = null;
                }
            }
        }
    }

    fn moveUnit(w: *World, t: *Thing, i: usize, dt: f32) void {
        const k = t.kind;
        var want: f32 = 0;
        var heading = t.yaw;
        // On its way: to the next point of its way, on (not slowing) when
        // near it; then to its goal.
        while (t.path_next < t.path.len) {
            const p = t.path.points[t.path_next];
            const dx = p[0] - t.pos[0];
            const dz = p[1] - t.pos[2];
            if (dx * dx + dz * dz > 0.8 * 0.8) break;
            t.path_next += 1;
        }
        if (t.path_next < t.path.len and t.goal != null) {
            const p = t.path.points[t.path_next];
            heading = std.math.atan2(p[0] - t.pos[0], -(p[1] - t.pos[2]));
            want = k.speed();
        } else if (t.goal) |g| {
            const dx = g[0] - t.pos[0];
            const dz = g[1] - t.pos[2];
            const d = @sqrt(dx * dx + dz * dz);
            if (d < 0.15) {
                t.goal = null;
            } else {
                heading = std.math.atan2(dx, -dz);
                // Slowing as it gets there.
                want = k.speed() * @min(1, d / 1.2);
            }
        }
        // Turning towards where it is going: tanks turn on the spot, then
        // go; walkers and drones turn as they go.
        const diff = angleDiff(heading, t.yaw);
        const turn_rate: f32 = switch (k) {
            .tank, .builder, .flak => 2.2,
            .walker => 6,
            else => 5,
        };
        t.yaw = wrap(t.yaw + std.math.clamp(diff, -turn_rate * dt, turn_rate * dt));
        if ((k == .tank or k == .builder or k == .flak) and @abs(diff) > 0.6) want = 0;
        if (t.cap > 0) want = @min(want, t.cap);
        t.moving += (want - t.moving) * @min(1, 4 * dt);
        var nx = t.pos[0] + @sin(t.yaw) * t.moving * dt;
        var nz = t.pos[2] - @cos(t.yaw) * t.moving * dt;
        // Kept apart from the others (flying ones from flying ones, those
        // on the ground from those on the ground and from buildings).
        for (w.things[0..w.count], 0..) |o, j| {
            if (j == i or o.kind.flies() != k.flies() or o.kind == .missile) continue;
            const dx = nx - o.pos[0];
            const dz = nz - o.pos[2];
            const want_d = k.radius() + o.kind.radius();
            const d2 = dx * dx + dz * dz;
            if (d2 >= want_d * want_d or d2 < 1e-6) continue;
            const d = @sqrt(d2);
            const push = (want_d - d) * (if (o.kind.isBuilding()) @as(f32, 1) else 0.5);
            nx += dx / d * push;
            nz += dz / d * push;
        }
        // Flying, anywhere over the map; on the ground, where it can go:
        // sliding along what is in the way, if it can; stopping if not.
        if (w.canBe(k, nx, nz)) {
            t.pos[0] = nx;
            t.pos[2] = nz;
        } else if (t.moving > 0.05 and w.canBe(k, nx, t.pos[2])) {
            t.pos[0] = nx;
        } else if (t.moving > 0.05 and w.canBe(k, t.pos[0], nz)) {
            t.pos[2] = nz;
        } else if (t.goal != null and t.replans < 3) {
            // Stuck (its way cut short, or a corner caught): a way from
            // here, looked for again.
            t.moving = 0;
            t.replans += 1;
            w.route(t);
        } else {
            t.moving = 0;
            t.goal = null;
        }
        // Up or down to the ground; flying, a little bob.
        const ground = w.groundFor(k, t.pos[0], t.pos[2]);
        t.pos[1] += (ground - t.pos[1]) * @min(1, (if (k.flies()) @as(f32, 3) else 20) * dt);
        t.phase += dt * switch (k) {
            .walker => t.moving * 3.2,
            .tank, .builder, .flak => t.moving * 2,
            else => 30,
        };
    }

    /// Whether a `k` can be at (x, z): flying, anywhere over the map; on
    /// the ground, out of the water, off cliffs (and, too big to go
    /// between trees, not among them).
    pub fn canBe(w: *const World, k: Kind, x: f32, z: f32) bool {
        if (k.flies()) return map_mod.inside(x, z) > 0.5;
        if (!w.map.passable(x, z)) return false;
        return !k.blockedByTrees() or !w.map.treeNear(x, z, k.radius());
    }

    /// Whether a `k` (a building) can be built at (x, z): on the map, on
    /// level enough dry ground, among no trees, and clear of other
    /// buildings.
    pub fn canPlace(w: *const World, k: Kind, x: f32, z: f32) bool {
        const r = k.radius();
        if (map_mod.inside(x, z) < r + 1) return false;
        const h = w.map.heightAt(x, z);
        for ([_][2]f32{ .{ 0, 0 }, .{ r, 0 }, .{ -r, 0 }, .{ 0, r }, .{ 0, -r } }) |d| {
            if (!w.map.passable(x + d[0], z + d[1])) return false;
            if (@abs(w.map.heightAt(x + d[0], z + d[1]) - h) > 0.6) return false;
        }
        if (w.map.treeNear(x, z, r)) return false;
        for (w.things[0..w.count]) |o| {
            if (!o.kind.isBuilding()) continue;
            const dx = o.pos[0] - x;
            const dz = o.pos[2] - z;
            const apart = o.kind.radius() + r + 0.4;
            if (dx * dx + dz * dz < apart * apart) return false;
        }
        // Nor where another builder means to build.
        for (w.things[0..w.count]) |o| {
            const ord = o.order orelse continue;
            if (o.site != null) continue;
            const dx = ord.at[0] - x;
            const dz = ord.at[1] - z;
            const apart = ord.kind.radius() + r + 0.4;
            if (dx * dx + dz * dz < apart * apart) return false;
        }
        return true;
    }

    /// Gives builder `i` an order (it goes there, and builds).
    pub fn orderBuild(w: *World, i: usize, o: Order) void {
        const t = &w.things[i];
        if (!t.kind.builds()) return;
        t.order = o;
        t.site = null;
        w.send(i, o.at);
    }

    /// Sends builder `i` to go on building `site` (one of its player's,
    /// not yet built).
    pub fn orderResume(w: *World, i: usize, site: usize) void {
        const t = &w.things[i];
        const b = w.things[site];
        if (!t.kind.builds() or b.built >= 1 or b.team != t.team) return;
        t.order = .{ .kind = b.kind, .at = .{ b.pos[0], b.pos[2] }, .yaw = b.yaw };
        t.site = site;
        w.send(i, t.order.?.at);
    }

    /// A builder's work: going to where it is to build; there, starting
    /// the building (where it was asked, if it still can be), then
    /// building it, paid for bit by bit as it goes.
    fn construct(w: *World, t: *Thing, dt: f32) void {
        const o = t.order orelse return;
        const dx = o.at[0] - t.pos[0];
        const dz = o.at[1] - t.pos[2];
        const reach = o.kind.radius() + t.kind.radius() + 1.0;
        const there = dx * dx + dz * dz <= reach * reach;
        if (!there) {
            // On its way (sent again, if it stopped).
            if (t.goal == null and t.replans < 3) {
                t.goal = o.at;
                t.replans += 1;
                w.route(t);
            }
            return;
        }
        t.goal = null;
        if (t.site) |s| {
            const b = &w.things[s];
            if (b.built >= 1) {
                t.order = null;
                t.site = null;
                return;
            }
            t.phase += dt * 4;
            const c = o.kind.cost();
            const part = dt / c.seconds;
            const r = &w.resources[t.team];
            if (r.metal < c.metal * part) return;
            r.metal -= c.metal * part;
            b.built = @min(1, b.built + part);
            if (b.built >= 1) {
                t.order = null;
                t.site = null;
            }
            return;
        }
        // Started, if it still can be (or given up).
        t.order = null;
        if (!w.canPlace(o.kind, o.at[0], o.at[1])) return;
        t.order = o;
        const i = w.add(.{ .kind = o.kind, .team = t.team, .pos = .{ o.at[0], 0, o.at[1] }, .yaw = o.yaw, .built = 0 }) orelse {
            t.order = null;
            return;
        };
        const fwd = [2]f32{ @sin(o.yaw), -@cos(o.yaw) };
        const out = o.kind.radius() + 4;
        w.things[i].rally = .{ o.at[0] + fwd[0] * out, o.at[1] + fwd[1] * out };
        t.site = i;
        // Facing it.
        t.yaw = std.math.atan2(dx, -dz);
    }

    /// A factory makes its first in line, if its player can pay for it as
    /// it goes; done, it comes out of the door and goes to the rally point.
    fn make(w: *World, f: *Thing, dt: f32) void {
        f.phase += dt;
        const k = f.making() orelse return;
        const c = k.cost();
        const r = &w.resources[f.team];
        // Paid for bit by bit, as it is made.
        const part = dt / c.seconds;
        if (!f.powered or r.metal < c.metal * part) return;
        r.metal -= c.metal * part;
        f.progress += part;
        if (f.progress < 1) return;
        f.progress = 0;
        std.mem.copyForwards(Kind, f.queue[0 .. f.queued - 1], f.queue[1..f.queued]);
        f.queued -= 1;
        const fwd = V3{ @sin(f.yaw), 0, -@cos(f.yaw) };
        // Out of the door; a drone factory's, up off its pad.
        const door = if (f.kind == .air_factory) f.pos else f.pos + fwd * math.splat(f.kind.radius() + 0.8);
        if (w.add(.{ .kind = k, .team = f.team, .pos = door, .yaw = f.yaw })) |i| {
            // (`f` may have moved: the list is not resized, so it has not.)
            w.send(i, f.rally);
        }
    }
};

/// Where building `i` comes, this while (`slot`), in the order buildings
/// get energy when there is not enough: at random, but the same all
/// while.
fn shuffleKey(slot: u32, i: u32, k: Kind) u32 {
    var h = slot *% 0x9e3779b9 ^ i *% 0x85ebca6b ^ @as(u32, @intFromEnum(k)) *% 0xc2b2ae35;
    h ^= h >> 16;
    h *%= 0x7feb352d;
    h ^= h >> 15;
    return h;
}

pub fn wrap(a: f32) f32 {
    return std.math.atan2(@sin(a), @cos(a));
}

pub fn angleDiff(target: f32, current: f32) f32 {
    return wrap(target - current);
}

const testing = std.testing;

fn testWorld() !struct { map: *Map, world: *World } {
    const m = try Map.create(testing.allocator, 1);
    const w = try testing.allocator.create(World);
    w.* = .{ .map = m };
    return .{ .map = m, .world = w };
}

test "a base: its buildings, and units that go where they are sent" {
    const tw = try testWorld();
    defer tw.map.destroy(testing.allocator);
    defer testing.allocator.destroy(tw.world);
    const w = tw.world;
    w.addBase(0);
    var units: [8]usize = undefined;
    var n: usize = 0;
    for (w.all(), 0..) |t, i| if (!t.kind.isBuilding()) {
        units[n] = i;
        n += 1;
    };
    try testing.expectEqual(@as(usize, 4), n);
    const b = map_mod.bases[0];
    w.moveTo(units[0..n], b[0] + 8, b[1] + 6);
    for (0..400) |_| w.step(0.05);
    for (units[0..n]) |i| {
        const t = w.things[i];
        try testing.expect(t.goal == null);
        const d = @sqrt((t.pos[0] - b[0] - 8) * (t.pos[0] - b[0] - 8) + (t.pos[2] - b[1] - 6) * (t.pos[2] - b[1] - 6));
        try testing.expect(d < 3);
        // On the ground, or flying over it.
        if (t.kind.flies()) try testing.expect(t.pos[1] > w.map.surfaceAt(t.pos[0], t.pos[2]) + 2) else try testing.expectApproxEqAbs(w.map.heightAt(t.pos[0], t.pos[2]), t.pos[1], 0.05);
    }
}

test "a factory makes what is queued, paying as it goes, and sends it out" {
    const tw = try testWorld();
    defer tw.map.destroy(testing.allocator);
    defer testing.allocator.destroy(tw.world);
    const w = tw.world;
    w.addBase(0);
    const f = for (w.all(), 0..) |t, i| {
        if (t.kind == .factory) break i;
    } else unreachable;
    const before = w.count;
    try testing.expect(w.enqueue(f, .walker));
    try testing.expect(w.enqueue(f, .tank));
    try testing.expect(w.enqueue(f, .tank));
    try testing.expectEqual(@as(u32, 2), w.things[f].queuedOf(.tank));
    w.dequeue(f, .tank);
    try testing.expectEqual(@as(u32, 1), w.things[f].queuedOf(.tank));
    const metal = w.resources[0].metal;
    // The walker, then the tank (4 and 7 seconds).
    for (0..250) |_| w.step(0.05);
    try testing.expectEqual(before + 2, w.count);
    try testing.expectEqual(@as(u8, 0), w.things[f].queued);
    try testing.expectEqual(Kind.walker, w.things[before].kind);
    try testing.expectEqual(Kind.tank, w.things[before + 1].kind);
    // Paid for (less what the base made meanwhile).
    try testing.expect(w.resources[0].metal < metal + 12.5 * (4 + 1) - 100);
    // On their way to the rally point.
    try testing.expect(w.things[before].goal != null or @abs(w.things[before].pos[0] - w.things[f].rally[0]) < 2);
}

/// A tree on the map, on open enough ground to drive up to.
fn someTree(m: *const Map) map_mod.Tree {
    var r: usize = map_mod.margin_rows + 20;
    while (r < map_mod.rows - map_mod.margin_rows) : (r += 1) {
        for (map_mod.margin_cols + 20..map_mod.cols - map_mod.margin_cols) |c| {
            const t = m.treeAt(c, r) orelse continue;
            if (map_mod.inside(t.at[0], t.at[2]) > 20 and m.passable(t.at[0], t.at[2])) return t;
        }
    }
    unreachable;
}

test "trees: in the way of tanks and builders, not of walkers and fliers" {
    const tw = try testWorld();
    defer tw.map.destroy(testing.allocator);
    defer testing.allocator.destroy(tw.world);
    const w = tw.world;
    const tree = someTree(w.map);
    for ([_]Kind{ .tank, .builder }) |k| try testing.expect(!w.canBe(k, tree.at[0], tree.at[2]));
    for ([_]Kind{ .walker, .drone, .air_builder }) |k| try testing.expect(w.canBe(k, tree.at[0], tree.at[2]));
    // Sent through it: those it is in the way of never get to it.
    for ([_]Kind{ .tank, .builder, .walker, .air_builder }) |k| {
        w.count = 0;
        const i = w.add(.{ .kind = k, .team = 0, .pos = .{ tree.at[0] - 6, 0, tree.at[2] } }).?;
        w.things[i].goal = .{ tree.at[0], tree.at[2] };
        var nearest: f32 = 100;
        for (0..60 * 10) |_| {
            w.step(1.0 / 60.0);
            const t = w.things[i];
            nearest = @min(nearest, @abs(t.pos[0] - tree.at[0]) + @abs(t.pos[2] - tree.at[2]));
        }
        if (k.blockedByTrees()) try testing.expect(nearest > 0.5) else try testing.expect(nearest < 0.3);
    }
}

test "builders: sent to build, they go there and build it, paying as they go; then it works" {
    const tw = try testWorld();
    defer tw.map.destroy(testing.allocator);
    defer testing.allocator.destroy(tw.world);
    const w = tw.world;
    // (No base: nothing else earns metal.)
    const b = map_mod.bases[0];
    const at = [2]f32{ b[0] + 6, b[1] + 6 };
    for ([_]Kind{ .builder, .air_builder }, 0..) |k, n| {
        const site = [2]f32{ at[0] + @as(f32, @floatFromInt(n)) * 5, at[1] - @as(f32, @floatFromInt(n)) * 5 };
        try testing.expect(w.canPlace(.power, site[0], site[1]));
        const i = w.add(.{ .kind = k, .team = 0, .pos = .{ b[0] + 4, 0, b[1] - 4 } }).?;
        w.orderBuild(i, .{ .kind = .power, .at = site });
        // Where it is to go, nothing else is placed.
        try testing.expect(!w.canPlace(.power, site[0] + 0.5, site[1]));
        const before = w.resources[0];
        var site_i: ?usize = null;
        var t: f32 = 0;
        while (t < 40) : (t += 1.0 / 30.0) {
            w.step(1.0 / 30.0);
            if (w.things[i].site) |s| site_i = s;
            if (site_i != null and w.things[i].order == null) break;
        }
        const s = site_i.?;
        try testing.expectEqual(Kind.power, w.things[s].kind);
        try testing.expectEqual(@as(f32, 1), w.things[s].built);
        try testing.expect(w.things[i].order == null);
        // It cost what a power plant costs.
        try testing.expectApproxEqAbs(before.metal - Kind.power.cost().metal, w.resources[0].metal, 0.5);
    }
    // Not on a building, nor in the water, nor off the map.
    _ = w.add(.{ .kind = .factory, .team = 0, .pos = .{ b[0], 0, b[1] } }).?;
    try testing.expect(!w.canPlace(.tower, b[0] + 1, b[1]));
    try testing.expect(!w.canPlace(.tower, -10, -10));
}

test "a building half built: does nothing until it is finished" {
    const tw = try testWorld();
    defer tw.map.destroy(testing.allocator);
    defer testing.allocator.destroy(tw.world);
    const w = tw.world;
    const b = map_mod.bases[0];
    _ = w.add(.{ .kind = .mine, .team = 0, .pos = .{ b[0], 0, b[1] }, .built = 0.5 }).?;
    const before = w.resources[0];
    w.step(1);
    try testing.expectEqual(before.metal, w.resources[0].metal);
    try testing.expectEqual(before.energy, w.resources[0].energy);
}

test "sent past a forest, a tank finds its way round it and gets there" {
    const tw = try testWorld();
    defer tw.map.destroy(testing.allocator);
    defer testing.allocator.destroy(tw.world);
    const w = tw.world;
    const n = w.map.nav;
    // A thick forest, with open ground either side.
    var from: [2]f32 = undefined;
    var to: [2]f32 = undefined;
    var found = false;
    var r: usize = map_mod.margin_rows + 60;
    search: while (r < map_mod.rows - map_mod.margin_rows - 60) : (r += 3) {
        for (map_mod.margin_cols + 60..map_mod.cols - map_mod.margin_cols - 60) |c| {
            const t = w.map.treeAt(c, r) orelse continue;
            if (map_mod.forestOf(1, t.at[0], t.at[2]) < 0.9) continue;
            from = .{ t.at[0] - 20, t.at[2] };
            to = .{ t.at[0] + 20, t.at[2] };
            if (!n.openAt(.wheels, from[0], from[1]) or !n.openAt(.wheels, to[0], to[1])) continue;
            found = true;
            break :search;
        }
    }
    try testing.expect(found);
    for ([_]Kind{ .tank, .walker }) |k| {
        w.count = 0;
        const i = w.add(.{ .kind = k, .team = 0, .pos = .{ from[0], 0, from[1] } }).?;
        w.moveTo(&.{i}, to[0], to[1]);
        var t: f32 = 0;
        while (t < 120 and w.things[i].goal != null) : (t += 1.0 / 30.0) w.step(1.0 / 30.0);
        const p = w.things[i].pos;
        try testing.expect(@abs(p[0] - to[0]) < 1 and @abs(p[2] - to[1]) < 1);
    }
}

test "repairing: a damaged building heals, paying metal; it stops when whole, and waits for metal" {
    const tw = try testWorld();
    defer tw.map.destroy(testing.allocator);
    defer testing.allocator.destroy(tw.world);
    const w = tw.world;
    const b = map_mod.bases[0];
    const f = w.add(.{ .kind = .tower, .team = 0, .pos = .{ b[0], 0, b[1] } }).?;
    const most = combat.maxHealth(.tower);
    w.things[f].health = most / 2;
    w.resources[0] = .{ .metal = 1000 };
    w.toggleRepair(&.{f}, 0);
    try testing.expect(w.things[f].repairing);
    for (0..60 * 5) |_| w.step(1.0 / 60.0);
    // Healed some, for metal.
    const healed = w.things[f].health - most / 2;
    try testing.expect(healed > 0);
    try testing.expectApproxEqAbs(1000 - healed * repair_metal, w.resources[0].metal, 1);
    // Pressed again: stops.
    w.toggleRepair(&.{f}, 0);
    try testing.expect(!w.things[f].repairing);
    // No metal: waits, healing nothing.
    w.toggleRepair(&.{f}, 0);
    w.resources[0].metal = 0;
    const was = w.things[f].health;
    for (0..60) |_| w.step(1.0 / 60.0);
    try testing.expectEqual(was, w.things[f].health);
    // Metal again: whole, then stops.
    w.resources[0].metal = 1000;
    for (0..60 * 30) |_| w.step(1.0 / 60.0);
    try testing.expectEqual(most, w.things[f].health);
    try testing.expect(!w.things[f].repairing);
}

test "energy: buildings use it as they run, power plants make it; batteries store more" {
    const tw = try testWorld();
    defer tw.map.destroy(testing.allocator);
    defer testing.allocator.destroy(tw.world);
    const w = tw.world;
    const b = map_mod.bases[0];
    _ = w.add(.{ .kind = .power, .team = 0, .pos = .{ b[0], 0, b[1] } }).?;
    _ = w.add(.{ .kind = .factory, .team = 0, .pos = .{ b[0] + 6, 0, b[1] } }).?;
    w.resources[0].energy = 100;
    w.step(1);
    // Made 12, used 2.
    try testing.expectApproxEqAbs(@as(f32, 10), w.resources[0].net, 1e-3);
    try testing.expectApproxEqAbs(@as(f32, 110), w.resources[0].energy, 0.01);
    // As much as can be stored, no more; a battery stores more.
    for (0..100) |_| w.step(1);
    try testing.expectEqual(base_storage, w.resources[0].energy);
    _ = w.add(.{ .kind = .battery, .team = 0, .pos = .{ b[0] - 6, 0, b[1] } }).?;
    for (0..100) |_| w.step(1);
    try testing.expectEqual(base_storage + battery_storage, w.resources[0].energy);
    try testing.expectEqual(base_storage + battery_storage, w.resources[0].storage);
    // Making a unit costs metal, not energy.
    const metal = w.resources[0].metal;
    for (w.all(), 0..) |t, i| if (t.kind == .factory) {
        _ = w.enqueue(i, .walker);
    };
    const energy = w.resources[0].energy;
    for (0..60 * 5) |_| w.step(1.0 / 60.0);
    try testing.expect(w.resources[0].metal < metal + 5 * 1 - Kind.walker.cost().metal + 1);
    try testing.expectEqual(energy, w.resources[0].energy);
}

test "short of energy: just enough buildings shut down, which changing; all run once some is stored" {
    const tw = try testWorld();
    defer tw.map.destroy(testing.allocator);
    defer testing.allocator.destroy(tw.world);
    const w = tw.world;
    const c = map_mod.centre;
    _ = w.add(.{ .kind = .power, .team = 0, .pos = .{ c[0], 0, c[1] } }).?;
    // Ten mines: 15 used, 12 made.
    for (0..10) |k| _ = w.add(.{ .kind = .mine, .team = 0, .pos = .{ c[0] - 20 + @as(f32, @floatFromInt(k)) * 4, 0, c[1] + 8 } }).?;
    w.resources[0].energy = 10;
    for (0..10) |_| w.step(1);
    const r = w.resources[0];
    try testing.expect(r.short);
    // Eight run (12), two do not.
    try testing.expectEqual(@as(u16, 2), r.shut_down);
    try testing.expect(r.net >= 0);
    var off_before: [2]usize = undefined;
    var n: usize = 0;
    for (w.all(), 0..) |t, i| if (!t.powered) {
        off_before[n] = i;
        n += 1;
    };
    // Some time on: others shut down instead (at least once).
    var changed = false;
    for (0..8) |_| {
        for (0..60 * 4) |_| w.step(1.0 / 60.0);
        for (w.all(), 0..) |t, i| if (!t.powered and i != off_before[0] and i != off_before[1]) {
            changed = true;
        };
    }
    try testing.expect(changed);
    // A battery's worth stored (another power plant): all run.
    _ = w.add(.{ .kind = .power, .team = 0, .pos = .{ c[0] + 10, 0, c[1] - 8 } }).?;
    for (0..60 * 10) |_| w.step(1.0 / 60.0);
    try testing.expect(!w.resources[0].short);
    for (w.all()) |t| try testing.expect(t.powered);
}

test "armouring a building: paid for over a while; then it is hurt half as much" {
    const tw = try testWorld();
    defer tw.map.destroy(testing.allocator);
    defer testing.allocator.destroy(tw.world);
    const w = tw.world;
    const b = map_mod.bases[0];
    const i = w.add(.{ .kind = .mine, .team = 0, .pos = .{ b[0], 0, b[1] } }).?;
    w.resources[0] = .{ .metal = 1000 };
    w.toggleArmour(i, 0);
    try testing.expect(w.things[i].armouring);
    for (0..@as(usize, @intFromFloat(armour_seconds)) * 10 + 5) |_| w.step(0.1);
    try testing.expect(w.things[i].armoured and !w.things[i].armouring);
    // (The mine dug some metal meanwhile: 4 a second.)
    try testing.expectApproxEqAbs(1000 - armourCost(.mine) + 4 * (armour_seconds + 0.5), w.resources[0].metal, 4);
    // Hurt by a shell's burst: half.
    const plain = w.add(.{ .kind = .mine, .team = 0, .pos = .{ b[0] + 8, 0, b[1] } }).?;
    for ([_]usize{ i, plain }) |k| w.addShot(.{ .from = w.things[k].pos + V3{ 0, 5, 0 }, .to = w.things[k].pos, .rate = 100, .shell = true, .team = 1, .damage = .{ 0, 0, 40, 0 } });
    w.step(0.05);
    const most = combat.maxHealth(.mine);
    try testing.expectApproxEqAbs(most - w.things[plain].health, 2 * (most - w.things[i].health), 0.01);
}

test "a drone factory makes what flies (and not what goes on the ground)" {
    const tw = try testWorld();
    defer tw.map.destroy(testing.allocator);
    defer testing.allocator.destroy(tw.world);
    const w = tw.world;
    const b = map_mod.bases[0];
    const f = w.add(.{ .kind = .air_factory, .team = 0, .pos = .{ b[0], 0, b[1] }, .rally = .{ b[0] + 6, b[1] } }).?;
    _ = w.add(.{ .kind = .power, .team = 0, .pos = .{ b[0] - 8, 0, b[1] } }).?;
    try testing.expect(!w.enqueue(f, .tank));
    try testing.expect(w.enqueue(f, .drone));
    for (0..80) |_| w.step(0.1);
    var drones: usize = 0;
    for (w.all()) |t| if (t.kind == .drone) {
        drones += 1;
    };
    try testing.expectEqual(@as(usize, 1), drones);
}

test "sent together, units go as fast as the slowest of them; alone, as fast as each can" {
    const tw = try testWorld();
    defer tw.map.destroy(testing.allocator);
    defer testing.allocator.destroy(tw.world);
    const w = tw.world;
    const c = map_mod.centre;
    const walker = w.add(.{ .kind = .walker, .team = 0, .pos = .{ c[0], 0, c[1] } }).?;
    const tank = w.add(.{ .kind = .tank, .team = 0, .pos = .{ c[0], 0, c[1] + 3 } }).?;
    w.moveTo(&.{ walker, tank }, c[0] + 30, c[1]);
    var fastest: f32 = 0;
    for (0..60 * 4) |_| {
        w.step(1.0 / 60.0);
        fastest = @max(fastest, w.things[walker].moving);
    }
    try testing.expect(fastest <= Kind.tank.speed() + 1e-3);
    // Alone: as fast as a walker goes.
    w.moveTo(&.{walker}, c[0] - 30, c[1]);
    fastest = 0;
    for (0..60 * 4) |_| {
        w.step(1.0 / 60.0);
        fastest = @max(fastest, w.things[walker].moving);
    }
    try testing.expect(fastest > Kind.tank.speed() + 0.5);
}
