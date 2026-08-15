const builtin = @import("builtin");
const std = @import("std");

const EditorApplication = @import("editor/application.zig");
const actions = @import("actions/root.zig");
const log = @import("utilities/log.zig");
const cli = @import("cli/root.zig");

inline fn allocator(gpa: std.mem.Allocator) std.mem.Allocator {
    if (builtin.mode == .Debug) {
        return gpa;
    }

    return std.heap.smp_allocator;
}

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const options = cli.parse(args) catch |err| {
        log.err("Invalid editor arguments: {}", .{err});
        return;
    };

    const project_root = try cli.absoluteProjectRoot(init.gpa, init.io, options.root_path);
    defer init.gpa.free(project_root);

    if (options.create_project) {
        try actions.createProject(init.gpa, init.io, project_root, options.project_name);
        return;
    }

    var editor_application = EditorApplication.init(init.gpa, init.io, project_root) catch |err| {
        log.err("Failed to initialize editor: {}", .{err});
        return;
    };
    defer editor_application.deinit();

    editor_application.run() catch |err| log.err("Editor failed: {}", .{err});
}

test {
    _ = @import("cli/root.zig");
    _ = @import("editor_camera.zig");
    _ = @import("editor/application.zig");
    _ = @import("game_systems.zig");
    _ = @import("state/play_state.zig");
    _ = @import("ui/scene_input.zig");
    _ = @import("platform/native_file_dialog.zig");
    _ = @import("ui/viewport.zig");
    _ = @import("viewport_target.zig");
}
