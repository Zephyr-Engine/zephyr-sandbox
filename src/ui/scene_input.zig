const ui = @import("zGUI");
const zp = @import("zephyr_runtime");

const SceneInputCapture = @This();

active: bool = false,

pub fn reset(self: *SceneInputCapture) void {
    self.active = false;
}

pub fn accepts(self: *SceneInputCapture, event: zp.ZEvent, viewport_rect: ui.Rect, mouse_pos: ui.Vec2, ui_owns_mouse: bool) bool {
    return self.acceptsWithUi(event, viewport_rect, mouse_pos, .{ .wants_mouse = ui_owns_mouse });
}

pub fn acceptsWithUi(self: *SceneInputCapture, event: zp.ZEvent, viewport_rect: ui.Rect, mouse_pos: ui.Vec2, ui_capture: ui.InputCapture) bool {
    const scene_target = viewport_rect.contains(mouse_pos) and !ui_capture.wants_mouse;
    return switch (event) {
        .MouseMove => true,
        .MousePressed => pressed: {
            if (scene_target) {
                self.active = true;
                break :pressed true;
            }
            break :pressed false;
        },
        .MouseReleased => released: {
            const was_active = self.active;
            self.active = false;
            break :released was_active or scene_target;
        },
        .MouseScroll => self.active or scene_target,
        .KeyReleased => !ui_capture.wants_keyboard,
        .KeyPressed, .KeyRepeated => !ui_capture.wants_keyboard and (self.active or scene_target),
        .WindowResize, .FramebufferResize, .ContentScaleChange, .WindowClose => true,
        .CharInput => false,
    };
}

pub fn processSceneEvents(
    self: *SceneInputCapture,
    input: *zp.Input,
    runtime_events: []const zp.ZEvent,
    viewport_rect: ui.Rect,
    mouse_pos: ui.Vec2,
    ui_capture: ui.InputCapture,
) void {
    for (runtime_events) |event| {
        if (self.acceptsWithUi(event, viewport_rect, mouse_pos, ui_capture)) {
            input.applyEvent(event);
        }
    }
}

const testing = @import("std").testing;

const inside_viewport: ui.Rect = .{ .x = 0, .y = 0, .w = 100, .h = 100 };
const inside_pos: ui.Vec2 = .{ .x = 50, .y = 50 };
const outside_pos: ui.Vec2 = .{ .x = 500, .y = 500 };

test "mouse move is always accepted" {
    var capture: SceneInputCapture = .{};
    try testing.expect(capture.accepts(.{ .MouseMove = .{ .x = 0, .y = 0 } }, inside_viewport, outside_pos, true));
}

test "char input is never accepted" {
    var capture: SceneInputCapture = .{};
    capture.active = true;
    try testing.expect(!capture.accepts(.{ .CharInput = 'a' }, inside_viewport, inside_pos, false));
}

test "window and framebuffer events are always accepted" {
    var capture: SceneInputCapture = .{};
    try testing.expect(capture.accepts(.WindowClose, inside_viewport, outside_pos, true));
    try testing.expect(capture.accepts(.{ .WindowResize = .{ .width = 1, .height = 1 } }, inside_viewport, outside_pos, true));
    try testing.expect(capture.accepts(.{ .FramebufferResize = .{ .width = 1, .height = 1 } }, inside_viewport, outside_pos, true));
    try testing.expect(capture.accepts(.{ .ContentScaleChange = .{ .x = 1, .y = 1 } }, inside_viewport, outside_pos, true));
}

test "key released is always accepted" {
    var capture: SceneInputCapture = .{};
    try testing.expect(capture.accepts(.{ .KeyReleased = .A }, inside_viewport, outside_pos, true));
}

test "mouse press over the scene claims capture and is accepted" {
    var capture: SceneInputCapture = .{};
    try testing.expect(capture.accepts(.{ .MousePressed = .Left }, inside_viewport, inside_pos, false));
    try testing.expect(capture.active);
}

test "mouse press outside the scene or over ui is rejected" {
    var capture: SceneInputCapture = .{};
    try testing.expect(!capture.accepts(.{ .MousePressed = .Left }, inside_viewport, outside_pos, false));
    try testing.expect(!capture.active);

    try testing.expect(!capture.accepts(.{ .MousePressed = .Left }, inside_viewport, inside_pos, true));
    try testing.expect(!capture.active);
}

test "mouse release while active is accepted and clears capture" {
    var capture: SceneInputCapture = .{ .active = true };
    try testing.expect(capture.accepts(.{ .MouseReleased = .Left }, inside_viewport, outside_pos, true));
    try testing.expect(!capture.active);
}

test "mouse release over the scene while inactive is still accepted" {
    var capture: SceneInputCapture = .{};
    try testing.expect(capture.accepts(.{ .MouseReleased = .Left }, inside_viewport, inside_pos, false));
    try testing.expect(!capture.active);
}

test "mouse release outside the scene while inactive is rejected" {
    var capture: SceneInputCapture = .{};
    try testing.expect(!capture.accepts(.{ .MouseReleased = .Left }, inside_viewport, outside_pos, true));
}

test "mouse scroll and key presses follow the active/scene-target rule" {
    var capture: SceneInputCapture = .{ .active = true };
    try testing.expect(capture.accepts(.{ .MouseScroll = .{ .x = 0, .y = 1 } }, inside_viewport, outside_pos, true));
    try testing.expect(capture.accepts(.{ .KeyPressed = .A }, inside_viewport, outside_pos, true));
    try testing.expect(capture.accepts(.{ .KeyRepeated = .A }, inside_viewport, outside_pos, true));

    capture.active = false;
    try testing.expect(!capture.accepts(.{ .MouseScroll = .{ .x = 0, .y = 1 } }, inside_viewport, outside_pos, true));
    try testing.expect(!capture.accepts(.{ .KeyPressed = .A }, inside_viewport, outside_pos, true));
    try testing.expect(!capture.accepts(.{ .KeyRepeated = .A }, inside_viewport, outside_pos, true));

    try testing.expect(capture.accepts(.{ .MouseScroll = .{ .x = 0, .y = 1 } }, inside_viewport, inside_pos, false));
    try testing.expect(capture.accepts(.{ .KeyPressed = .A }, inside_viewport, inside_pos, false));
}

test "reset clears active capture" {
    var capture: SceneInputCapture = .{ .active = true };
    capture.reset();
    try testing.expect(!capture.active);
}

test "processSceneEvents forwards only accepted events to input" {
    var input: zp.Input = .{};
    var capture: SceneInputCapture = .{};
    const events = [_]zp.ZEvent{
        .{ .MousePressed = .Left },
        .{ .CharInput = 'x' },
    };

    capture.processSceneEvents(&input, &events, inside_viewport, inside_pos, .{});

    try testing.expect(input.isMouseButtonDown(.Left));
    try testing.expect(capture.active);
}

test "focused editor field keeps keyboard events out of scene input" {
    var input: zp.Input = .{};
    var capture: SceneInputCapture = .{};
    const events = [_]zp.ZEvent{
        .{ .KeyPressed = .A },
        .{ .KeyRepeated = .Backspace },
        .{ .KeyReleased = .A },
        .{ .CharInput = 'x' },
    };
    capture.processSceneEvents(&input, &events, inside_viewport, inside_pos, .{
        .wants_keyboard = true,
        .wants_text_input = true,
    });
    try testing.expect(!input.isKeyDown(.A));
    try testing.expectEqual(@as(usize, 0), input.textInput().len);
}
