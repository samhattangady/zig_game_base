const std = @import("std");
const inputs = @import("inputs.zig");
const MouseState = inputs.MouseState;
const serializer = @import("serializer.zig");

pub const Orientation = enum {
    n,
    e,
    s,
    w,

    pub fn opposite(self: *const Orientation) Orientation {
        return switch (self.*) {
            .n => .s,
            .e => .w,
            .s => .n,
            .w => .e,
        };
    }
    pub fn next(self: *const Orientation) Orientation {
        return switch (self.*) {
            .n => .e,
            .e => .s,
            .s => .w,
            .w => .n,
        };
    }
    pub fn nextStep(self: *const Orientation, count: usize) Orientation {
        var start = self.*;
        for (0..count) |_| start = start.next();
        return start;
    }
    pub fn toIndex(self: *const Orientation) usize {
        return @intFromEnum(self.*);
    }
    pub fn fromIndex(index: usize) Orientation {
        return @enumFromInt(index);
    }
    pub fn toDir(self: *const Orientation) Vec2i {
        return switch (self.*) {
            .n => .{ .x = 0, .y = 1 },
            .e => .{ .x = 1, .y = 0 },
            .s => .{ .x = 0, .y = -1 },
            .w => .{ .x = -1, .y = 0 },
        };
    }
    pub fn getRelative(source: Vec2i, address: Vec2i) Orientation {
        assert(source.distancei(address) == 1);
        if (source.x > address.x) return .w;
        if (source.x < address.x) return .e;
        if (source.y > address.y) return .s;
        if (source.y < address.y) return .n;
        unreachable;
    }

    // standard is south
    pub fn toDegrees(self: *const Orientation) f32 {
        return switch (self.*) {
            .n => 0,
            .e => 90,
            .s => 180,
            .w => 270,
        };
    }

    pub fn vec(self: *const Orientation) Vec2 {
        return switch (self.*) {
            .n => .{ .x = 0, .y = 1 },
            .e => .{ .x = 1, .y = 0 },
            .s => .{ .x = 0, .y = -1 },
            .w => .{ .x = -1, .y = 0 },
        };
    }
};

