const std = @import("std");
const ui = @import("zGUI");

const ProjectModel = @import("../../editor/project_model.zig");

pub const AssetTile = struct {
    pub const width: f32 = 112;
    pub const height: f32 = 118;

    pub const Icons = struct {
        folder: ui.TextureHandle,
        file: ui.TextureHandle,
    };

    node: ui.NodeId,

    pub fn init(
        state: *ui.Ui,
        parent: ui.NodeId,
        item: ProjectModel.Item,
        icons: Icons,
        current_path: []const u8,
    ) !AssetTile {
        const node = try ui.widgets.button(state, parent, "", state.theme.style(.{
            .width = .{ .px = width },
            .height = .{ .px = height },
            .padding = .{
                .left = state.theme.space.md,
                .right = state.theme.space.md,
                .top = state.theme.space.md,
                .bottom = state.theme.space.sm,
            },
            .gap = state.theme.space.xxs,
            .direction = .column,
            .background = .transparent,
            .hover_background = .interaction_hover,
            .pressed_background = .accent_hover,
            .border = .transparent,
            .hover_border = .accent_border,
            .pressed_border = .accent_border_strong,
            .border_width = 1,
            .radius = .control,
        }));
        errdefer state.destroySubtree(node);

        const thumbnail = try ui.widgets.row(state, node, .{
            .width = .fill,
            .height = .{ .px = 62 },
            .background = .transparent,
        });
        _ = try ui.widgets.spacer(state, thumbnail);
        _ = try ui.widgets.image(state, thumbnail, .{
            .texture = if (item.kind == .folder) icons.folder else icons.file,
            .style = state.theme.style(.{
                .width = .{ .px = 58 },
                .height = .{ .px = 58 },
                .background = .transparent,
            }),
        });
        _ = try ui.widgets.spacer(state, thumbnail);

        var name_buffer: [16]u8 = undefined;
        var type_buffer: [16]u8 = undefined;
        try centeredLabel(state, node, shortened(std.fs.path.basename(item.path), &name_buffer), .text, 12, 18);
        try centeredLabel(
            state,
            node,
            shortened(if (item.kind == .folder) folderKind(current_path) else fileKind(item.path), &type_buffer),
            .text_muted,
            10,
            13,
        );
        return .{ .node = node };
    }

    pub fn clicked(self: AssetTile, state: *const ui.Ui) bool {
        return state.clicked(self.node);
    }

    pub fn hovered(self: AssetTile, state: *const ui.Ui) bool {
        return state.interaction(self.node).hovered;
    }

    fn centeredLabel(
        state: *ui.Ui,
        parent: ui.NodeId,
        label: []const u8,
        color: ui.ColorRole,
        size: f32,
        label_height: f32,
    ) !void {
        const row = try ui.widgets.row(state, parent, .{
            .width = .fill,
            .height = .{ .px = label_height },
            .background = .transparent,
        });
        _ = try ui.widgets.spacer(state, row);
        _ = try ui.widgets.text(state, row, label, .{
            .width = .hug,
            .height = .fill,
            .color = color,
            .size = size,
        });
        _ = try ui.widgets.spacer(state, row);
    }

    fn fileKind(path: []const u8) []const u8 {
        const extension = std.fs.path.extension(path);
        return if (extension.len == 0) "FILE" else extension[1..];
    }

    fn folderKind(current_path: []const u8) []const u8 {
        return if (current_path.len == 0) "PROJECT FOLDER" else "FOLDER";
    }

    fn shortened(label: []const u8, buffer: *[16]u8) []const u8 {
        if (label.len <= buffer.len) return label;
        @memcpy(buffer[0..13], label[0..13]);
        @memcpy(buffer[13..16], "...");
        return buffer;
    }
};
