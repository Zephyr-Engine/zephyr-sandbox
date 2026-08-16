const zp = @import("zephyr_runtime");
const std = @import("std");
const ui = @import("zGUI");
const zimp = @import("zimp");

const SceneController = @import("../editor/scene_controller.zig");
const panel = @import("panel.zig");

pub const panel_id = panel.id("editor.scene");
pub const descriptor: panel.Descriptor = .{
    .id = panel_id,
    .title = "Scene",
    .min_size = .{ .x = 190, .y = 240 },
};

pub const Icons = struct {
    camera: ui.TextureHandle,
    model: ui.TextureHandle,
};

const ItemKind = enum {
    camera,
    model,
};

const Row = struct {
    node: ui.NodeId,
    entity_id: zp.SceneEntityId,
};

const camera_component_id = zp.ComponentTypeId.parseComptime(zp.components.CameraComponent.schema_meta.id);
const mesh_component_id = zp.ComponentTypeId.parseComptime(zp.components.MeshRenderComponent.schema_meta.id);

const Scene = @This();

allocator: std.mem.Allocator,
scenes: *SceneController,
icons: Icons,
root_node: ui.NodeId = ui.invalid_node,
body_node: ui.NodeId = ui.invalid_node,
list_node: ui.NodeId = ui.invalid_node,
rows: std.ArrayList(Row) = .empty,
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
        .padding = .{ .left = 8, .right = 8, .top = 8, .bottom = 10 },
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
        if (state.clicked(row.node)) {
            self.scenes.selectEntity(row.entity_id);
            self.scene_revision = self.scenes.revision();
            try self.rebuildList(state);
            return;
        }
    }

    for (self.rows.items) |row| {
        if (state.interaction(row.node).hovered) {
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
    if (!force and self.scene_revision == next_revision) {
        return;
    }
    self.scene_revision = next_revision;

    const document = self.scenes.activeDocument();
    if (document) |scene| {
        if (self.scenes.selectedEntity()) |selected| {
            if (!containsEntity(scene.document.entities, selected)) {
                self.scenes.selectEntity(null);
            }
        }
    } else {
        self.scenes.selectEntity(null);
    }
    self.scene_revision = self.scenes.revision();
    try self.rebuildList(state);
}

fn rebuildList(self: *Scene, state: *ui.Ui) !void {
    if (self.list_node != ui.invalid_node) {
        state.destroySubtree(self.list_node);
    }
    self.rows.clearRetainingCapacity();

    const list_node = try ui.widgets.column(state, self.body_node, .{
        .width = .fill,
        .height = .hug,
        .gap = 3,
        .background = .transparent,
    });
    errdefer state.destroySubtree(list_node);

    if (self.scenes.activeDocument()) |scene| {
        for (scene.document.entities) |entity| {
            try self.addRow(state, list_node, entity);
        }
    } else {
        _ = try ui.widgets.text(state, list_node, "No scene loaded", .{
            .width = .fill,
            .height = .{ .px = 28 },
            .padding = .{ .left = 8, .top = 6 },
            .color = .text_muted,
            .size = 12,
        });
    }

    self.list_node = list_node;
}

fn addRow(self: *Scene, state: *ui.Ui, parent: ui.NodeId, entity: zimp.scene.SceneEntity) !void {
    const selected = if (self.scenes.selectedEntity()) |id| id.eql(entity.id) else false;
    const row = try ui.widgets.button(state, parent, "", state.theme.style(.{
        .width = .fill,
        .height = .{ .px = 34 },
        .padding = .{ .left = 8, .right = 9, .top = 7, .bottom = 7 },
        .gap = 9,
        .direction = .row,
        .background = if (selected) .accent_soft else .transparent,
        .border = if (selected) .accent else .transparent,
        .radius = .control,
    }));
    var style = state.nodeStyle(row).?;
    style.border_width = 1;
    style.hover_background = ui.Color.rgba(255, 255, 255, 18);
    style.hover_border_color = ui.Color.rgba(139, 92, 246, 125);
    style.pressed_background = ui.Color.rgba(139, 92, 246, 70);
    try state.setStyle(row, style);

    _ = try ui.widgets.image(state, row, .{
        .texture = switch (itemKind(entity.components)) {
            .camera => self.icons.camera,
            .model => self.icons.model,
        },
        .style = state.theme.style(.{
            .width = .{ .px = 20 },
            .height = .{ .px = 20 },
            .background = .transparent,
        }),
        .tint = if (selected) ui.Color.rgba(224, 213, 255, 255) else ui.Color.rgba(196, 198, 209, 255),
    });
    _ = try ui.widgets.text(state, row, entity.name, .{
        .width = .fill,
        .height = .fill,
        .padding = .{ .top = 2 },
        .color = if (selected) .text else .text_muted,
        .size = 13,
    });
    try self.rows.append(self.allocator, .{ .node = row, .entity_id = entity.id });
}

fn itemKind(components: []const zimp.scene.SceneComponent) ItemKind {
    for (components) |component| {
        if (component.type_id.eql(camera_component_id)) return .camera;
    }
    return .model;
}

fn containsEntity(entities: []const zimp.scene.SceneEntity, id: zp.SceneEntityId) bool {
    for (entities) |entity| {
        if (entity.id.eql(id)) return true;
    }
    return false;
}

test "scene item kind prefers a camera over a mesh renderer" {
    const components = [_]zimp.scene.SceneComponent{
        .{ .type_id = mesh_component_id },
        .{ .type_id = camera_component_id },
    };
    try std.testing.expectEqual(ItemKind.camera, itemKind(&components));
}