pub const Vec2 = struct {
    const Self = @This();
    x: f32 = 0,
    y: f32 = 0,

    pub fn fromInts(x: anytype, y: anytype) Vec2 {
        return Vec2{
            .x = @as(f32, @floatFromInt(x)),
            .y = @as(f32, @floatFromInt(y)),
        };
    }

    pub fn distance(v1: *const Self, v2: Self) f32 {
        return @sqrt(((v2.x - v1.x) * (v2.x - v1.x)) + ((v2.y - v1.y) * (v2.y - v1.y)));
    }

    pub fn distanceSqr(v1: *const Self, v2: Self) f32 {
        return ((v2.x - v1.x) * (v2.x - v1.x)) + ((v2.y - v1.y) * (v2.y - v1.y));
    }

    pub fn length(v: *const Self) f32 {
        return @sqrt((v.x * v.x) + (v.y * v.y));
    }

    pub fn lengthSqr(v: *const Self) f32 {
        return (v.x * v.x) + (v.y * v.y);
    }

    pub fn normalize(v: *const Self) Self {
        const len = v.length();
        if (len == 0) return v.scale(0);
        return v.scale(1 / len);
    }

    pub fn xVec(v: *const Self) Self {
        return .{ .x = v.x };
    }

    pub fn yVec(v: *const Self) Self {
        return .{ .y = v.y };
    }

    pub fn toVec3(v: *const Self) Vec3 {
        return .{ .x = v.x, .y = v.y };
    }

    pub fn add(v1: *const Self, v2: Vec2) Self {
        return .{ .x = v1.x + v2.x, .y = v1.y + v2.y };
    }

    pub fn subtract(v1: *const Self, v2: Self) Self {
        return .{ .x = v1.x - v2.x, .y = v1.y - v2.y };
    }

    pub fn scale(v: *const Self, t: f32) Self {
        return .{ .x = v.x * t, .y = v.y * t };
    }

    pub fn yScale(v: *const Self, t: f32) Self {
        return .{ .x = v.x, .y = v.y * t };
    }

    pub fn scaleVec2(v: *const Self, v2: Vec2) Self {
        return .{ .x = v.x * v2.x, .y = v.y * v2.y };
    }

    /// Strict equals check. Does not account for float imprecision
    pub fn equal(v1: *const Self, v2: Self) bool {
        return v1.x == v2.x and v1.y == v2.y;
    }

    pub fn zero(v: *const Self) bool {
        return v.x == 0 and v.y == 0;
    }

    pub fn rotate(v: *const Self, rad: f32) Self {
        const cosa = @cos(rad);
        const sina = @sin(rad);
        return .{
            .x = (cosa * v.x) - (sina * v.y),
            .y = (sina * v.x) + (cosa * v.y),
        };
    }

    pub fn roundI(v: *const Self) Vec2i {
        return .{
            .x = @as(i32, @intFromFloat(@round(v.x))),
            .y = @as(i32, @intFromFloat(@round(v.y))),
        };
    }

    pub fn floorI(v: *const Self) Vec2i {
        return .{
            .x = @as(i32, @intFromFloat(@floor(v.x))),
            .y = @as(i32, @intFromFloat(@floor(v.y))),
        };
    }

    pub fn round(v: *const Self) Vec2 {
        return .{
            .x = @round(v.x),
            .y = @round(v.y),
        };
    }

    pub fn dot(v1: *const Self, v2: Self) f32 {
        return (v1.x * v2.x) + (v1.y * v2.y);
    }

    /// to get the sin of the angle between the two vectors.
    pub fn crossZ(v1: *const Self, v2: Self) f32 {
        return (v1.x * v2.y) - (v1.y * v2.x);
    }

    pub fn perpendicular(v: *const Self) Self {
        return .{ .x = v.y, .y = -v.x };
    }

    pub fn ease(v1: *const Vec2, v2: Vec2, t: f32) Vec2 {
        return .{
            .x = easeinoutf(v1.x, v2.x, t),
            .y = easeinoutf(v1.y, v2.y, t),
        };
    }

    /// takes a Vec2 v that is currently aligned to origin. It then rotates it
    /// such that it now has the same relationship with target as it originally
    /// had with origin.
    /// origin and target need to be normalized.
    /// For example, if we have offsets of a polygon, and we want to rotate it,
    /// then the origin will be x axis, and the target will be the rotation.
    pub fn alignTo(v: *const Self, origin: Vec2, target: Vec2) Vec2 {
        // get the angle between origin and target
        const cosa = origin.dot(target);
        const sina = origin.crossZ(target);
        return .{
            .x = (cosa * v.x) - (sina * v.y),
            .y = (sina * v.x) + (cosa * v.y),
        };
    }

    pub fn lerp(v0: *const Vec2, v1: Vec2, t: f32) Vec2 {
        return .{
            .x = lerpf(v0.x, v1.x, t),
            .y = lerpf(v0.y, v1.y, t),
        };
    }

    pub fn toExtern(self: *const Vec2) Vec2Extern {
        return .{ .x = self.x, .y = self.y };
    }
};

pub const Vec2Extern = extern struct {
    x: f32 = 0,
    y: f32 = 0,
};

