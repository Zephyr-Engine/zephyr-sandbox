const zp = @import("zephyr_runtime");
const std = @import("std");
const ui = @import("zGUI");

const ui_runtime = @import("ui/zgui_runtime_backend.zig");

const ViewportTarget = @This();

device: *zp.Device,
framebuffer: zp.Framebuffer,
color_view: zp.TextureView,
pixel_size: ui_runtime.PixelSize = .{ .width = 1, .height = 1 },
renderable: bool = false,

pub fn init(device: *zp.Device) !ViewportTarget {
    var framebuffer = try device.createFramebuffer(1, 1);
    errdefer device.destroyFramebuffer(&framebuffer);
    return .{
        .device = device,
        .color_view = device.framebufferColorView(&framebuffer),
        .framebuffer = framebuffer,
    };
}

pub fn deinit(self: *ViewportTarget) void {
    self.device.destroyFramebuffer(&self.framebuffer);
    self.* = undefined;
}

pub fn ensureSize(self: *ViewportTarget, rect: ui.Rect, raster_scale: f32) !bool {
    if (!isRenderableRect(rect)) {
        self.renderable = false;
        return false;
    }

    const next = ui_runtime.renderSizeForRect(rect, raster_scale);
    if (requiresResize(self.pixel_size, next)) {
        try self.device.resizeFramebuffer(&self.framebuffer, .{
            .width = next.width,
            .height = next.height,
        });
        self.pixel_size = next;
    }
    self.renderable = true;
    return true;
}

pub fn nativeTextureId(self: *const ViewportTarget) u32 {
    return self.device.textureViewNativeId(self.color_view);
}

pub fn renderTarget(self: *ViewportTarget) ?*zp.Framebuffer {
    return if (self.renderable) &self.framebuffer else null;
}

fn isRenderableRect(rect: ui.Rect) bool {
    return !rect.isEmpty();
}

fn requiresResize(current: ui_runtime.PixelSize, next: ui_runtime.PixelSize) bool {
    return !std.meta.eql(current, next);
}

test "empty viewport rectangles are not renderable" {
    try std.testing.expect(!isRenderableRect(.{}));
    try std.testing.expect(!isRenderableRect(.{ .w = 10, .h = 0 }));
    try std.testing.expect(isRenderableRect(.{ .w = 10, .h = 10 }));
}

test "viewport target resizes only for a distinct pixel extent" {
    const current: ui_runtime.PixelSize = .{ .width = 1280, .height = 720 };
    try std.testing.expect(!requiresResize(current, current));
    try std.testing.expect(requiresResize(current, .{ .width = 1920, .height = 1080 }));
}
