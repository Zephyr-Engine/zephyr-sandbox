const ui = @import("zGUI");

const panel = @import("panel.zig");

pub const panel_id = panel.id("editor.scene");
pub const descriptor: panel.Descriptor = .{
    .id = panel_id,
    .title = "Scene",
    .min_size = .{ .x = 190, .y = 240 },
};

const Scene = @This();

root_node: ui.NodeId = ui.invalid_node,

pub fn init() Scene {
    return .{};
}

pub fn mount(self: *Scene, state: *ui.Ui, parent: ui.NodeId, services: panel.Services) !void {
    _ = services;
    const root_node = try ui.widgets.column(state, parent, .{
        .width = .fill,
        .height = .fill,
        .gap = 10,
        .padding = .{ .left = 12, .right = 12, .top = 12, .bottom = 12 },
        .margin = .{ .top = 10, .bottom = 10 },
        .background = .panel,
        .radius_corners = .{
            .top_right = state.theme.radius(.card),
            .bottom_right = state.theme.radius(.card),
        },
    });
    errdefer state.destroySubtree(root_node);

    const header = try ui.widgets.row(state, root_node, .{
        .width = .fill,
        .height = .{ .px = 30 },
        .gap = 8,
    });
    _ = try ui.widgets.text(state, header, "Scene", .{
        .width = .fill,
        .height = .fill,
        .padding = .{ .top = 6 },
        .size = state.theme.font.title,
    });

    self.root_node = root_node;
}

pub fn update(self: *Scene, state: *ui.Ui, frame: panel.Frame) !void {
    _ = self;
    _ = state;
    _ = frame;
}

pub fn unmount(self: *Scene, state: *ui.Ui) void {
    state.destroySubtree(self.root_node);
    self.root_node = ui.invalid_node;
}

pub fn root(self: *const Scene) ui.NodeId {
    return self.root_node;
}