pub const Vec2i = struct {
    const Self = @This();
    x: i32 = 0,
    y: i32 = 0,

    pub fn toVec2(v: *const Self) Vec2 {
        return .{
            .x = @as(f32, @floatFromInt(v.x)),
            .y = @as(f32, @floatFromInt(v.y)),
        };
    }

    pub fn add(v1: *const Self, v2: Self) Self {
        return .{ .x = v1.x + v2.x, .y = v1.y + v2.y };
    }

    pub fn length(v: *const Self) f32 {
        return v.toVec2().length();
    }

    pub fn lengthSqr(v: *const Self) f32 {
        return v.toVec2().lengthSqr();
    }

    pub fn equal(v: *const Self, v1: Self) bool {
        return v.x == v1.x and v.y == v1.y;
    }

    pub fn scale(v: *const Self, t: i32) Self {
        return .{ .x = v.x * t, .y = v.y * t };
    }

    // integer division. No guarantees
    pub fn divide(v: *const Self, t: i32) Self {
        return .{ .x = v.x / t, .y = v.y / t };
    }

    pub fn distance(v: *const Self, v1: Vec2i) f32 {
        return v.toVec2().distance(v1.toVec2());
    }

    pub fn distancei(v: *const Self, v1: Self) usize {
        const absx = @abs(v.x - v1.x);
        const absy = @abs(v.y - v1.y);
        return absx + absy;
    }

    // TODO (24 Jul 2024 sam): Test this to see if its correct. Its correct for 1 cell away
    // Meant to calculate "ranges" where diagonal is also one step.
    pub fn diagDistance(v: *const Self, v1: Self) usize {
        const absx = @abs(v.x - v1.x);
        const absy = @abs(v.y - v1.y);
        return @max(absx, absy);
    }

    pub fn numSteps(v: *const Self) usize {
        const absx = @abs(v.x);
        const absy = @abs(v.y);
        return absx + absy;
    }
    pub fn maxMag(v: *const Self) usize {
        const absx = @abs(v.x);
        const absy = @abs(v.y);
        return @max(absx, absy);
    }

    pub fn orthoTarget(v: *const Vec2i, target: Vec2i) Vec2i {
        var ot = target;
        const absx = @abs(v.x - target.x);
        const absy = @abs(v.y - target.y);
        if (absx >= absy) ot.y = v.y else ot.x = v.x;
        return ot;
    }

    pub fn orthoFixed(v: *const Vec2i, is_horizontal: bool) i32 {
        if (is_horizontal) return v.y;
        return v.x;
    }
    pub fn orthoVariable(v: *const Vec2i, is_horizontal: bool) i32 {
        if (is_horizontal) return v.x;
        return v.y;
    }
    pub fn orthoFixedV(v: *const Vec2i, is_horizontal: bool) Vec2i {
        if (is_horizontal) return .{ .y = v.y };
        return .{ .x = v.x };
    }
    pub fn orthoVariableV(v: *const Vec2i, is_horizontal: bool) Vec2i {
        if (is_horizontal) return .{ .x = v.x };
        return .{ .y = v.y };
    }
    pub fn orthoConstruct(fixed: i32, vrb: i32, is_horizontal: bool) Vec2i {
        if (is_horizontal) return .{ .x = vrb, .y = fixed };
        return .{ .x = fixed, .y = vrb };
    }

    // assumes that cells are ortho
    pub fn getChangeTo(self: *const Vec2i, other: Vec2i) Vec2i {
        if (self.x == other.x) {
            if (self.y > other.y) return .{ .y = -1 };
            return .{ .y = 1 };
        }
        if (self.x > other.x) return .{ .x = -1 };
        return .{ .x = 1 };
    }
};

pub const Vec3 = struct {
    const Self = @This();
    x: f32 = 0,
    y: f32 = 0,
    z: f32 = 0,

    pub fn toVec2(v: *const Self) Vec2 {
        return .{ .x = v.x, .y = v.y };
    }
};

pub const Vec4 = struct {
    const Self = @This();
    x: f32 = 0,
    y: f32 = 0,
    z: f32 = 0,
    w: f32 = 0,

    /// Converts hex rgba to Vec4. Expects in format "#rrggbbaa"
    pub fn fromHexRgba(hex: []const u8) Vec4 {
        std.debug.assert(hex[0] == '#'); // hex_rgba needs to be in "#rrggbbaa" format
        std.debug.assert(hex.len == 9); // hex_rgba needs to be in "#rrggbbaa" format
        var self = Vec4{};
        self.x = @as(f32, @floatFromInt(std.fmt.parseInt(u8, hex[1..3], 16) catch unreachable)) / 255.0;
        self.y = @as(f32, @floatFromInt(std.fmt.parseInt(u8, hex[3..5], 16) catch unreachable)) / 255.0;
        self.z = @as(f32, @floatFromInt(std.fmt.parseInt(u8, hex[5..7], 16) catch unreachable)) / 255.0;
        self.w = @as(f32, @floatFromInt(std.fmt.parseInt(u8, hex[7..9], 16) catch unreachable)) / 255.0;
        return self;
    }

    /// Converts hex rgb to Vec4. Expects in format "#rrggbb"
    pub fn fromHexRgb(hex: []const u8) Vec4 {
        std.debug.assert(hex[0] == '#'); // hex_rgba needs to be in "#rrggbb" format
        std.debug.assert(hex.len == 7); // hex_rgba needs to be in "#rrggbb" format
        var self = Vec4{};
        self.x = @as(f32, @floatFromInt(std.fmt.parseInt(u8, hex[1..3], 16) catch unreachable)) / 255.0;
        self.y = @as(f32, @floatFromInt(std.fmt.parseInt(u8, hex[3..5], 16) catch unreachable)) / 255.0;
        self.z = @as(f32, @floatFromInt(std.fmt.parseInt(u8, hex[5..7], 16) catch unreachable)) / 255.0;
        self.w = 1.0;
        return self;
    }

    pub fn toHexRgba(self: *const Self, buffer: []u8) void {
        std.debug.assert(buffer.len >= 10);
        buffer[0] = '#';
        buffer[9] = 0;
        _ = std.fmt.bufPrint(buffer[1..9], "{x:0>2}", .{@as(u8, @intFromFloat(self.x * 255))}) catch unreachable;
        _ = std.fmt.bufPrint(buffer[3..5], "{x:0>2}", .{@as(u8, @intFromFloat(self.y * 255))}) catch unreachable;
        _ = std.fmt.bufPrint(buffer[5..7], "{x:0>2}", .{@as(u8, @intFromFloat(self.z * 255))}) catch unreachable;
        _ = std.fmt.bufPrint(buffer[7..9], "{x:0>2}", .{@as(u8, @intFromFloat(self.w * 255))}) catch unreachable;
    }

    pub fn alpha(self: *const Vec4, a: f32) Vec4 {
        var col = self.*;
        col.w = a;
        return col;
    }

    // TODO (26 Jul 2023 sam): Do a hsv based lerp also
    pub fn lerp(self: *const Vec4, other: Vec4, f: f32) Vec4 {
        return .{
            .x = lerpf(self.x, other.x, f),
            .y = lerpf(self.y, other.y, f),
            .z = lerpf(self.z, other.z, f),
            .w = lerpf(self.w, other.w, f),
        };
    }
};

