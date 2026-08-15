const std = @import("std");
const ui = @import("zGUI");
const zp = @import("zephyr_runtime");

pub const PixelSize = struct {
    width: u32,
    height: u32,
};

pub const BeginFrameInput = struct {
    window: *zp.Window,
    framebuffer_size: PixelSize,
    font_atlas: *ui.FontAtlas,
    window_size: ui.Vec2,
    ui_scale: f32 = 1,
    dt: f32,
};

pub const Frame = struct {
    events: []const ui.PlatformEvent,
    framebuffer_size: PixelSize,
    text_raster_scale: f32,
    window_size: ui.Vec2,
    dt: f32,
    clipboard: ui.Clipboard,

    pub fn toBeginFrame(self: Frame) ui.BeginFrame {
        return .{
            .events = self.events,
            .window_size = self.window_size,
            .dt = self.dt,
            .clipboard = self.clipboard,
        };
    }
};

const Backend = @This();

allocator: std.mem.Allocator,
events: std.ArrayList(ui.PlatformEvent) = .empty,
text_buffer: std.ArrayList(u8) = .empty,
renderer: *ui.OpenGlRenderer,

pub fn init(allocator: std.mem.Allocator, renderer: *ui.OpenGlRenderer) Backend {
    return .{
        .allocator = allocator,
        .renderer = renderer,
    };
}

pub fn deinit(self: *Backend) void {
    self.events.deinit(self.allocator);
    self.text_buffer.deinit(self.allocator);
    self.* = undefined;
}

pub fn beginFrame(self: *Backend, input: BeginFrameInput, runtime_events: []const zp.ZEvent) !Frame {
    const frame = Frame{
        .events = try self.translateEvents(runtime_events, input.ui_scale),
        .window_size = input.window_size,
        .framebuffer_size = input.framebuffer_size,
        .text_raster_scale = framebufferScale(input.window_size, input.framebuffer_size),
        .dt = input.dt,
        .clipboard = clipboardFor(input.window),
    };
    try self.renderer.syncFontAtlas(input.font_atlas);
    try self.renderer.beginFrameLogical(
        frame.framebuffer_size.width,
        frame.framebuffer_size.height,
        frame.window_size.x,
        frame.window_size.y,
    );

    return frame;
}

fn translateEvents(self: *Backend, runtime_events: []const zp.ZEvent, ui_scale: f32) ![]const ui.PlatformEvent {
    self.events.clearRetainingCapacity();
    self.text_buffer.clearRetainingCapacity();

    var text_capacity: usize = 0;
    for (runtime_events) |event| switch (event) {
        .CharInput => text_capacity += 4,
        else => {},
    };
    try self.text_buffer.ensureTotalCapacity(self.allocator, text_capacity);

    for (runtime_events) |event| {
        if (try self.toPlatformEvent(event, ui_scale)) |platform_event| {
            try self.events.append(self.allocator, platform_event);
        }
    }
    return self.events.items;
}

fn toPlatformEvent(self: *Backend, event: zp.ZEvent, ui_scale: f32) !?ui.PlatformEvent {
    return switch (event) {
        .MouseMove => |pos| .{ .mouse_move = .{ .x = pos.x / ui_scale, .y = pos.y / ui_scale } },
        .MousePressed => |button| .{ .mouse_down = mapMouseButton(button) orelse return null },
        .MouseReleased => |button| .{ .mouse_up = mapMouseButton(button) orelse return null },
        .MouseScroll => |scroll| .{ .scroll = .{ .x = scroll.x, .y = scroll.y } },
        .KeyPressed => |key| .{ .key_down = mapKey(key) },
        .KeyRepeated => |key| .{ .key_down = mapKey(key) },
        .KeyReleased => |key| .{ .key_up = mapKey(key) },
        .CharInput => |codepoint| try self.textInputEvent(codepoint),
        .WindowResize => |resize| .{ .window_resize = .{ .x = @as(f32, @floatFromInt(resize.width)) / ui_scale, .y = @as(f32, @floatFromInt(resize.height)) / ui_scale } },
        .WindowClose => .window_close,
        .FramebufferResize, .ContentScaleChange => null,
    };
}

fn textInputEvent(self: *Backend, codepoint: u32) !?ui.PlatformEvent {
    var buf: [4]u8 = undefined;
    const len = std.unicode.utf8Encode(@intCast(codepoint), &buf) catch return null;
    const start = self.text_buffer.items.len;
    try self.text_buffer.appendSlice(self.allocator, buf[0..len]);
    return .{ .text_input = self.text_buffer.items[start .. start + len] };
}

pub fn setCursor(window: *zp.Window, cursor: ui.CursorKind) void {
    switch (cursor) {
        .arrow => window.setCursor(.arrow),
        .hand => window.setCursor(.hand),
        .text => window.setCursor(.text),
        .resize_x => window.setCursor(.resize_x),
        .resize_y => window.setCursor(.resize_y),
        .resize_diag_a, .resize_diag_b => window.setCursor(.arrow),
    }
}

