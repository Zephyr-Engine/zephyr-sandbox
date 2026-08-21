const std = @import("std");
const ui = @import("zGUI");
const zimp = @import("zimp");

const InspectorField = @import("components/inspector_field.zig").InspectorField;
const SceneMutation = @import("../editor/scene_mutation.zig").Mutation;
const SceneController = @import("../editor/scene_controller.zig");
const panel = @import("panel.zig");

pub const panel_id = panel.id("editor.inspector");
pub const descriptor: panel.Descriptor = .{
    .id = panel_id,
    .title = "Inspector",
    .min_size = .{ .x = 230, .y = 240 },
};

const Value = zimp.scene.Value;
const Inspector = @This();

allocator: std.mem.Allocator,
scenes: *SceneController,
root_node: ui.NodeId = ui.invalid_node,
body_node: ui.NodeId = ui.invalid_node,
content_node: ui.NodeId = ui.invalid_node,
entity_name: ?ui.TextField = null,
components: std.ArrayList(ui.Collapsible) = .empty,
fields: std.ArrayList(InspectorField) = .empty,
scene_revision: u64,

pub const Dependencies = struct {
    allocator: std.mem.Allocator,
    scenes: *SceneController,
};

pub fn init(dependencies: Dependencies) Inspector {
    return .{
        .allocator = dependencies.allocator,
        .scenes = dependencies.scenes,
        .scene_revision = dependencies.scenes.revision(),
    };
}

pub fn deinit(self: *Inspector) void {
    self.components.deinit(self.allocator);
    self.fields.deinit(self.allocator);
}

pub fn mount(self: *Inspector, state: *ui.Ui, parent: ui.NodeId, _: panel.Services) !void {
    const root_node = try ui.widgets.column(state, parent, .{
        .width = .fill,
        .height = .fill,
        .background = .shell,
    });
    errdefer state.destroySubtree(root_node);

    const body_node = try ui.widgets.column(state, root_node, .{
        .width = .fill,
        .height = .fill,
        .gap = state.theme.space.lg,
        .padding = .{
            .left = state.theme.space.lg,
            .right = state.theme.space.lg,
            .top = state.theme.space.lg,
            .bottom = state.theme.space.xl,
        },
        .background = .shell,
        .overflow_y = .scroll,
    });

    self.root_node = root_node;
    self.body_node = body_node;
    try self.rebuild(state);
}

pub fn update(self: *Inspector, state: *ui.Ui, _: panel.Frame) !void {
    if (self.scene_revision != self.scenes.revision()) {
        self.scene_revision = self.scenes.revision();
        try self.rebuild(state);
    }

    const entity = self.selectedEntity() orelse return;
    if (self.entity_name) |*name| {
        const event = try name.update(state, .{
            .max_bytes = 256,
            .placeholder = "Entity name",
        });
        if (event.changed and !std.mem.eql(u8, name.text(), entity.name)) {
            try self.scenes.commitSceneMutation(.{ .rename_entity = .{
                .id = entity.id,
                .name = name.text(),
            } });
            self.scene_revision = self.scenes.revision();
        }
    }

    for (self.components.items) |*component| _ = try component.update(state);
    for (self.fields.items) |*field| {
        if (try field.update(state)) |value| {
            try self.scenes.commitSceneMutation(fieldMutation(
                entity.id,
                field.component_id,
                field.schema.number,
                field.present,
                value,
            ));
            field.present = true;
            self.scene_revision = self.scenes.revision();
        }
    }
}

pub fn unmount(self: *Inspector, state: *ui.Ui) void {
    self.clearContent(state);
    state.destroySubtree(self.root_node);
    self.root_node = ui.invalid_node;
    self.body_node = ui.invalid_node;
}

pub fn root(self: *const Inspector) ui.NodeId {
    return self.root_node;
}

fn rebuild(self: *Inspector, state: *ui.Ui) !void {
    self.clearContent(state);
    const content = try ui.widgets.column(state, self.body_node, .{
        .width = .fill,
        .height = .hug,
        .gap = state.theme.space.lg,
        .background = .transparent,
    });
    errdefer state.destroySubtree(content);
    self.content_node = content;

    const entity = self.selectedEntity() orelse {
        try addEmptyState(state, content, self.scenes.activeDocument() != null);
        return;
    };
    self.entity_name = try ui.TextField.init(self.allocator, state, content, .{
        .text = entity.name,
        .placeholder = "Entity name",
        .max_bytes = 256,
    });
    for (entity.components) |component| try self.addComponent(state, content, component);
}

fn clearContent(self: *Inspector, state: *ui.Ui) void {
    if (self.entity_name) |*name| name.deinit(state);
    self.entity_name = null;
    for (self.fields.items) |*field| field.deinit(state);
    self.fields.clearRetainingCapacity();
    for (self.components.items) |*component| component.deinit(state);
    self.components.clearRetainingCapacity();
    if (self.content_node != ui.invalid_node) state.destroySubtree(self.content_node);
    self.content_node = ui.invalid_node;
}

