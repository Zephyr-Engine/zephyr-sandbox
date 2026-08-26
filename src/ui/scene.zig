const std = @import("std");
const ui = @import("zGUI");
const zimp = @import("zimp");
const zp = @import("zephyr_runtime");

const SceneController = @import("../editor/scene_controller.zig");
const SceneEntityRow = @import("components/scene_entity_row.zig").SceneEntityRow;
const panel = @import("panel.zig");

pub const panel_id = panel.id("editor.scene");
pub const descriptor: panel.Descriptor = .{
    .id = panel_id,
    .title = "Scene",
    .min_size = .{ .x = 190, .y = 240 },
};

pub const Icons = SceneEntityRow.Icons;
const Scene = @This();

allocator: std.mem.Allocator,
scenes: *SceneController,
icons: Icons,
root_node: ui.NodeId = ui.invalid_node,
body_node: ui.NodeId = ui.invalid_node,
list_node: ui.NodeId = ui.invalid_node,
rows: std.ArrayList(SceneEntityRow) = .empty,
scene_revision: u64,

pub const Dependencies = struct {
    allocator: std.mem.Allocator,
    scenes: *SceneController,
    icons: Icons,
};

pub fn init(dependencies: Dependencies) Scene {
    return .{
        .allocator = dependencies.allocator,
        .scenes = dependencies.scenes,
        .icons = dependencies.icons,
        .scene_revision = dependencies.scenes.revision(),
    };
}

pub fn deinit(self: *Scene) void {
    self.rows.deinit(self.allocator);
}

pub fn mount(self: *Scene, state: *ui.Ui, parent: ui.NodeId, _: panel.Services) !void {
    const root_node = try ui.widgets.column(state, parent, .{
        .width = .fill,
        .height = .fill,
        .background = .shell,
    });
    errdefer state.destroySubtree(root_node);
    const body_node = try ui.widgets.column(state, root_node, .{
        .width = .fill,
        .height = .fill,
        .padding = .{
            .left = state.theme.space.md,
            .right = state.theme.space.md,
            .top = state.theme.space.md,
            .bottom = state.theme.space.lg,
        },
        .background = .shell,
        .overflow_y = .scroll,
    });

    self.root_node = root_node;
    self.body_node = body_node;
    try self.refresh(state, true);
}

pub fn update(self: *Scene, state: *ui.Ui, _: panel.Frame) !void {
    try self.refresh(state, false);
    for (self.rows.items) |row| {
        if (row.clicked(state)) {
            self.scenes.selectEntity(row.entity_id);
            self.scene_revision = self.scenes.revision();
            try self.rebuildList(state);
            return;
        }
    }
    for (self.rows.items) |row| {
        if (row.hovered(state)) {
            state.requestCursor(.hand);
            return;
        }
    }
}

pub fn unmount(self: *Scene, state: *ui.Ui) void {
    state.destroySubtree(self.root_node);
    self.root_node = ui.invalid_node;
    self.body_node = ui.invalid_node;
    self.list_node = ui.invalid_node;
    self.rows.clearRetainingCapacity();
}

pub fn root(self: *const Scene) ui.NodeId {
    return self.root_node;
}

fn refresh(self: *Scene, state: *ui.Ui, force: bool) !void {
    const next_revision = self.scenes.revision();
    if (!force and self.scene_revision == next_revision) return;
    self.scene_revision = next_revision;

    if (self.scenes.activeDocument()) |scene_document| {
        if (self.scenes.selectedEntity()) |selected| {
            if (!containsEntity(scene_document.document.entities, selected)) self.scenes.selectEntity(null);
        }
    } else {
        self.scenes.selectEntity(null);
    }
    self.scene_revision = self.scenes.revision();
    try self.rebuildList(state);
}

fn rebuildList(self: *Scene, state: *ui.Ui) !void {
    if (self.list_node != ui.invalid_node) state.destroySubtree(self.list_node);
    self.rows.clearRetainingCapacity();

    const list_node = try ui.widgets.column(state, self.body_node, .{
        .width = .fill,
        .height = .hug,
        .gap = state.theme.space.xxs,
        .background = .transparent,
    });
    errdefer state.destroySubtree(list_node);

    if (self.scenes.activeDocument()) |scene_document| {
        for (scene_document.document.entities) |entity| {
            const selected = if (self.scenes.selectedEntity()) |id| id.eql(entity.id) else false;
            try self.rows.append(self.allocator, try SceneEntityRow.init(state, list_node, entity, selected, self.icons));
        }
    } else {
        _ = try ui.widgets.text(state, list_node, "No scene loaded", .{
            .width = .fill,
            .height = .{ .px = 28 },
            .padding = .{ .left = state.theme.space.lg, .top = state.theme.space.sm },
            .color = .text_muted,
            .size = 12,
        });
    }
    self.list_node = list_node;
}

fn containsEntity(entities: []const zimp.scene.SceneEntity, id: zp.SceneEntityId) bool {
    for (entities) |entity| if (entity.id.eql(id)) return true;
    return false;
}
