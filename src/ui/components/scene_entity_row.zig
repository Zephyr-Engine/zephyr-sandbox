const std = @import("std");
const ui = @import("zGUI");
const zimp = @import("zimp");
const zp = @import("zephyr_runtime");

const camera_component_id = zp.ComponentTypeId.parseComptime(zp.components.CameraComponent.schema_meta.id);
const mesh_component_id = zp.ComponentTypeId.parseComptime(zp.components.MeshRenderComponent.schema_meta.id);

pub const SceneEntityRow = struct {
    pub const Icons = struct {
        camera: ui.TextureHandle,
        model: ui.TextureHandle,
    };

    node: ui.NodeId,
    entity_id: zp.SceneEntityId,

    pub fn init(
        state: *ui.Ui,
        parent: ui.NodeId,
        entity: zimp.scene.SceneEntity,
        selected: bool,
        icons: Icons,
    ) !SceneEntityRow {
        const node = try ui.widgets.button(state, parent, "", state.theme.style(.{
            .width = .fill,
            .height = .{ .px = state.theme.metrics.control_height },
            .padding = .{
                .left = state.theme.space.md,
                .right = state.theme.space.lg,
                .top = state.theme.space.sm,
                .bottom = state.theme.space.sm,
            },
            .gap = state.theme.space.lg,
            .direction = .row,
            .background = if (selected) .accent_soft else .transparent,
            .hover_background = .interaction_hover,
            .pressed_background = .accent_pressed,
            .border = if (selected) .accent else .transparent,
            .hover_border = .accent_border,
            .border_width = 1,
            .radius = .control,
        }));
        errdefer state.destroySubtree(node);

        _ = try ui.widgets.image(state, node, .{
            .texture = switch (kind(entity.components)) {
                .camera => icons.camera,
                .model => icons.model,
            },
            .style = state.theme.style(.{
                .width = .{ .px = 20 },
                .height = .{ .px = 20 },
                .background = .transparent,
            }),
            .tint = state.theme.color(if (selected) .icon_selected else .icon),
        });
        _ = try ui.widgets.text(state, node, entity.name, .{
            .width = .fill,
            .height = .fill,
            .padding = .{ .top = state.theme.space.xxs },
            .color = if (selected) .text else .text_muted,
            .size = 13,
        });
        return .{ .node = node, .entity_id = entity.id };
    }

    pub fn clicked(self: SceneEntityRow, state: *const ui.Ui) bool {
        return state.clicked(self.node);
    }

    pub fn hovered(self: SceneEntityRow, state: *const ui.Ui) bool {
        return state.interaction(self.node).hovered;
    }

    const Kind = enum { camera, model };

    fn kind(components: []const zimp.scene.SceneComponent) Kind {
        for (components) |component| {
            if (component.type_id.eql(camera_component_id)) return .camera;
        }
        return .model;
    }
};

test "scene entity row prefers a camera icon over a mesh renderer" {
    const components = [_]zimp.scene.SceneComponent{
        .{ .type_id = mesh_component_id },
        .{ .type_id = camera_component_id },
    };
    try std.testing.expectEqual(SceneEntityRow.Kind.camera, SceneEntityRow.kind(&components));
}
