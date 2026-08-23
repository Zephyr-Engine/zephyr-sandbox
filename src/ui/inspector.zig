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
const component_menu_width: f32 = 220;
const remove_component_label = "Remove Component";

pub const Icons = struct {
    component_menu: ui.TextureHandle,
};

const ComponentSection = struct {
    collapsible: ui.Collapsible,
    menu_trigger: ui.NodeId,
    component_id: zimp.ComponentTypeId,
};

allocator: std.mem.Allocator,
scenes: *SceneController,
icons: Icons,
root_node: ui.NodeId = ui.invalid_node,
body_node: ui.NodeId = ui.invalid_node,
content_node: ui.NodeId = ui.invalid_node,
entity_name: ?ui.TextField = null,
components: std.ArrayList(ComponentSection) = .empty,
component_menu: ?ui.SelectionList = null,
fields: std.ArrayList(InspectorField) = .empty,
scene_revision: u64,
component_id: ?zimp.ComponentTypeId = null,

pub const Dependencies = struct {
    allocator: std.mem.Allocator,
    scenes: *SceneController,
    icons: Icons,
};

pub fn init(dependencies: Dependencies) Inspector {
    return .{
        .allocator = dependencies.allocator,
        .scenes = dependencies.scenes,
        .icons = dependencies.icons,
        .scene_revision = dependencies.scenes.revision(),
    };
}

pub fn deinit(self: *Inspector) void {
    self.components.deinit(self.allocator);
    self.fields.deinit(self.allocator);
}

