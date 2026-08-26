const std = @import("std");
const ui = @import("zGUI");

const ViewportStats = @import("components/viewport_stats.zig").ViewportStats;
const ViewportToolbar = @import("components/viewport_toolbar.zig").ViewportToolbar;
const panel = @import("panel.zig");

pub const panel_id = panel.id("editor.viewport");
pub const descriptor: panel.Descriptor = .{
    .id = panel_id,
    .title = "Viewport",
    .min_size = .{ .x = 240, .y = 240 },
};

pub const Icons = ViewportToolbar.Icons;

pub const TextureBinding = struct {
    texture: ui.TextureHandle,
    generation: u64 = 0,

    pub fn replace(self: *TextureBinding, texture: ui.TextureHandle) void {
        self.texture = texture;
        self.generation +%= 1;
    }
};

const Viewport = @This();

texture: *const TextureBinding,
texture_generation: u64,
icons: Icons,
root_node: ui.NodeId = ui.invalid_node,
image: ui.NodeId = ui.invalid_node,
toolbar: ViewportToolbar = undefined,
stats: ViewportStats = undefined,

pub fn init(texture: *const TextureBinding, icons: Icons) Viewport {
    return .{ .texture = texture, .texture_generation = texture.generation, .icons = icons };
}

pub fn mount(self: *Viewport, state: *ui.Ui, parent: ui.NodeId, services: panel.Services) !void {
    const root_node = try ui.widgets.surface(state, parent, .{
        .width = .fill,
        .height = .fill,
        .direction = .absolute,
        .background = .viewport,
    });
    errdefer state.destroySubtree(root_node);

    const image = try ui.widgets.image(state, root_node, .{
        .texture = self.texture.texture,
        .style = state.theme.style(.{
            .width = .fill,
            .height = .fill,
            .background = .viewport,
            .border = .stroke_soft,
            .border_width = 1,
            .radius = .viewport,
        }),
        .uv0 = .{ .x = 0, .y = 1 },
        .uv1 = .{ .x = 1, .y = 0 },
        .interactive = false,
    });

    self.root_node = root_node;
    self.image = image;
    self.toolbar = try ViewportToolbar.init(state, root_node, services.actions, self.icons);
    self.stats = try ViewportStats.init(state, root_node);
}

pub fn update(self: *Viewport, state: *ui.Ui, frame: panel.Frame) !void {
    if (self.texture_generation != self.texture.generation) {
        self.texture_generation = self.texture.generation;
        ui.widgets.setImage(state, self.image, .{
            .texture = self.texture.texture,
            .uv0 = .{ .x = 0, .y = 1 },
            .uv1 = .{ .x = 1, .y = 0 },
        });
    }
    try self.toolbar.update(state);
    try self.stats.update(state, frame.debug_stats);
}

pub fn unmount(self: *Viewport, state: *ui.Ui) void {
    state.destroySubtree(self.root_node);
    self.root_node = ui.invalid_node;
    self.image = ui.invalid_node;
}

pub fn root(self: *const Viewport) ui.NodeId {
    return self.root_node;
}

test "viewport texture binding records replacements" {
    var binding = TextureBinding{ .texture = .none };
    const replacement: ui.TextureHandle = @enumFromInt(7);
    binding.replace(replacement);

    try std.testing.expectEqual(replacement, binding.texture);
    try std.testing.expectEqual(@as(u64, 1), binding.generation);
}