fn selectedEntity(self: *Inspector) ?*zimp.scene.SceneEntity {
    const id = self.scenes.selectedEntity() orelse return null;
    const loaded = self.scenes.activeDocument() orelse return null;
    const index = loaded.document.entityIndex(id) orelse return null;
    return &loaded.document.entities[index];
}

fn addComponent(self: *Inspector, state: *ui.Ui, parent: ui.NodeId, component: zimp.scene.SceneComponent) !void {
    const schema = self.scenes.componentSchema(component.type_id) orelse {
        try self.addUnknownComponent(state, parent, component);
        return;
    };

    var section = try ui.Collapsible.init(state, parent, schema.display_name, .{});
    errdefer section.deinit(state);
    const body = section.body();
    _ = try ui.widgets.divider(state, body);

    var visible_fields: usize = 0;
    for (schema.fields) |*field_schema| {
        if (field_schema.editor.hidden) continue;
        visible_fields += 1;
        const field_index = component.fieldIndex(field_schema.number);
        const value = if (field_index) |index| component.fields[index].value else field_schema.default_value;
        var field = try InspectorField.init(
            self.allocator,
            state,
            body,
            component.type_id,
            field_schema,
            value,
            field_index != null,
        );
        errdefer field.deinit(state);
        try self.fields.append(self.allocator, field);
    }

    if (visible_fields == 0) {
        _ = try ui.widgets.text(state, body, "No editable properties", .{
            .width = .fill,
            .height = .{ .px = 24 },
            .padding = .{ .top = state.theme.space.sm },
            .color = .text_muted,
            .size = 11,
        });
    }
    try self.components.append(self.allocator, section);
}

fn addUnknownComponent(self: *Inspector, state: *ui.Ui, parent: ui.NodeId, component: zimp.scene.SceneComponent) !void {
    var section = try ui.Collapsible.init(state, parent, "Unknown component", .{
        .surface = .panel_soft,
        .border = .warning_soft,
        .title_color = .warning,
    });
    errdefer section.deinit(state);
    const id_text = component.type_id.toString();
    _ = try ui.widgets.text(state, section.body(), &id_text, .{
        .width = .fill,
        .height = .{ .px = 18 },
        .color = .text_muted,
        .size = 10,
    });
    try self.components.append(self.allocator, section);
}

fn addEmptyState(state: *ui.Ui, parent: ui.NodeId, has_scene: bool) !void {
    const card = try ui.widgets.card(state, parent, .{
        .gap = state.theme.space.sm,
        .padding = .{
            .left = state.theme.space.lg,
            .right = state.theme.space.lg,
            .top = state.theme.space.md,
            .bottom = state.theme.space.md,
        },
        .surface = .panel_soft,
        .border = .stroke_soft,
    });
    _ = try ui.widgets.text(state, card, if (has_scene) "Nothing selected" else "No scene loaded", .{
        .width = .fill,
        .height = .{ .px = 24 },
        .color = .text_dim,
        .size = 13,
    });
    _ = try ui.widgets.text(state, card, if (has_scene) "Select an entity in the Scene panel to inspect and edit it." else "Open a scene to inspect its entities.", .{
        .width = .fill,
        .height = .{ .px = 20 },
        .color = .text_muted,
        .size = 11,
    });
}

fn fieldMutation(
    entity_id: zimp.SceneEntityId,
    component_id: zimp.ComponentTypeId,
    field_number: u32,
    present: bool,
    value: Value,
) SceneMutation {
    return if (present)
        .{ .set_field = .{
            .entity_id = entity_id,
            .type_id = component_id,
            .field_number = field_number,
            .value = value,
        } }
    else
        .{ .add_field = .{
            .entity_id = entity_id,
            .type_id = component_id,
            .field_number = field_number,
            .value = value,
        } };
}

test "inspector adds omitted defaults before setting materialized fields" {
    const entity_id = zimp.SceneEntityId.parseComptime("11111111-1111-4111-8111-111111111111");
    const component_id = zimp.ComponentTypeId.parseComptime("22222222-2222-4222-8222-222222222222");

    const add = fieldMutation(entity_id, component_id, 7, false, .{ .f32 = 2.5 });
    try std.testing.expectEqual(std.meta.Tag(SceneMutation).add_field, std.meta.activeTag(add));
    try std.testing.expectEqual(@as(u32, 7), add.add_field.field_number);

    const set = fieldMutation(entity_id, component_id, 7, true, .{ .f32 = 4.5 });
    try std.testing.expectEqual(std.meta.Tag(SceneMutation).set_field, std.meta.activeTag(set));
    try std.testing.expectEqual(@as(f32, 4.5), set.set_field.value.f32);
}