pub const Movement = struct {
    const Self = @This();
    from: Vec2,
    to: Vec2,
    start: u64,
    duration: u64,
    mode: enum {
        linear,
        eased,
    } = .linear,

    pub fn getPos(self: *const Self, ticks: u64) Vec2 {
        if (ticks < self.start) return self.from;
        if (ticks > (self.start + self.duration)) return self.to;
        const t: f32 = @as(f32, @floatFromInt(ticks - self.start)) / @as(f32, @floatFromInt(self.duration));
        switch (self.mode) {
            .linear => return self.from.lerp(self.to, t),
            .eased => return self.from.ease(self.to, t),
        }
    }
};

pub const Rect = struct {
    const Self = @This();
    position: Vec2,
    size: Vec2,

    pub fn contains(self: *const Self, pos: Vec2) bool {
        const minx = @min(self.position.x, self.position.x + self.size.x);
        const maxx = @max(self.position.x, self.position.x + self.size.x);
        const miny = @min(self.position.y, self.position.y + self.size.y);
        const maxy = @max(self.position.y, self.position.y + self.size.y);
        return (pos.x > minx) and
            (pos.x < maxx) and
            (pos.y > miny) and
            (pos.y < maxy);
    }

    pub fn overlaps(self: *const Rect, other: Rect) bool {
        const sx0 = self.position.x;
        const sx1 = self.position.x + self.size.x;
        const sy0 = self.position.y;
        const sy1 = self.position.y + self.size.y;
        const ox0 = other.position.x;
        const ox1 = other.position.x + other.size.x;
        const oy0 = other.position.y;
        const oy1 = other.position.y + other.size.y;
        return rangeOverlap(sx0, sx1, ox0, ox1) and rangeOverlap(sy0, sy1, oy0, oy1);
    }

    pub fn center(self: *const Self) Vec2 {
        return self.position.add(self.size.scale(0.5));
    }

    // TODO (28 Jul 2024 sam): Break this up into the intesection check for
    // collision and prediction
    pub fn intersectsLine(self: *const Self, p0: Vec2, p1: Vec2) ?Vec2 {
        const p0_in = self.contains(p0);
        const p1_in = self.contains(p1);
        // if (!p0_in and !p1_in) return null;
        if (p0_in and p1_in) return p0;
        const verts = [_]Vec2{
            self.position,
            self.position.add(self.size.xVec()),
            self.position.add(self.size),
            self.position.add(self.size.yVec()),
        };
        for (verts, 0..) |v0, i| {
            const v1 = if (i == verts.len - 1) verts[0] else verts[i + 1];
            // TODO (28 Jul 2024 sam): Return the closest point of contact
            if (lineSegmentsIntersect(p0, p1, v0, v1)) |point| return point;
        }
        // should be unreachable.
        return null;
    }
};

