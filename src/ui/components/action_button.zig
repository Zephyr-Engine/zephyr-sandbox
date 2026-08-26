const ui = @import("zGUI");

const actions = @import("../../editor/actions.zig");

pub const Options = struct {
    texture: ui.TextureHandle,
    style: ui.Style,
    tint: ?ui.Color = null,
    disabled_tint: ?ui.Color = null,
    uv0: ui.Vec2 = .{},
    uv1: ui.Vec2 = .{ .x = 1, .y = 1 },
};

const ActionButton = @This();

node: ui.NodeId,
action: actions.ActionId,
registry: *actions.Registry,
texture: ui.TextureHandle,
tint: ui.Color,
disabled_tint: ui.Color,
uv0: ui.Vec2,
uv1: ui.Vec2,
last_enabled: ?bool = null,

pub fn create(
    state: *ui.Ui,
    parent: ui.NodeId,
    registry: *actions.Registry,
    comptime action_id: actions.ActionId,
    options: Options,
) !ActionButton {
    const tint = options.tint orelse state.theme.color(.icon);
    const disabled_tint = options.disabled_tint orelse state.theme.color(.icon_disabled);
    const node = try ui.widgets.iconButton(state, parent, .{
        .texture = options.texture,
        .style = options.style,
        .uv0 = options.uv0,
        .uv1 = options.uv1,
        .tint = tint,
        .on_activate = registry.handler(action_id),
    });
    return .{
        .node = node,
        .action = action_id,
        .registry = registry,
        .texture = options.texture,
        .tint = tint,
        .disabled_tint = disabled_tint,
        .uv0 = options.uv0,
        .uv1 = options.uv1,
    };
}

pub fn sync(self: *ActionButton, state: *ui.Ui) !void {
    const enabled = self.registry.enabled(self.action);
    if (self.last_enabled != null and self.last_enabled.? == enabled) return;
    try state.setInteractive(self.node, enabled);
    try state.setImage(self.node, .{
        .texture = self.texture,
        .uv0 = self.uv0,
        .uv1 = self.uv1,
        .tint = if (enabled) self.tint else self.disabled_tint,
    });
    self.last_enabled = enabled;
}

test "action button mirrors registry enablement" {
    const std = @import("std");
    const action_id = actions.actionId("test.toggle");
    const State = struct {
        enabled: bool = true,

        fn execute(self: *@This()) !void {
            _ = self;
        }

        fn isEnabled(self: *@This()) bool {
            return self.enabled;
        }
    };

    var action_state: State = .{};
    var registry = actions.Registry.init(std.testing.allocator);
    defer registry.deinit();
    try registry.register(action_id, actions.Action.bind("Toggle", &action_state, State.execute).withEnabled(State.isEnabled));

    var state = try ui.Ui.init(std.testing.allocator);
    defer state.deinit();
    var button = try ActionButton.create(&state, state.rootNode(), &registry, action_id, .{
        .texture = .none,
        .style = .{},
    });
    try button.sync(&state);
    try std.testing.expect(state.tree.get(button.node).?.flags.interactive);

    action_state.enabled = false;
    try button.sync(&state);
    try std.testing.expect(!state.tree.get(button.node).?.flags.interactive);
    try std.testing.expectEqual(button.disabled_tint, state.tree.get(button.node).?.image.?.tint);
}
