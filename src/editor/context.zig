const zp = @import("zephyr_runtime");
const std = @import("std");

const createProject = @import("../actions/root.zig").createProject;
const native_file_dialog = @import("../platform/native_file_dialog.zig");
const SceneInputCapture = @import("../ui/scene_input.zig");
const EditorPlayback = @import("../state/play_state.zig");
const action_mod = @import("actions.zig");

const EditorContext = @This();

allocator: std.mem.Allocator,
io: std.Io,
world: *zp.World,
assets: *zp.AssetManager,
playback: EditorPlayback,
actions: action_mod.Registry,
scene_input_capture: SceneInputCapture = .{},

pub fn create(allocator: std.mem.Allocator, io: std.Io, world: *zp.World, assets: *zp.AssetManager) !*EditorContext {
    const context = try allocator.create(EditorContext);
    errdefer allocator.destroy(context);
    context.* = .{
        .allocator = allocator,
        .io = io,
        .assets = assets,
        .world = world,
        .actions = action_mod.Registry.init(allocator),
        .playback = try EditorPlayback.init(world),
    };
    errdefer context.actions.deinit();
    try context.registerActions();

    return context;
}

pub fn destroy(self: *EditorContext) void {
    const allocator = self.allocator;
    self.actions.deinit();
    allocator.destroy(self);
}

pub fn actionRegistry(self: *EditorContext) *action_mod.Registry {
    return &self.actions;
}

pub fn playState(self: *const EditorContext) EditorPlayback.PlayState {
    return self.playback.play_state;
}

pub fn sceneInputCapture(self: *EditorContext) *SceneInputCapture {
    return &self.scene_input_capture;
}

fn registerActions(self: *EditorContext) !void {
    try self.actions.register(action_mod.ids.new_project, action_mod.Action.bind("New Project", self, EditorContext.newProject));
    try self.actions.register(action_mod.ids.open_project, action_mod.Action.bind("Open Project", self, EditorContext.openProject));
    try self.actions.register(action_mod.ids.save_project, action_mod.Action.bind("Save Project", self, EditorContext.saveProject));
    try self.actions.register(action_mod.ids.play, action_mod.Action.bind("Play", self, EditorContext.play).withEnabled(EditorContext.canPlay));
    try self.actions.register(action_mod.ids.pause, action_mod.Action.bind("Pause", self, EditorContext.pause).withEnabled(EditorContext.canPause));
    try self.actions.register(action_mod.ids.stop, action_mod.Action.bind("Stop", self, EditorContext.stop).withEnabled(EditorContext.canStop));
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
        self.onOpenProjectDirectory(path);
    }
}

fn saveProject(self: *EditorContext) !void {
    _ = self;
    std.log.info("Save Project selected (project saving is not implemented yet)", .{});
}

fn onNewProjectDirectory(self: *EditorContext, directory: []const u8) !void {
    const project_name = try self.allocator.dupe(u8, std.fs.path.basename(directory));
    defer self.allocator.free(project_name);

    try createProject(self.allocator, self.io, directory, project_name);
    std.log.info("New Project selected directory: {s}", .{directory});
}

fn onOpenProjectDirectory(self: *EditorContext, directory: []const u8) void {
    _ = self;
    std.log.info("Open Project selected directory: {s}", .{directory});
}

fn play(self: *EditorContext) !void {
    try self.transitionTo(.Play);
}

fn pause(self: *EditorContext) !void {
    try self.transitionTo(.Pause);
}

fn stop(self: *EditorContext) !void {
    try self.transitionTo(.Stop);
}

fn canPlay(self: *EditorContext) bool {
    return self.playback.play_state != .Play;
}

fn canPause(self: *EditorContext) bool {
    return self.playback.play_state == .Play;
}

fn canStop(self: *EditorContext) bool {
    return self.playback.play_state != .Stop;
}

fn transitionTo(self: *EditorContext, state: EditorPlayback.PlayState) !void {
    const transition = self.playback.play_state.transitionTo(state) orelse return;
    try self.executeTransition(transition.to);
    self.playback.play_state = transition.to;
}

fn executeTransition(self: *EditorContext, state: EditorPlayback.PlayState) !void {
    var camera: zp.EntityID = undefined;
    switch (state) {
        .Play => {
            camera = self.playback.scene_camera;
        },
        .Pause => {
            camera = self.playback.editor_camera;
        },
        .Stop => {
            try self.world.resetActiveScene(self.assets);
            const cam = zp.activeCamera(&self.world.world) orelse return error.NoActiveCamera;
            self.playback.scene_camera = cam;

            camera = self.playback.editor_camera;
        },
    }
    try zp.setActiveCamera(&self.world.world, camera);

    self.world.getResource(zp.Input).clear();
    self.scene_input_capture.reset();
}
