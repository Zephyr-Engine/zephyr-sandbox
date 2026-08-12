const std = @import("std");

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