pub const Button = struct {
    const Self = @This();
    rect: Rect,
    value: u8,
    text: []const u8,
    text2: []const u8 = "",
    enabled: bool = true,
    // mouse is hovering over button
    hovered: bool = false,
    // the frame that mouse button was down in bounds
    clicked: bool = false,
    // the frame what mouse button was released in bounds (and was also down in bounds)
    released: bool = false,
    // when mouse was down in bounds and is still down.
    triggered: bool = false,
    // a handle on what the button has to act on
    index: usize = 0,

    pub fn contains(self: *const Self, pos: Vec2) bool {
        return self.rect.contains(pos);
    }

    pub fn update(self: *Self, mouse: MouseState) void {
        if (self.enabled) {
            self.hovered = !mouse.l_button.is_down and self.contains(mouse.current_pos);
            self.clicked = mouse.l_button.is_clicked and self.contains(mouse.current_pos);
            self.released = mouse.l_button.is_released and self.contains(mouse.current_pos) and self.contains(mouse.l_down_pos);
            self.triggered = mouse.l_button.is_down and self.contains(mouse.l_down_pos);
        } else {
            self.hovered = false;
            self.clicked = false;
            self.released = false;
            self.triggered = false;
        }
    }
};

pub const Line = struct {
    p0: Vec2,
    p1: Vec2,

    pub fn intersects(self: *const Line, other: Line) ?Vec2 {
        return lineSegmentsIntersect(self.p0, self.p1, other.p0, other.p1);
    }

    /// projects the point onto the line, and then returns the fract of that projected point
    /// along the line, where 0 is p0 and 1 is p1
    pub fn unlerp(self: *const Line, point: Vec2) f32 {
        // TODO (21 Jul 2023 sam): Check if this works. Copied over...
        const l_sqr = self.p0.distanceSqr(self.p1);
        if (l_sqr == 0.0) return 0.0;
        // TODO (02 Feb 2022 sam): Why is this divided by l_sqr and not l? Does dot product
        // return a squared length of projected line length?
        const t = point.subtract(self.p0).dot(self.p1.subtract(self.p0)) / l_sqr;
        return t;
    }
};

pub const TextLine = struct {
    text: []const u8,
    position: Vec2,
};

pub fn rangeOverlap(r0: f32, r1: f32, s0: f32, s1: f32) bool {
    const r_start = @min(r0, r1);
    const r_end = @max(r0, r1);
    const s_start = @min(s0, s1);
    const s_end = @max(s0, s1);
    return (r_start <= s_end and s_start <= r_end);
}

pub fn pointToRectDistanceSqr(point: Vec2, position: Vec2, size: Vec2) f32 {
    const other = position.add(size);
    const dx = @max(position.x - point.x, @max(0, point.x - other.x));
    const dy = @max(position.y - point.y, @max(0, point.y - other.y));
    return dx * dx + dy * dy;
}

pub fn easeinoutf(start: f32, end: f32, t: f32) f32 {
    // Bezier Blend as per StackOverflow : https://stackoverflow.com/a/25730573/5453127
    // t goes between 0 and 1.
    const x = t * t * (3.0 - (2.0 * t));
    return start + ((end - start) * x);
}

pub fn milliTimestamp() u64 {
    return std.time.milliTimestamp();
}

pub fn debugPrint(comptime fmt: []const u8, args: anytype) void {
    std.debug.print(fmt, args);
}

/// Checks if a ray in +ve x direction from point intersects with line v0-v1
pub fn xRayIntersects(point: Vec2, v0: Vec2, v1: Vec2) bool {
    // if point.y is not between v0.y and v1.y, no intersection
    if (!((point.y >= @min(v0.y, v1.y)) and (point.y <= @max(v0.y, v1.y)))) return false;
    // if point.x is greater than both verts, no intersection
    if (point.x > v0.x and point.x > v1.x) return false;
    // if point.x is less than both verts, intersection
    if (point.x <= v0.x and point.x <= v1.x) return true;
    // point.x is between v0.x and v1.x
    // get the point of intersection
    const y_fract = (point.y - v0.y) / (v1.y - v0.y);
    const x_intersect = lerpf(v0.x, v1.x, y_fract);
    // if intersection point is more than point.x, intersection
    return x_intersect >= point.x;
}

pub fn polygonArea(verts: []const Vec2) f32 {
    var acc: f32 = 0;
    for (verts, 0..verts.len) |p0, i| {
        const p1 = if (i == verts.len - 1) verts[0] else verts[i + 1];
        acc += (p0.x * p1.y) - (p1.x * p0.y);
    }
    return @abs(acc / 2);
}

