const std = @import("std");
const ui = @import("zGUI");
const zimp = @import("zimp");

const numeric = @import("numeric_field.zig");
const EditorHints = zimp.scene.EditorFieldHints;
const Value = zimp.scene.Value;

pub const VectorField = struct {
    fields: [4]?ui.NumericField = .{ null, null, null, null },
    values: [4]f32 = .{ 0, 0, 0, 0 },
    len: usize,

    pub fn init(
        allocator: std.mem.Allocator,
        state: *ui.Ui,
        parent: ui.NodeId,
        values: []const f32,
        hints: EditorHints,
    ) !VectorField {
        var self = VectorField{ .len = values.len };
        errdefer self.deinit(state);
        const host = try ui.widgets.row(state, parent, .{
            .width = .fill,
            .height = .{ .px = state.theme.metrics.control_height },
            .gap = state.theme.space.sm,
        });
        for (values, 0..) |component_value, index| {
            self.values[index] = component_value;
            self.fields[index] = try ui.NumericField.initF32(allocator, state, host, component_value, options(hints, index));
        }
        return self;
    }

    pub fn deinit(self: *VectorField, state: *ui.Ui) void {
        for (&self.fields) |*field| if (field.*) |*number| number.deinit(state);
    }

    pub fn update(self: *VectorField, state: *ui.Ui, hints: EditorHints) !bool {
        var changed = false;
        for (0..self.len) |index| {
            const before = self.values[index];
            const result = try self.fields[index].?.updateF32(state, &self.values[index], options(hints, index));
            if (result.changed and !result.committed) {
                if (numeric.previewF32(self.fields[index].?.text.text(), hints)) |preview| self.values[index] = preview;
            }
            changed = changed or self.values[index] != before;
        }
        return changed;
    }

    pub fn value(self: *const VectorField) Value {
        return switch (self.len) {
            2 => .{ .vec2 = self.values[0..2].* },
            3 => .{ .vec3 = self.values[0..3].* },
            4 => .{ .quat = self.values },
            else => unreachable,
        };
    }

    fn options(hints: EditorHints, index: usize) ui.NumericOptions {
        var result = numeric.options(hints, false);
        result.trailing_label = componentLabel(index);
        result.trailing_label_color = componentColor(index);
        return result;
    }

    fn componentLabel(index: usize) []const u8 {
        return switch (index) {
            0 => "X",
            1 => "Y",
            2 => "Z",
            3 => "W",
            else => "",
        };
    }

    fn componentColor(index: usize) ui.ColorRole {
        return switch (index) {
            0 => .danger,
            1 => .success,
            2 => .accent,
            3 => .warning,
            else => .text_muted,
        };
    }
};