pub fn mount(self: *Inspector, state: *ui.Ui, parent: ui.NodeId, _: panel.Services) !void {
    const root_node = try ui.widgets.surface(state, parent, .{
        .width = .fill,
        .height = .fill,
        .direction = .absolute,
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
    self.component_menu = try ui.SelectionList.init(self.allocator, state, root_node);
    errdefer {
        self.component_menu.?.deinit(state);
        self.component_menu = null;
    }

    try self.component_menu.?.setItems(state, &.{remove_component_label});

    const remove_component_item = self.component_menu.?.item_nodes.items[0];
    var remove_component_style = state.nodeStyle(remove_component_item) orelse return error.InvalidNode;
    remove_component_style.foreground = state.theme.color(.danger);

    try state.setStyle(remove_component_item, remove_component_style);
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

    if (self.component_menu) |*menu| {
        if (try menu.update(state)) |index| {
            switch (index) {
                0 => try self.scenes.commitSceneMutation(.{ .remove_component = .{
                    .entity = entity.id,
                    .type_id = self.component_id.?,
                } }),
                else => {},
            }
        }
    }

    for (self.components.items) |*component| {
        _ = try component.collapsible.update(state);
        if (state.input.hovered == component.menu_trigger) {
            state.requestCursor(.hand);
        }
        if (state.activated(component.menu_trigger)) {
            self.component_id = component.component_id;
            try self.openComponentMenu(state, component.menu_trigger);
        }
    }

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
    if (self.component_menu) |*menu| menu.deinit(state);
    self.component_menu = null;
    state.destroySubtree(self.root_node);
    self.root_node = ui.invalid_node;
    self.body_node = ui.invalid_node;
}

pub fn root(self: *const Inspector) ui.NodeId {
    return self.root_node;
}

pub fn title(self: *const Inspector) []const u8 {
    return if (self.scenes.isDirty()) "● Inspector" else "Inspector";
}

fn rebuild(self: *Inspector, state: *ui.Ui) !void {
    self.clearContent(state);
    const content = try ui.widgets.column(state, self.body_node, .{
        .width = .fill,
        .height = .hug,
        .gap = state.theme.space.md,
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
    for (entity.components) |component| {
        try self.renderComponent(state, content, component);
    }

    const btn = try ui.widgets.button(state, content, "", state.theme.style(.{
        .width = .fill,
        .height = .{ .px = state.theme.metrics.section_header_height },
        .direction = .row,
        .gap = state.theme.space.sm,
        .padding = .{
            .top = state.theme.space.xl,
            .bottom = state.theme.space.xl,
        },
        .background = .accent,
        .border = .accent,
        .border_width = 1,
        .radius = .control,
    }));
    errdefer state.destroySubtree(btn);

    _ = try ui.widgets.surface(state, btn, .{ .width = .fill, .height = .fill });
    _ = try ui.widgets.text(state, btn, "+", .{
        .height = .fill,
        .color = .text,
        .size = 14,
    });
    _ = try ui.widgets.text(state, btn, "Add component", .{
        .height = .fill,
        .color = .text,
        .size = 14,
    });
    _ = try ui.widgets.surface(state, btn, .{ .width = .fill, .height = .fill });
}

fn clearContent(self: *Inspector, state: *ui.Ui) void {
    if (self.component_menu) |*menu| menu.close(state) catch {};
    if (self.entity_name) |*name| name.deinit(state);
    self.entity_name = null;
    for (self.fields.items) |*field| field.deinit(state);
    self.fields.clearRetainingCapacity();
    for (self.components.items) |*component| component.collapsible.deinit(state);
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

fn renderComponent(self: *Inspector, state: *ui.Ui, parent: ui.NodeId, component: zimp.scene.SceneComponent) !void {
    const schema = self.scenes.componentSchema(component.type_id) orelse {
        try self.addUnknownComponent(state, parent, component);
        return;
    };

    var section = try ui.Collapsible.init(state, parent, schema.display_name, .{
        .surface = .panel_soft,
        .border = .stroke_soft,
        .body_gap = state.theme.space.sm,
        .body_padding = .{
            .left = state.theme.space.lg,
            .right = state.theme.space.lg,
            .bottom = state.theme.space.lg,
        },
    });
    errdefer section.deinit(state);
    const menu_trigger = try self.addComponentMenuTrigger(state, &section);
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
    try self.components.append(self.allocator, .{
        .collapsible = section,
        .menu_trigger = menu_trigger,
        .component_id = component.type_id,
    });
}

fn addUnknownComponent(self: *Inspector, state: *ui.Ui, parent: ui.NodeId, component: zimp.scene.SceneComponent) !void {
    var section = try ui.Collapsible.init(state, parent, "Unknown component", .{
        .surface = .panel_soft,
        .border = .warning_soft,
        .title_color = .warning,
    });
    errdefer section.deinit(state);
    const menu_trigger = try self.addComponentMenuTrigger(state, &section);
    const id_text = component.type_id.toString();
    _ = try ui.widgets.text(state, section.body(), &id_text, .{
        .width = .fill,
        .height = .{ .px = 18 },
        .color = .text_muted,
        .size = 10,
    });
    try self.components.append(self.allocator, .{
        .collapsible = section,
        .menu_trigger = menu_trigger,
        .component_id = component.type_id,
    });
}

fn addComponentMenuTrigger(self: *const Inspector, state: *ui.Ui, section: *const ui.Collapsible) !ui.NodeId {
    var header_style = state.nodeStyle(section.header_node) orelse return error.InvalidNode;
    header_style.padding.right = 0;
    try state.setStyle(section.header_node, header_style);

    return ui.widgets.iconButton(state, section.header_node, .{
        .texture = self.icons.component_menu,
        .tint = state.theme.color(.text_muted),
        .style = state.theme.style(.{
            .width = .{ .px = state.theme.metrics.section_header_height },
            .height = .{ .px = state.theme.metrics.section_header_height },
            .background = .transparent,
            .hover_background = .panel_soft,
            .pressed_background = .control,
            .border_width = 0,
            .radius = .control,
        }),
    });
}

fn openComponentMenu(self: *Inspector, state: *ui.Ui, trigger: ui.NodeId) !void {
    const menu = &self.component_menu.?;
    const root_bounds = state.bounds(self.root_node) orelse return;
    const trigger_bounds = state.bounds(trigger) orelse return;
    try menu.show(state, .{
        .x = trigger_bounds.x - root_bounds.x + trigger_bounds.w - component_menu_width,
        .y = trigger_bounds.y - root_bounds.y + trigger_bounds.h,
    });
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