pub fn polygonContainsPoint(verts: []const Vec2, point: Vec2, bbox: ?Rect) bool {
    // TODO (27 Jul 2024 sam): If there is no bbox, then compute it first.
    if (bbox) |box| {
        if (!box.contains(point)) return false;
    }
    // counts the number of intersections between edges and a line from point towards +x
    var count: usize = 0;
    for (verts, 0..) |v0, i| {
        // var v1 = verts[0];
        // if (i < verts.len - 1) {
        //     v1 = verts[i + 1];
        // }
        const v1 = if (i < verts.len - 1) verts[i + 1] else verts[0];
        // const v1 = if (i == verts.len - 1) verts[0] else verts[i + i];
        if (xRayIntersects(point, v0, v1)) count += 1;
    }
    return @mod(count, 2) == 1;
}

/// t varies from 0 to 1. (Can also be outside the range for extrapolation)
pub fn lerpf(start: f32, end: f32, t: f32) f32 {
    return (start * (1.0 - t)) + (end * t);
}

// returns t from 0-1 start-end
pub fn unlerpf(start: f32, end: f32, current: f32) f32 {
    const total = end - start;
    if (total == 0) return 0;
    return (current - start) / total;
}

/// When we have an index that we want to toggle through while looping, then we use this.
pub fn applyChangeLooped(value: u8, change: i8, max: u8) u8 {
    return applyChange(value, change, max, true);
}

/// When we have an index that we want to toggle through while looping, then we use this.
pub fn applyChange(value: anytype, change: anytype, max: anytype, loop: bool) @TypeOf(value) {
    const max_return = if (loop) 0 else max;
    const min_return = if (loop) max else 0;
    std.debug.assert(change == 1 or change == -1);
    if (change == 1) {
        if (value == max) return max_return;
        return value + 1;
    }
    if (change == -1) {
        if (value == 0) return min_return;
        return value - 1;
    }
    unreachable;
}

pub fn lineSegmentsIntersect(p1: Vec2, p2: Vec2, p3: Vec2, p4: Vec2) ?Vec2 {
    // sometimes it looks like single points are being passed in
    if (p1.equal(p2) and p2.equal(p3) and p3.equal(p4)) {
        return p1;
    }
    if (p1.equal(p2) or p3.equal(p4)) {
        return null;
    }
    const t = ((p1.x - p3.x) * (p3.y - p4.y)) - ((p1.y - p3.y) * (p3.x - p4.x));
    const u = ((p2.x - p1.x) * (p1.y - p3.y)) - ((p2.y - p1.y) * (p1.x - p3.x));
    const d = ((p1.x - p2.x) * (p3.y - p4.y)) - ((p1.y - p2.y) * (p3.x - p4.x));
    // TODO (24 Apr 2021 sam): There is an performance improvement here where the division is not
    // necessary. Be careful of the negative signs when figuring that all out.  @@Performance
    const td = t / d;
    const ud = u / d;
    if (td >= 0.0 and td <= 1.0 and ud >= 0.0 and ud <= 1.0) {
        var s = t / d;
        if (d == 0) {
            s = 0;
        }
        return Vec2{
            .x = p1.x + s * (p2.x - p1.x),
            .y = p1.y + s * (p2.y - p1.y),
        };
    } else {
        return null;
    }
}

pub fn lineContains(p0: Vec2i, p1: Vec2i, point: Vec2i) bool {
    const p_is_horizontal = p0.y == p1.y;
    const p_fixed = p0.orthoFixed(p_is_horizontal);
    const point_fixed = point.orthoFixed(p_is_horizontal);
    if (p_fixed != point_fixed) return false;
    const p_start = @min(p0.orthoVariable(p_is_horizontal), p1.orthoVariable(p_is_horizontal));
    const p_end = @max(p0.orthoVariable(p_is_horizontal), p1.orthoVariable(p_is_horizontal));
    const point_v = point.orthoVariable(p_is_horizontal);
    return (p_start <= point_v) and (point_v <= p_end);
}

