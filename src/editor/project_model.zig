const std = @import("std");
const zimp = @import("zimp");
const zp = @import("zephyr_runtime");

const ProjectModel = @This();

pub const ItemKind = enum {
    folder,
    file,
};

pub const Item = struct {
    path: []u8,
    kind: ItemKind,
};

pub const Listing = struct {
    allocator: std.mem.Allocator,
    items: std.ArrayList(Item) = .empty,

    pub fn deinit(self: *Listing) void {
        for (self.items.items) |item| self.allocator.free(item.path);
        self.items.deinit(self.allocator);
        self.* = undefined;
    }
};

allocator: std.mem.Allocator,
io: std.Io,
project: *const zp.Project,
generation: u64 = 0,

pub fn init(allocator: std.mem.Allocator, io: std.Io, project: *const zp.Project) ProjectModel {
    return .{
        .allocator = allocator,
        .io = io,
        .project = project,
    };
}

pub fn rebind(self: *ProjectModel, project: *const zp.Project) void {
    self.project = project;
    self.generation +%= 1;
}

pub fn roots(self: *const ProjectModel) [2][]const u8 {
    return .{ self.project.manifest.assets_dir, self.project.manifest.scenes_dir };
}

pub fn listDirectory(self: *const ProjectModel, path: []const u8) !Listing {
    var listing = Listing{ .allocator = self.allocator };
    errdefer listing.deinit();

    if (path.len == 0) {
        for (self.roots()) |root| {
            try appendItem(self.allocator, &listing.items, root, .folder);
        }
        return listing;
    }

    var dir = std.Io.Dir.openDir(self.project.root_dir, self.io, path, .{ .iterate = true }) catch return listing;
    defer dir.close(self.io);
    var iter = dir.iterate();

    while (try iter.next(self.io)) |entry| {
        const kind: ItemKind = if (entry.kind == .directory) .folder else .file;
        const entry_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ path, entry.name });
        errdefer self.allocator.free(entry_path);
        try listing.items.append(self.allocator, .{ .path = entry_path, .kind = kind });
    }

    return listing;
}

pub fn isScenePath(self: *const ProjectModel, path: []const u8) bool {
    return isScenePathIn(self.project.manifest.scenes_dir, path);
}

pub fn loadScene(self: *const ProjectModel, path: []const u8) !zimp.scene.SceneDocument {
    return self.project.loadScene(self.allocator, self.io, path);
}

pub fn saveScene(self: *const ProjectModel, path: []const u8, document: *const zimp.scene.SceneDocument) !void {
    return self.project.saveScene(self.allocator, self.io, path, document);
}

fn appendItem(allocator: std.mem.Allocator, items: *std.ArrayList(Item), path: []const u8, kind: ItemKind) !void {
    try items.append(allocator, .{
        .path = try allocator.dupe(u8, path),
        .kind = kind,
    });
}

fn isScenePathIn(scenes_dir: []const u8, path: []const u8) bool {
    return path.len > scenes_dir.len and
        std.mem.startsWith(u8, path, scenes_dir) and
        path[scenes_dir.len] == '/' and
        std.mem.endsWith(u8, path, ".scene.json");
}

test "scene paths must be files inside the configured scenes directory" {
    try std.testing.expect(isScenePathIn("scenes", "scenes/level.scene.json"));
    try std.testing.expect(isScenePathIn("scenes", "scenes/nested/level.scene.json"));
    try std.testing.expect(!isScenePathIn("scenes", "scenes.scene.json"));
    try std.testing.expect(!isScenePathIn("scenes", "scenes-old/level.scene.json"));
    try std.testing.expect(!isScenePathIn("scenes", "scenes/level.json"));
}

test "directory listings own paths and distinguish files from folders" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "assets/models");
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "assets/readme.txt", .data = "asset" });

    const project = zp.Project{
        .manifest = .{
            .name = "Test",
            .project_id = .parseComptime("bf5a424f-e93e-4977-9a7a-0c522318dfdc"),
        },
        .root_dir = tmp.dir,
    };
    var model = ProjectModel.init(std.testing.allocator, std.testing.io, &project);
    var listing = try model.listDirectory("assets");
    defer listing.deinit();

    try std.testing.expectEqual(@as(usize, 2), listing.items.items.len);
    var saw_folder = false;
    var saw_file = false;
    for (listing.items.items) |item| {
        if (std.mem.eql(u8, item.path, "assets/models")) saw_folder = item.kind == .folder;
        if (std.mem.eql(u8, item.path, "assets/readme.txt")) saw_file = item.kind == .file;
    }
    try std.testing.expect(saw_folder);
    try std.testing.expect(saw_file);
}
