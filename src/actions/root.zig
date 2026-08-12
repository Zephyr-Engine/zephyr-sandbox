const zp = @import("zephyr_runtime");
const std = @import("std");

const log = @import("../utilities/log.zig");

pub fn createProject(
    allocator: std.mem.Allocator,
    io: std.Io,
    root_path: []const u8,
    name: []const u8,
) !void {
    const root_dir = try std.Io.Dir.openDirAbsolute(io, root_path, .{});
    errdefer root_dir.close(io);

    const project_name = try allocator.dupe(u8, name);
    defer allocator.free(project_name);

    const random_source: std.Random.IoSource = .{ .io = io };
    const manifest = zp.ProjectManifest{
        .project_id = .v4(random_source.interface()),
        .name = project_name,
    };

    try root_dir.createDirPath(io, manifest.generated_dir);
    try root_dir.createDirPath(io, manifest.assets_dir);
    try root_dir.createDirPath(io, manifest.scenes_dir);
    try root_dir.createDirPath(io, manifest.cooked_assets_dir);
    try manifest.save(allocator, io, root_dir);

    log.info("Created project at {s}", .{root_path});
}
