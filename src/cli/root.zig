const zp = @import("zephyr_runtime");
const std = @import("std");

const log = @import("../utilities/log.zig");

const default_project_name = "Zephyr Game Example";

pub const Options = struct {
    root_path: []const u8 = ".",
    create_project: bool = false,
    project_name: []const u8 = default_project_name,
};

pub fn parse(args: []const []const u8) !Options {
    var options: Options = .{};

    if (args.len == 1) {
        return error.MissingProjectPath;
    }

    if (args.len == 2) {
        if (std.mem.eql(u8, args[1], "create") or std.mem.eql(u8, args[1], "open")) {
            return error.MissingProjectPath;
        }
        return error.UnknownArgument;
    }
    if (args.len != 3) {
        return error.UnknownArgument;
    }

    options.root_path = args[2];
    if (std.mem.eql(u8, args[1], "create")) {
        options.create_project = true;
    } else if (!std.mem.eql(u8, args[1], "open")) {
        return error.UnknownArgument;
    }

    return options;
}

pub fn absoluteProjectRoot(allocator: std.mem.Allocator, io: std.Io, root: []const u8) ![:0]u8 {
    if (std.fs.path.isAbsolute(root)) {
        return allocator.dupeZ(u8, root);
    }

    return std.Io.Dir.cwd().realPathFileAlloc(io, root, allocator);
}

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

const testing = std.testing;

test "parse rejects a missing project path" {
    try testing.expectError(error.MissingProjectPath, parse(&.{"zephyr-editor"}));
}

test "parse create command selects create mode" {
    const options = try parse(&.{ "zephyr-editor", "create", "/tmp/project" });

    try testing.expectEqualStrings("/tmp/project", options.root_path);
    try testing.expect(options.create_project);
}

test "parse open command selects open mode" {
    const options = try parse(&.{ "zephyr-editor", "open", "/tmp/project" });

    try testing.expectEqualStrings("/tmp/project", options.root_path);
    try testing.expect(!options.create_project);
}

test "parse rejects commands without a project path" {
    try testing.expectError(error.MissingProjectPath, parse(&.{ "zephyr-editor", "create" }));
    try testing.expectError(error.MissingProjectPath, parse(&.{ "zephyr-editor", "open" }));
}

test "parse rejects unknown arguments" {
    try testing.expectError(error.UnknownArgument, parse(&.{ "zephyr-editor", "wat" }));
    try testing.expectError(error.UnknownArgument, parse(&.{ "zephyr-editor", "open", "/tmp/project", "extra" }));
}
