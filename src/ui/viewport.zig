const std = @import("std");
const ui = @import("zGUI");

const actions = @import("../editor/actions.zig");
const ActionButton = @import("action_button.zig");
const panel = @import("panel.zig");

pub const panel_id = panel.id("editor.viewport");
pub const descriptor: panel.Descriptor = .{
    .id = panel_id,
    .title = "Viewport",
    .min_size = .{ .x = 240, .y = 240 },
};

pub const Icons = struct {
    play: ui.TextureHandle,
    pause: ui.TextureHandle,
    stop: ui.TextureHandle,
};

const Viewport = @This();

texture: ui.TextureHandle,
icons: Icons,
root_node: ui.NodeId = ui.invalid_node,
image: ui.NodeId = ui.invalid_node,
stats_card: ui.NodeId = ui.invalid_node,
stats_label: ui.NodeId = ui.invalid_node,
action_buttons: [3]ActionButton = undefined,
stats_text: [128]u8 = undefined,
stats_visible: bool = false,

pub fn init(texture: ui.TextureHandle, icons: Icons) Viewport {
    return .{ .texture = texture, .icons = icons };
}

pub fn mount(self: *Viewport, state: *ui.Ui, parent: ui.NodeId, services: panel.Services) !void {
    const root_node = try ui.widgets.surface(state, parent, .{
        .width = .fill,
        .height = .fill,
        .direction = .absolute,
        .background = .viewport,
    });
    errdefer state.destroySubtree(root_node);

    const image = try ui.widgets.image(state, root_node, .{
        .texture = self.texture,
        .style = state.theme.style(.{
            .width = .fill,
            .height = .fill,
            .background = .viewport,
            .border = .stroke,
            .border_width = 1,
            .radius = .viewport,
        }),
        .uv0 = .{ .x = 0, .y = 1 },
        .uv1 = .{ .x = 1, .y = 0 },
        .interactive = false,
    });

    const toolbar_row = try ui.widgets.row(state, root_node, .{
        .width = .fill,
        .height = .{ .px = 52 },
        .padding = .{ .top = 9 },
        .background = .transparent,
    });
    _ = try ui.widgets.spacer(state, toolbar_row);
    const toolbar = try ui.widgets.row(state, toolbar_row, .{
        .width = .{ .px = 98 },
        .height = .{ .px = 36 },
        .gap = 2,
        .padding = .{ .left = 5, .right = 5, .top = 4, .bottom = 4 },
        .background = .shell,
        .border = .stroke_soft,
        .border_width = 1,
        .radius = .pill,
    });
    var toolbar_style = state.nodeStyle(toolbar).?;
    toolbar_style.background = ui.Color.rgba(17, 18, 22, 232);
    toolbar_style.border_color = ui.Color.rgba(255, 255, 255, 24);
    try state.setStyle(toolbar, toolbar_style);
    _ = try ui.widgets.spacer(state, toolbar_row);

    const play_button = try controlButton(
        state,
        toolbar,
        services.actions,
        actions.ids.play,
        self.icons.play,
    );
    const pause_button = try controlButton(
        state,
        toolbar,
        services.actions,
        actions.ids.pause,
        self.icons.pause,
    );
    const stop_button = try controlButton(
        state,
        toolbar,
        services.actions,
        actions.ids.stop,
        self.icons.stop,
    );

    const stats_row = try ui.widgets.row(state, root_node, .{
        .width = .fill,
        .height = .{ .px = 82 },
        .padding = .{ .top = 10, .right = 10 },
        .background = .transparent,
    });
    _ = try ui.widgets.spacer(state, stats_row);
    const stats_card = try ui.widgets.surface(state, stats_row, .{
        .width = .{ .px = 120 },
        .height = .{ .px = 58 },
        .padding = .{ .left = 10, .right = 10, .top = 8, .bottom = 8 },
        .background = .panel_soft,
        .border = .stroke_soft,
        .border_width = 1,
        .radius = .control,
    });
    const stats_label = try ui.widgets.text(state, stats_card, "", .{
        .width = .fill,
        .height = .fill,
        .color = .text,
        .size = state.theme.font.small,
    });
    var card_style = state.nodeStyle(stats_card).?;
    card_style.background = ui.Color.rgba(30, 30, 36, 220);
    try state.setStyle(stats_card, card_style);
    try state.setVisible(stats_card, false);

    self.root_node = root_node;
    self.image = image;
    self.stats_card = stats_card;
    self.stats_label = stats_label;
    self.action_buttons = .{ play_button, pause_button, stop_button };
    self.stats_visible = false;
}

pub fn update(self: *Viewport, state: *ui.Ui, frame: panel.Frame) !void {
    for (&self.action_buttons) |*button| try button.sync(state);

    const snapshot = frame.debug_stats orelse {
        if (self.stats_visible) {
            try state.setVisible(self.stats_card, false);
            self.stats_visible = false;
        }
        return;
    };

    const text = if (snapshot.gpu_time_ms) |gpu_time_ms|
        std.fmt.bufPrint(&self.stats_text, "{d:.0} FPS  {d:.2} ms\nCPU  {d:.2} ms\nGPU  {d:.2} ms", .{
            snapshot.fps,
            snapshot.frame_time_ms,
            snapshot.cpu_time_ms,
            gpu_time_ms,
        }) catch return error.StatsBufferTooSmall
    else
        std.fmt.bufPrint(&self.stats_text, "{d:.0} FPS  {d:.2} ms\nCPU  {d:.2} ms\nGPU  --", .{
            snapshot.fps,
            snapshot.frame_time_ms,
            snapshot.cpu_time_ms,
        }) catch return error.StatsBufferTooSmall;

    if (!self.stats_visible) {
        try state.setVisible(self.stats_card, true);
        self.stats_visible = true;
    }
    try state.setText(self.stats_label, text);
}

pub fn unmount(self: *Viewport, state: *ui.Ui) void {
    state.destroySubtree(self.root_node);
    self.root_node = ui.invalid_node;
    self.image = ui.invalid_node;
    self.stats_card = ui.invalid_node;
    self.stats_label = ui.invalid_node;
    self.stats_visible = false;
}

pub fn root(self: *const Viewport) ui.NodeId {
    return self.root_node;
}

fn controlButton(
    state: *ui.Ui,
    parent: ui.NodeId,
    registry: *actions.Registry,
    comptime action_id: actions.ActionId,
    icon: ui.TextureHandle,
) !ActionButton {
    var button = try ActionButton.create(state, parent, registry, action_id, .{
        .texture = icon,
        .style = state.theme.style(.{
            .width = .{ .px = 28 },
            .height = .{ .px = 28 },
            .padding = .{ .left = 4, .right = 4, .top = 4, .bottom = 4 },
            .background = .transparent,
            .border = .transparent,
            .radius = .control,
        }),
    });
    var style = state.nodeStyle(button.node).?;
    style.hover_background = ui.Color.rgba(255, 255, 255, 18);
    style.pressed_background = ui.Color.rgba(255, 255, 255, 30);
    try state.setStyle(button.node, style);
    try button.sync(state);
    return button;
}
