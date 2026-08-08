const std = @import("std");
const ui = @import("zGUI");
const zp = @import("zephyr_runtime");

const Icons = @This();

play: ui.TextureHandle = .none,
pause: ui.TextureHandle = .none,
stop: ui.TextureHandle = .none,

pub fn init(renderer: *ui.OpenGlRenderer, allocator: std.mem.Allocator) !Icons {
    var textures: Icons = .{};
    errdefer textures.deinit(renderer);

    textures.play = try load(
        renderer,
        allocator,
        "play.png",
        @embedFile("../resources/assets/play.png"),
    );
    textures.pause = try load(
        renderer,
        allocator,
        "pause.png",
        @embedFile("../resources/assets/pause.png"),
    );
    textures.stop = try load(
        renderer,
        allocator,
        "stop.png",
        @embedFile("../resources/assets/stop.png"),
    );
    return textures;
}

pub fn deinit(self: *Icons, renderer: *ui.OpenGlRenderer) void {
    renderer.destroyTexture(&self.play);
    renderer.destroyTexture(&self.pause);
    renderer.destroyTexture(&self.stop);
}

fn load(
    renderer: *ui.OpenGlRenderer,
    allocator: std.mem.Allocator,
    filename: []const u8,
    encoded: []const u8,
) !ui.TextureHandle {
    var decoded = try zp.RawTexture.init(filename, @constCast(encoded));
    defer decoded.deinit(allocator);

    const pixels = switch (decoded.pixels) {
        .ldr => |pixels| pixels,
        .hdr => return error.UnsupportedEditorIconFormat,
    };

    // The source glyphs are black silhouettes. Store them as white-alpha masks
    // so zGUI can tint them for the dark editor theme.
    var i: usize = 0;
    while (i + 4 <= pixels.len) : (i += 4) {
        @memset(pixels[i..][0..3], 255);
    }

    return renderer.createTextureRgba(decoded.width, decoded.height, pixels);
}
