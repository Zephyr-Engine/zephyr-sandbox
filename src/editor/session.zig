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
