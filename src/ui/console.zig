const ui = @import("zGUI");

const panel = @import("panel.zig");

pub const panel_id = panel.id("editor.console");
pub const descriptor: panel.Descriptor = .{
    .id = panel_id,
    .title = "Console",
    .min_size = .{ .x = 240, .y = 96 },
};

const Console = @This();

root_node: ui.NodeId = ui.invalid_node,

pub fn init() Console {
    return .{};
}

pub fn mount(self: *Console, state: *ui.Ui, parent: ui.NodeId, services: panel.Services) !void {
    _ = services;
    const root_node = try ui.widgets.column(state, parent, .{
        .width = .fill,
        .height = .fill,
        .gap = 8,
        .padding = .{ .left = 12, .right = 12, .top = 10, .bottom = 10 },
        .background = .shell,
        .border = .stroke_soft,
        .border_edges = .{ .top = 1 },
    });
    errdefer state.destroySubtree(root_node);

    const header = try ui.widgets.row(state, root_node, .{
        .width = .fill,
        .height = .{ .px = 28 },
        .gap = 8,
    });
    _ = try ui.widgets.text(state, header, "Console", .{
        .width = .{ .px = 72 },
        .height = .fill,
        .padding = .{ .top = 6 },
        .size = 14,
    });

    self.root_node = root_node;
}

pub fn update(self: *Console, state: *ui.Ui, frame: panel.Frame) !void {
    _ = self;
    _ = state;
    _ = frame;
}

pub fn unmount(self: *Console, state: *ui.Ui) void {
    state.destroySubtree(self.root_node);
    self.root_node = ui.invalid_node;
}

pub fn root(self: *const Console) ui.NodeId {
    return self.root_node;
}
