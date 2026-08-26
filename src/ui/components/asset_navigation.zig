const ui = @import("zGUI");

pub const AssetNavigation = struct {
    back_button: ui.NodeId,
    forward_button: ui.NodeId,
    path_label: ui.NodeId,

    pub fn init(state: *ui.Ui, parent: ui.NodeId) !AssetNavigation {
        const root = try ui.widgets.row(state, parent, .{
            .width = .fill,
            .height = .{ .px = state.theme.metrics.section_header_height },
            .gap = state.theme.space.xs,
            .padding = .{
                .left = state.theme.space.lg,
                .right = state.theme.space.xl,
                .top = state.theme.space.sm,
                .bottom = state.theme.space.sm,
            },
            .background = .shell,
        });
        errdefer state.destroySubtree(root);

        const back_button = try button(state, root, "‹");
        const forward_button = try button(state, root, "›");
        _ = try ui.widgets.text(state, root, "PROJECT ASSETS", .{
            .width = .{ .px = 102 },
            .height = .fill,
            .padding = .{ .left = state.theme.space.sm, .top = state.theme.space.sm },
            .color = .text_dim,
            .size = 11,
        });
        const path_label = try ui.widgets.text(state, root, "", .{
            .width = .fill,
            .height = .fill,
            .padding = .{ .left = state.theme.space.xxs, .top = state.theme.space.sm },
            .size = 12,
            .color = .text_muted,
        });
        return .{
            .back_button = back_button,
            .forward_button = forward_button,
            .path_label = path_label,
        };
    }

    pub fn sync(self: *AssetNavigation, state: *ui.Ui, path: []const u8, can_go_back: bool, can_go_forward: bool) !void {
        try state.setText(self.path_label, if (path.len == 0) "Project folders" else path);
        try syncButton(state, self.back_button, can_go_back);
        try syncButton(state, self.forward_button, can_go_forward);
    }

    pub fn backClicked(self: *const AssetNavigation, state: *const ui.Ui) bool {
        return state.clicked(self.back_button);
    }

    pub fn forwardClicked(self: *const AssetNavigation, state: *const ui.Ui) bool {
        return state.clicked(self.forward_button);
    }

    pub fn hovered(self: *const AssetNavigation, state: *const ui.Ui) bool {
        return state.interaction(self.back_button).hovered or state.interaction(self.forward_button).hovered;
    }

    fn button(state: *ui.Ui, parent: ui.NodeId, label: []const u8) !ui.NodeId {
        return ui.widgets.button(state, parent, label, state.theme.style(.{
            .width = .{ .px = 22 },
            .height = .{ .px = state.theme.metrics.compact_control_height },
            .padding = .{ .left = state.theme.space.sm, .top = state.theme.space.xs },
            .background = .transparent,
            .hover_background = .interaction_hover,
            .pressed_background = .accent_hover,
            .border = .transparent,
            .radius = .control,
            .font_size = 14,
        }));
    }

    fn syncButton(state: *ui.Ui, node: ui.NodeId, enabled: bool) !void {
        var style = state.nodeStyle(node).?;
        style.foreground = state.theme.color(if (enabled) .text_dim else .text_disabled);
        style.hover_background = if (enabled) state.theme.color(.interaction_hover) else null;
        style.pressed_background = if (enabled) state.theme.color(.accent_hover) else null;
        try state.setStyle(node, style);
        try state.setInteractive(node, enabled);
    }
};
