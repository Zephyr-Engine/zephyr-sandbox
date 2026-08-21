const std = @import("std");
const ui = @import("zGUI");
const zimp = @import("zimp");

const EditorHints = zimp.scene.EditorFieldHints;

pub const TextField = struct {
    field: ui.TextField,

    pub fn init(
        allocator: std.mem.Allocator,
        state: *ui.Ui,
        parent: ui.NodeId,
        value: []const u8,
        hints: EditorHints,
    ) !TextField {
        return .{ .field = try ui.TextField.init(allocator, state, parent, options(value, hints)) };
    }

    pub fn deinit(self: *TextField, state: *ui.Ui) void {
        self.field.deinit(state);
    }

    pub fn update(self: *TextField, state: *ui.Ui, hints: EditorHints) !bool {
        const result = try self.field.update(state, options(null, hints));
        return result.changed;
    }

    fn options(text: ?[]const u8, hints: EditorHints) ui.TextFieldOptions {
        return .{
            .text = text orelse "",
            .max_bytes = 4096,
            .multiline = hints.multiline,
            .height = if (hints.multiline) 78 else null,
        };
    }
};
