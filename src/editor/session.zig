const EditorPlayback = @import("../state/play_state.zig");
const Command = @import("command.zig").Command;

const Session = @This();

play_state: EditorPlayback,

pub fn init(play_state: EditorPlayback) Session {
    return .{
        .play_state = play_state,
    };
}

pub fn handle(self: *Session, command: Command) ?EditorPlayback.PlayState.Transition {
    const transition = self.play_state.play_state.apply(command) orelse return null;
    self.play_state.play_state = transition.to;
    return transition;
}

pub fn canHandle(self: *const Session, command: Command) bool {
    return switch (command) {
        .play => self.play_state.play_state != .Play,
        .pause => self.play_state.play_state == .Play,
        .stop => self.play_state.play_state != .Stop,
    };
}

pub fn currentPlayState(self: *const Session) EditorPlayback.PlayState {
    return self.play_state.play_state;
}

const testing = @import("std").testing;

fn sessionWithState(state: EditorPlayback.PlayState) Session {
    var session = Session.init(.{
        .play_state = .Stop,
        .editor_camera = .nil,
        .scene_camera = .nil,
    });
    session.play_state.play_state = state;
    return session;
}

test "init starts in the stopped state" {
    const session = sessionWithState(.Stop);
    try testing.expectEqual(EditorPlayback.PlayState.Stop, session.currentPlayState());
}

test "handle applies a valid transition and updates current state" {
    var session = sessionWithState(.Stop);

    const transition = session.handle(.play).?;
    try testing.expectEqual(EditorPlayback.PlayState.Stop, transition.from);
    try testing.expectEqual(EditorPlayback.PlayState.Play, transition.to);
    try testing.expectEqual(EditorPlayback.PlayState.Play, session.currentPlayState());
}

test "handle returns null and leaves state unchanged for a no-op command" {
    var session = sessionWithState(.Stop);

    try testing.expect(session.handle(.stop) == null);
    try testing.expectEqual(EditorPlayback.PlayState.Stop, session.currentPlayState());

    try testing.expect(session.handle(.pause) == null);
    try testing.expectEqual(EditorPlayback.PlayState.Stop, session.currentPlayState());
}

test "canHandle reflects the play/pause/stop rules while stopped" {
    const session = sessionWithState(.Stop);

    try testing.expect(session.canHandle(.play));
    try testing.expect(!session.canHandle(.pause));
    try testing.expect(!session.canHandle(.stop));
}

test "canHandle reflects the play/pause/stop rules while playing" {
    const session = sessionWithState(.Play);

    try testing.expect(!session.canHandle(.play));
    try testing.expect(session.canHandle(.pause));
    try testing.expect(session.canHandle(.stop));
}

test "canHandle reflects the play/pause/stop rules while paused" {
    const session = sessionWithState(.Pause);

    try testing.expect(session.canHandle(.play));
    try testing.expect(!session.canHandle(.pause));
    try testing.expect(session.canHandle(.stop));
}

test "full play/pause/stop lifecycle transitions state and history" {
    var session = sessionWithState(.Stop);

    try testing.expectEqual(EditorPlayback.PlayState.Play, session.handle(.play).?.to);
    try testing.expectEqual(EditorPlayback.PlayState.Pause, session.handle(.pause).?.to);
    try testing.expectEqual(EditorPlayback.PlayState.Play, session.handle(.play).?.to);
    try testing.expectEqual(EditorPlayback.PlayState.Stop, session.handle(.stop).?.to);
    try testing.expectEqual(EditorPlayback.PlayState.Stop, session.currentPlayState());
}
