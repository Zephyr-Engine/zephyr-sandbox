const ui = @import("zGUI");

const actions = @import("../../editor/actions.zig");
const ActionButton = @import("action_button.zig");

pub const ViewportToolbar = struct {
    pub const Icons = struct {
        play: ui.TextureHandle,
        pause: ui.TextureHandle,
        stop: ui.TextureHandle,
    };

    buttons: [3]ActionButton,

    pub fn init(
        state: *ui.Ui,
        parent: ui.NodeId,
        registry: *actions.Registry,
        icons: Icons,
    ) !ViewportToolbar {
        const control_size = state.theme.metrics.compact_control_height;
        const gap = state.theme.space.xxs;
        const padding = state.theme.space.xs;
        const placement = try ui.widgets.row(state, parent, .{
            .width = .fill,
            .height = .{ .px = 52 },
            .padding = .{ .top = state.theme.space.lg },
            .background = .transparent,
        });
        errdefer state.destroySubtree(placement);
        _ = try ui.widgets.spacer(state, placement);
        const toolbar = try ui.widgets.row(state, placement, .{
            .width = .{ .px = control_size * 3 + gap * 2 + padding * 2 },
            .height = .{ .px = control_size + padding * 2 },
            .gap = gap,
            .padding = ui.Edges.all(padding),
            .background = .overlay_soft,
            .border = .overlay_stroke,
            .border_width = 1,
            .radius = .pill,
        });
        _ = try ui.widgets.spacer(state, placement);

        var result = ViewportToolbar{ .buttons = .{
            try controlButton(state, toolbar, registry, actions.ids.play, icons.play),
            try controlButton(state, toolbar, registry, actions.ids.pause, icons.pause),
            try controlButton(state, toolbar, registry, actions.ids.stop, icons.stop),
        } };
        try result.update(state);
        return result;
    }

    pub fn update(self: *ViewportToolbar, state: *ui.Ui) !void {
        for (&self.buttons) |*button| try button.sync(state);
    }

    fn controlButton(
        state: *ui.Ui,
        parent: ui.NodeId,
        registry: *actions.Registry,
        comptime action_id: actions.ActionId,
        icon: ui.TextureHandle,
    ) !ActionButton {
        return ActionButton.create(state, parent, registry, action_id, .{
            .texture = icon,
            .style = state.theme.style(.{
                .width = .{ .px = state.theme.metrics.compact_control_height },
                .height = .{ .px = state.theme.metrics.compact_control_height },
                .padding = ui.Edges.all(state.theme.space.xs),
                .background = .transparent,
                .hover_background = .interaction_hover,
                .pressed_background = .interaction_pressed,
                .border = .transparent,
                .radius = .control,
            }),
        });
    }
};
