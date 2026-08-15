const zp = @import("zephyr_runtime");
const std = @import("std");

const createProject = @import("../actions/root.zig").createProject;
const native_file_dialog = @import("../platform/native_file_dialog.zig");
const EditorPlayback = @import("../state/play_state.zig");
const SceneController = @import("scene_controller.zig");
const ProjectModel = @import("project_model.zig");
const action_mod = @import("actions.zig");
const Game = @import("../game.zig");

const Runtime = zp.Runtime(Game.definition);
const EditorContext = @This();

pub const Command = union(enum) {
    switch_project: []u8,
};

allocator: std.mem.Allocator,
io: std.Io,
project: ProjectModel,
scene: SceneController,
actions: action_mod.Registry,
pending_command: ?Command = null,

pub fn create(
    allocator: std.mem.Allocator,
    io: std.Io,
    project: *const zp.Project,
    runtime: *Runtime,
) !*EditorContext {
    const context = try allocator.create(EditorContext);
    errdefer allocator.destroy(context);

    context.io = io;
    context.allocator = allocator;
    context.project = ProjectModel.init(allocator, io, project);
    context.scene = try SceneController.init(&context.project, runtime);
    context.actions = action_mod.Registry.init(allocator);
    context.pending_command = null;

    errdefer context.actions.deinit();

    try context.registerActions();
    return context;
}

pub fn destroy(self: *EditorContext) void {
    const allocator = self.allocator;
    self.clearPendingCommand();
    self.actions.deinit();

    allocator.destroy(self);
}

pub fn rebind(self: *EditorContext, project: *const zp.Project, runtime: *Runtime, playback: EditorPlayback) void {
    self.project.rebind(project);
    self.scene.rebind(runtime, playback);
}

pub fn actionRegistry(self: *EditorContext) *action_mod.Registry {
    return &self.actions;
}

pub fn projectModel(self: *EditorContext) *ProjectModel {
    return &self.project;
}

pub fn sceneController(self: *EditorContext) *SceneController {
    return &self.scene;
}

pub fn takeCommand(self: *EditorContext) ?Command {
    const command = self.pending_command;
    self.pending_command = null;
    return command;
}

fn registerActions(self: *EditorContext) !void {
    try self.actions.register(action_mod.ids.new_project, action_mod.Action.bind("New Project", self, EditorContext.newProject));
    try self.actions.register(action_mod.ids.open_project, action_mod.Action.bind("Open Project", self, EditorContext.openProject));
    try self.actions.register(action_mod.ids.save_project, action_mod.Action.bind("Save Project", self, EditorContext.saveProject));
    try self.actions.register(action_mod.ids.play, action_mod.Action.bind("Play", &self.scene, SceneController.play).withEnabled(SceneController.canPlay));
    try self.actions.register(action_mod.ids.pause, action_mod.Action.bind("Pause", &self.scene, SceneController.pause).withEnabled(SceneController.canPause));
    try self.actions.register(action_mod.ids.stop, action_mod.Action.bind("Stop", &self.scene, SceneController.stop).withEnabled(SceneController.canStop));
}

fn newProject(self: *EditorContext) !void {
    const selection = try native_file_dialog.chooseDirectory(self.allocator, self.io, "Choose New Project Location");
    defer if (selection) |path| self.allocator.free(path);
    if (selection) |path| {
        try self.onNewProjectDirectory(path);
    }
}

fn openProject(self: *EditorContext) !void {
    const selection = try native_file_dialog.chooseDirectory(self.allocator, self.io, "Open Project");
    defer if (selection) |path| self.allocator.free(path);
    if (selection) |path| {
        try self.requestProjectSwitch(path);
    }
}

fn saveProject(_: *EditorContext) !void {
    std.log.info("Save Project selected (project saving is not implemented yet)", .{});
}

fn onNewProjectDirectory(self: *EditorContext, directory: []const u8) !void {
    const project_name = try self.allocator.dupe(u8, std.fs.path.basename(directory));
    defer self.allocator.free(project_name);

    try createProject(self.allocator, self.io, directory, project_name);
    std.log.info("New Project selected directory: {s}", .{directory});
}

fn requestProjectSwitch(self: *EditorContext, directory: []const u8) !void {
    const path = try self.allocator.dupe(u8, directory);
    self.clearPendingCommand();
    self.pending_command = .{ .switch_project = path };
}

fn clearPendingCommand(self: *EditorContext) void {
    if (self.pending_command) |command| switch (command) {
        .switch_project => |path| self.allocator.free(path),
    };
    self.pending_command = null;
}

test {
    _ = @import("project_model.zig");
}