// assumes the lines are axis aligned
// returns a point of intersectoin
pub fn linesIntersect(p0: Vec2i, p1: Vec2i, q0: Vec2i, q1: Vec2i) ?Vec2i {
    const p_is_horizontal = p0.y == p1.y;
    const q_is_horizontal = q0.y == q1.y;
    const p_start = @min(p0.orthoVariable(p_is_horizontal), p1.orthoVariable(p_is_horizontal));
    const p_end = @max(p0.orthoVariable(p_is_horizontal), p1.orthoVariable(p_is_horizontal));
    const q_start = @min(q0.orthoVariable(q_is_horizontal), q1.orthoVariable(q_is_horizontal));
    const q_end = @max(q0.orthoVariable(q_is_horizontal), q1.orthoVariable(q_is_horizontal));
    const p_fixed = p0.orthoFixed(p_is_horizontal);
    const q_fixed = q0.orthoFixed(q_is_horizontal);
    if (p_is_horizontal == q_is_horizontal) {
        if (p_fixed == q_fixed) {
            // lines are parallel. They intersect if they have the same fixed
            // and they overlap
            if (p_start <= q_end and q_start <= p_end) {
                // overlap exists
                // dont return p0 if there are multiple points of overlap
                // points that overlap go from max_of_starts to min_of_ends
                const overlap_start = @max(p_start, q_start);
                const overlap_end = @min(p_end, q_end);
                const overlap = blk: {
                    if (overlap_end - overlap_start > 1) break :blk overlap_start + 1;
                    if (overlap_start == p0.orthoVariable(p_is_horizontal)) break :blk overlap_end;
                    break :blk overlap_start;
                };
                if (overlap > overlap_end) return null;
                return Vec2i.orthoConstruct(p_fixed, overlap, p_is_horizontal);
            } else {
                return null;
            }
        } else {
            return null;
        }
    } else {
        // lines are orthogonal check that fixed of both lies between variable of the other
        if (q_start <= p_fixed and p_fixed <= q_end and p_start <= q_fixed and q_fixed <= p_end) {
            return Vec2i.orthoConstruct(p_fixed, q_fixed, p_is_horizontal);
        } else {
            return null;
        }
    }
}

// returns a point of intersectoin - unless p0 is the intersectino point, in which
// case we return null - so that when drawing a line, we dont register as a collision
// with the point that we are leaving
pub fn linesIntersectNotStart(p0: Vec2i, p1: Vec2i, q0: Vec2i, q1: Vec2i) ?Vec2i {
    if (linesIntersect(p0, p1, q0, q1)) |intersect| {
        if (intersect.equal(p0)) return null;
        return intersect;
    } else {
        return null;
    }
}

// pub fn pointToLineDistanceSqr(point: Vec2, line: Line) f32 {
//     // TODO (21 Jul 2023 sam): Check if this works. Copied over...
//     const l_sqr = line.p0.distanceSqr(line.p1);
//     if (l_sqr == 0.0) return line.p0.distanceSqr(point);
//     const t = std.math.clamp(point.subtract(line.p0).dot(line.p1.subtract(line.p0)) / l_sqr, 0.0, 1.0);
//     const projected = line.p0.add(line.p1.subtract(line.p0).scale(t));
//     return point.distanceSqr(projected);
// }

pub fn pointToLineDistanceSqr(point: Vec2, p0: Vec2, p1: Vec2) f32 {
    // TODO (21 Jul 2023 sam): Check if this works. Copied over...
    const l_sqr = p0.distanceSqr(p1);
    if (l_sqr == 0.0) return p0.distanceSqr(point);
    const t = std.math.clamp(point.subtract(p0).dot(p1.subtract(p0)) / l_sqr, 0.0, 1.0);
    const projected = p0.add(p1.subtract(p0).scale(t));
    return point.distanceSqr(projected);
}

pub fn parseBool(token: []const u8) !bool {
    if (std.mem.eql(u8, token, "true")) return true;
    if (std.mem.eql(u8, token, "false")) return false;
    return error.ParseError;
}

/// given an enum, it gives the next value in the cycle, and loops if required
pub fn enumChange(val: anytype, change: i8, loop: bool) @TypeOf(val) {
    const T = @TypeOf(val);
    const max = @typeInfo(T).Enum.fields.len - 1;
    const index = @intFromEnum(val);
    const new_index = applyChange(@as(u8, @intCast(index)), change, @as(u8, @intCast(max)), loop);
    return @as(T, @enumFromInt(new_index));
}

pub fn assert(condition: bool) void {
    if (!condition) unreachable; // assertion failed.
}

pub fn readFileContents(path: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const file_size = try file.getEndPos();
    const data = try file.readToEndAlloc(allocator, file_size);
    return data;
}

pub fn writeFileContents(path: []const u8, contents: []const u8, allocator: std.mem.Allocator) !void {
    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();
    _ = try file.writeAll(contents);
    _ = allocator;
}

