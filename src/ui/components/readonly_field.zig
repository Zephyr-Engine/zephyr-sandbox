const std = @import("std");
const ui = @import("zGUI");
const zimp = @import("zimp");

const Value = zimp.scene.Value;

pub const ReadonlyField = struct {
    root: ui.NodeId,

    pub fn init(state: *ui.Ui, parent: ui.NodeId, value: Value) !ReadonlyField {
        var buffer: [160]u8 = undefined;
        const text = formatValue(&buffer, value);
        const root = try ui.widgets.surface(state, parent, .{
            .width = .fill,
            .height = .{ .px = state.theme.metrics.control_height },
            .padding = .{
                .left = state.theme.space.lg,
                .right = state.theme.space.lg,
                .top = state.centeredTextTop(state.theme.metrics.control_height, state.theme.font.tiny),
            },
            .background = .panel_soft,
            .border = .stroke_soft,
            .border_width = 1,
            .radius = .control,
        });
        errdefer state.destroySubtree(root);
        _ = try ui.widgets.text(state, root, text, .{
            .width = .fill,
            .height = .fill,
            .color = .text_muted,
            .size = state.theme.font.tiny,
        });
        return .{ .root = root };
    }

    pub fn deinit(self: *ReadonlyField, state: *ui.Ui) void {
        state.destroySubtree(self.root);
    }

    fn formatValue(buffer: []u8, value: Value) []const u8 {
        return switch (value) {
            .bool => |v| std.fmt.bufPrint(buffer, "{}", .{v}) catch "",
            .i32 => |v| std.fmt.bufPrint(buffer, "{d}", .{v}) catch "",
            .u32 => |v| std.fmt.bufPrint(buffer, "{d}", .{v}) catch "",
            .f32 => |v| std.fmt.bufPrint(buffer, "{d}", .{v}) catch "",
            .string => |v| v,
            .vec2 => |v| std.fmt.bufPrint(buffer, "{d}, {d}", .{ v[0], v[1] }) catch "",
            .vec3 => |v| std.fmt.bufPrint(buffer, "{d}, {d}, {d}", .{ v[0], v[1], v[2] }) catch "",
            .quat => |v| std.fmt.bufPrint(buffer, "{d}, {d}, {d}, {d}", .{ v[0], v[1], v[2], v[3] }) catch "",
            .asset_ref => |v| &v.toString(),
            .entity_ref => |v| &v.toString(),
            .none => "—",
        };
    }
};
