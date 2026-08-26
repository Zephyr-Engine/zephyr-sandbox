const std = @import("std");
const ui = @import("zGUI");
const zimp = @import("zimp");

const ReferenceField = @import("reference_field.zig").ReferenceField;
const ReadonlyField = @import("readonly_field.zig").ReadonlyField;
const BooleanField = @import("boolean_field.zig").BooleanField;
const VectorField = @import("vector_field.zig").VectorField;
const EnumField = @import("enum_field.zig").EnumField;
const TextField = @import("text_field.zig").TextField;
const numeric = @import("numeric_field.zig");

const EditorHints = zimp.scene.EditorFieldHints;
const FieldSchema = zimp.scene.FieldSchema;
const Value = zimp.scene.Value;

pub const InspectorField = struct {
    root: ui.NodeId,
    component_id: zimp.ComponentTypeId,
    schema: *const FieldSchema,
    present: bool,
    control: Control,

    const Control = union(enum) {
        boolean: BooleanField,
        int: numeric.IntField,
        uint: numeric.UintField,
        float: numeric.FloatField,
        text: TextField,
        vector: VectorField,
        reference: ReferenceField,
        enumeration: EnumField,
        readonly: ReadonlyField,
    };

    pub fn init(
        allocator: std.mem.Allocator,
        state: *ui.Ui,
        parent: ui.NodeId,
        component_id: zimp.ComponentTypeId,
        schema: *const FieldSchema,
        value: Value,
        present: bool,
    ) !InspectorField {
        const vector = switch (schema.kind) {
            .vec2, .vec3, .quat => true,
            else => false,
        };
        const root = try ui.widgets.surface(state, parent, .{
            .width = .fill,
            .height = .hug,
            .direction = .row,
            .gap = state.theme.space.lg,
            .padding = .{ .top = state.theme.space.xxs, .bottom = state.theme.space.xxs },
        });
        errdefer state.destroySubtree(root);

        _ = try ui.widgets.text(state, root, schema.display_name, .{
            .width = .{ .percent = if (vector) 0.18 else 0.37 },
            .height = .{ .px = state.theme.metrics.control_height },
            .padding = .{
                .left = 1,
                .top = state.centeredTextTop(state.theme.metrics.control_height, state.theme.font.small),
            },
            .color = if (schema.editor.readonly) .text_muted else .text_dim,
            .size = state.theme.font.small,
        });

        return .{
            .root = root,
            .component_id = component_id,
            .schema = schema,
            .present = present,
            .control = try initControl(allocator, state, root, schema, value),
        };
    }

    pub fn deinit(self: *InspectorField, state: *ui.Ui) void {
        switch (self.control) {
            inline else => |*control| control.deinit(state),
        }
        state.destroySubtree(self.root);
    }

    pub fn update(self: *InspectorField, state: *ui.Ui) !?Value {
        return switch (self.control) {
            .boolean => |*control| if (try control.update(state)) Value{ .bool = control.value } else null,
            .int => |*control| if (try control.update(state, self.schema.editor)) Value{ .i32 = control.value } else null,
            .uint => |*control| if (try control.update(state, self.schema.editor)) Value{ .u32 = control.value } else null,
            .float => |*control| if (try control.update(state, self.schema.editor)) Value{ .f32 = control.value } else null,
            .text => |*control| if (try control.update(state, self.schema.editor)) Value{ .string = control.field.text() } else null,
            .vector => |*control| if (try control.update(state, self.schema.editor)) control.value() else null,
            .reference => |*control| try control.update(state),
            .enumeration => |*control| if (try control.update(state)) Value{ .u32 = control.value } else null,
            .readonly => null,
        };
    }

    fn initControl(
        allocator: std.mem.Allocator,
        state: *ui.Ui,
        parent: ui.NodeId,
        schema: *const FieldSchema,
        value: Value,
    ) !Control {
        if (schema.editor.readonly) return .{ .readonly = try ReadonlyField.init(state, parent, value) };

        const hints: EditorHints = schema.editor;
        return switch (schema.kind) {
            .bool => .{ .boolean = try BooleanField.init(state, parent, value.bool) },
            .i32 => .{ .int = try numeric.IntField.init(allocator, state, parent, value.i32, hints) },
            .u32 => .{ .uint = try numeric.UintField.init(allocator, state, parent, value.u32, hints) },
            .f32 => .{ .float = try numeric.FloatField.init(allocator, state, parent, value.f32, hints) },
            .string => .{ .text = try TextField.init(allocator, state, parent, value.string, hints) },
            .vec2 => .{ .vector = try VectorField.init(allocator, state, parent, value.vec2[0..], hints) },
            .vec3 => .{ .vector = try VectorField.init(allocator, state, parent, value.vec3[0..], hints) },
            .quat => .{ .vector = try VectorField.init(allocator, state, parent, value.quat[0..], hints) },
            .asset_ref => .{ .reference = try ReferenceField.initAsset(allocator, state, parent, value.asset_ref) },
            .entity_ref => .{ .reference = try ReferenceField.initEntity(allocator, state, parent, value.entity_ref) },
            .enum_ref => |enum_schema| .{ .enumeration = try EnumField.init(state, parent, value.u32, enum_schema) },
        };
    }
};