/// ConstKey is a useful key that can be used for the ConstIndexArray
/// It has a few methods like equal, serialization etc.
/// It needs a unique string as input so that the compiler knows that
/// each unique string is a unique type
pub fn ConstKey(comptime val: []const u8) type {
    return struct {
        // Uses 0 memory. Just for the compiler to know that this is a
        // unique type.
        _unique: [val.len]void = undefined,
        index: usize,
        pub fn equal(a: *const @This(), b: @This()) bool {
            return a.index == b.index;
        }
        // pub fn serialize(self: *const @This(), js: *serializer.JsonSerializer) !void {
        //     serializer.serialize("index", self.index, js) catch unreachable;
        // }
        // pub fn deserialize(self: *@This(), js: std.json.Value, options: serializer.DeserializationOptions) void {
        //     serializer.deserialize("index", &self.index, js, options);
        // }
    };
}

/// ConstIndexArray is a wrapper around ArrayHashMap that allows us to
/// just use append where it will just increment the index and add the
/// new item at that key.
/// We use this to have lists where we want the indexes to remain valid
/// even when other items in the list are deleted
/// Ideally we use ConstKey as the key.
pub fn ConstIndexArray(comptime Key: type, comptime T: type) type {
    return struct {
        const Self = @This();
        const Pair = struct {
            key: Key,
            val: T,
        };
        map: std.AutoArrayHashMap(Key, T),
        counter: usize,

        // TODO (25 Dec 2023 sam): add a method that can return pairs of these.
        // const Pair = struct {
        //     key: @TypeOf(Key),
        //     value: @TypeOf(T),
        // };

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .map = std.AutoArrayHashMap(Key, T).init(allocator),
                .counter = 0,
            };
        }

        pub fn deinit(self: *Self) void {
            self.map.deinit();
        }

        pub fn clearRetainingCapacity(self: *Self) void {
            self.map.clearRetainingCapacity();
            self.counter = 0;
        }

        pub fn serialize(self: *const Self, js: *serializer.JsonSerializer) !void {
            for (self.keys()) |key| {
                var buffer: [8]u8 = undefined;
                const key_name = std.fmt.bufPrint(buffer[0..], "{d}", .{key.index}) catch unreachable;
                const val = self.getPtr(key);
                try serializer.serialize(key_name, val.*, js);
            }
        }

        pub fn deserialize(self: *@This(), js: std.json.Value, options: serializer.DeserializationOptions) void {
            var list_keys = js.object.iterator();
            while (list_keys.next()) |pair| {
                const key = pair.key_ptr.*;
                var val: T = undefined;
                const index = Key{ .index = std.fmt.parseInt(usize, key, 10) catch unreachable };
                serializer.deserialize(null, &val, js.object.get(key).?, options);
                self.map.put(index, val) catch unreachable;
                if (index.index + 1 > self.counter) self.counter = index.index + 1;
            }
        }

        pub fn getNextKey(self: *Self) Key {
            // TODO (29 Jan 2024 sam): If we change this design to give a recently
            // deleted key instead, it will affect simulation.tryRemoveTerraAnt, which
            // holds references to possibly unused trail keys. Keep in mind when refactor
            return .{ .index = self.counter };
        }

        pub fn append(self: *Self, item: T) !void {
            try self.map.put(self.getNextKey(), item);
            self.counter += 1;
        }

        /// we want to crash on trying to get things that don't exist
        pub fn getPtr(self: *const Self, key: Key) *T {
            return self.map.getPtr(key).?;
        }

        pub fn getConstPtr(self: *const Self, key: Key) *const T {
            return self.map.getPtr(key).?;
        }

        pub fn ifGetPtr(self: *const Self, key: Key) ?*T {
            return self.map.getPtr(key);
        }

        pub fn items(self: *Self) []T {
            return self.map.values();
        }

        pub fn constItems(self: *const Self) []T {
            return self.map.values();
        }

        pub fn keys(self: *const Self) []Key {
            return self.map.keys();
        }

        pub fn count(self: *const Self) usize {
            return self.map.count();
        }

        pub fn delete(self: *Self, key: Key) void {
            const removed = self.map.swapRemove(key);
            std.debug.assert(removed);
        }

        pub fn contains(self: *const Self, key: Key) bool {
            return self.map.contains(key);
        }

        pub fn remove(self: *Self, key: Key) T {
            const val = self.map.fetchSwapRemove(key).?;
            return val.value;
        }
    };
}

pub fn unlerp(start: f32, end: f32, val: f32) f32 {
    if (start == end) return 0;
    return (val - start) / (end - start);
}

pub fn lerp(start: f32, end: f32, val: f32) f32 {
    if (start == end) return start;
    return start + (val * (end - start));
}