pub fn toUiSize(size: zp.Window.WindowSize, ui_scale: f32) ui.Vec2 {
    return .{ .x = @as(f32, @floatFromInt(size.width)) / ui_scale, .y = @as(f32, @floatFromInt(size.height)) / ui_scale };
}

pub fn toPixelSize(size: zp.Window.WindowSize) PixelSize {
    return .{ .width = size.width, .height = size.height };
}

pub fn renderSizeForRect(rect: ui.Rect, scale: f32) PixelSize {
    return .{
        .width = @intFromFloat(@max(1, @round(rect.w * scale))),
        .height = @intFromFloat(@max(1, @round(rect.h * scale))),
    };
}

fn framebufferScale(window_size: ui.Vec2, framebuffer_size: PixelSize) f32 {
    const framebuffer_width: f32 = @floatFromInt(framebuffer_size.width);
    const framebuffer_height: f32 = @floatFromInt(framebuffer_size.height);
    const x = framebuffer_width / @max(1, window_size.x);
    const y = framebuffer_height / @max(1, window_size.y);
    return @max(0.25, @max(x, y));
}

fn mapMouseButton(button: zp.MouseButton) ?ui.MouseButton {
    return switch (button) {
        .Left => .left,
        .Right => .right,
        .Middle => .middle,
        else => null,
    };
}

fn mapKey(key: zp.Key) ui.Key {
    const value = @intFromEnum(key);
    if (value >= @intFromEnum(zp.Key.Num0) and value <= @intFromEnum(zp.Key.Num9)) {
        return @enumFromInt(@intFromEnum(ui.Key.num_0) + value - @intFromEnum(zp.Key.Num0));
    }
    if (value >= @intFromEnum(zp.Key.A) and value <= @intFromEnum(zp.Key.Z)) {
        return @enumFromInt(@intFromEnum(ui.Key.a) + value - @intFromEnum(zp.Key.A));
    }
    if (value >= @intFromEnum(zp.Key.F1) and value <= @intFromEnum(zp.Key.F25)) {
        return @enumFromInt(@intFromEnum(ui.Key.f1) + value - @intFromEnum(zp.Key.F1));
    }
    if (value >= @intFromEnum(zp.Key.Kp0) and value <= @intFromEnum(zp.Key.Kp9)) {
        return @enumFromInt(@intFromEnum(ui.Key.kp_0) + value - @intFromEnum(zp.Key.Kp0));
    }
    return switch (key) {
        .Space => .space,
        .Apostrophe => .apostrophe,
        .Comma => .comma,
        .Minus => .minus,
        .Period => .period,
        .Slash => .slash,
        .Semicolon => .semicolon,
        .Equal => .equal,
        .LeftBracket => .left_bracket,
        .Backslash => .backslash,
        .RightBracket => .right_bracket,
        .GraveAccent => .grave_accent,
        .World1 => .world_1,
        .World2 => .world_2,
        .Escape => .escape,
        .Enter => .enter,
        .Tab => .tab,
        .Backspace => .backspace,
        .Insert => .insert,
        .Delete => .delete,
        .Left => .left,
        .Right => .right,
        .Up => .up,
        .Down => .down,
        .PageUp => .page_up,
        .PageDown => .page_down,
        .Home => .home,
        .End => .end,
        .CapsLock => .caps_lock,
        .ScrollLock => .scroll_lock,
        .NumLock => .num_lock,
        .PrintScreen => .print_screen,
        .Pause => .pause,
        .KpDecimal => .kp_decimal,
        .KpDivide => .kp_divide,
        .KpMultiply => .kp_multiply,
        .KpSubtract => .kp_subtract,
        .KpAdd => .kp_add,
        .KpEnter => .kp_enter,
        .KpEqual => .kp_equal,
        .LeftShift => .left_shift,
        .LeftControl => .left_control,
        .LeftAlt => .left_alt,
        .LeftSuper => .left_super,
        .RightShift => .right_shift,
        .RightControl => .right_control,
        .RightAlt => .right_alt,
        .RightSuper => .right_super,
        .Menu => .menu,
        else => .unknown,
    };
}

fn clipboardFor(window: *zp.Window) ui.Clipboard {
    return .{ .context = window, .read_fn = clipboardRead, .write_fn = clipboardWrite };
}

fn clipboardRead(context: ?*anyopaque) []const u8 {
    const window: *zp.Window = @ptrCast(@alignCast(context orelse return ""));
    return window.getClipboard();
}

fn clipboardWrite(context: ?*anyopaque, text: []const u8) void {
    const window: *zp.Window = @ptrCast(@alignCast(context orelse return));
    window.setClipboard(text);
}
