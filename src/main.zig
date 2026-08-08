const builtin = @import("builtin");
const std = @import("std");

const editor_application = @import("editor/application.zig");
const log = @import("utilities/log.zig");
const zp = @import("zephyr_runtime");
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
        try cli.createProject(init.gpa, init.io, project_root, options.project_name);
        return;
    }

    var project = try zp.openProject(init.gpa, init.io, .{ .root_path = project_root });
    defer project.deinit(init.gpa, init.io);

    const watch_handle = try project.watchAssets(init.gpa, init.io);
    defer project.stopWatchingAssets(watch_handle);

    watch_handle.waitForInitialCook() catch |err| {
        log.err("Failed to cook initial assets: {}", .{err});
        return;
    };

    editor_application.run(allocator(init.gpa), init.io, &project) catch |err| {
        log.err("Editor failed to start: {}", .{err});
        return;
    };
}

test {
    _ = @import("cli/root.zig");
    _ = @import("editor_camera.zig");
    _ = @import("editor/application.zig");
    _ = @import("game_systems.zig");
    _ = @import("state/play_state.zig");
    _ = @import("ui/scene_input.zig");
    _ = @import("ui/viewport.zig");
    _ = @import("viewport_target.zig");
}
