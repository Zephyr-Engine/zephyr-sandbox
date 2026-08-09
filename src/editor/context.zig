const zp = @import("zephyr_runtime");
const std = @import("std");

const SceneInputCapture = @import("../ui/scene_input.zig");
const EditorPlayback = @import("../state/play_state.zig");
const Command = @import("command.zig").Command;
const action_mod = @import("actions.zig");
const Session = @import("session.zig");
const native_file_dialog = @import("../platform/native_file_dialog.zig");

const EditorContext = @This();

allocator: std.mem.Allocator,
io: std.Io,
world: *zp.World,
assets: *zp.AssetManager,
session: Session,
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
        .session = Session.init(try EditorPlayback.init(world)),
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
    return self.session.currentPlayState();
}

pub fn sceneInputCapture(self: *EditorContext) *SceneInputCapture {
    return &self.scene_input_capture;
}

fn registerActions(self: *EditorContext) !void {
    try self.actions.register(action_mod.ids.new_project, action_mod.Action.bind("New Project", self, EditorContext.newProject));
    try self.actions.register(action_mod.ids.open_project, action_mod.Action.bind("Open Project", self, EditorContext.openProject));
    try self.actions.register(action_mod.ids.save_project, action_mod.Action.bind("Save Project", self, EditorContext.saveProject));
    try self.actions.register(action_mod.ids.play, bindCommand("Play", self, .play));
    try self.actions.register(action_mod.ids.pause, bindCommand("Pause", self, .pause));
    try self.actions.register(action_mod.ids.stop, bindCommand("Stop", self, .stop));
}

fn newProject(self: *EditorContext) void {
    const selection = native_file_dialog.chooseDirectory(self.allocator, self.io, "Choose New Project Location") catch |err| {
        std.log.err("could not open the native new-project picker: {}", .{err});
        return;
    };

    defer if (selection) |path| self.allocator.free(path);
    if (selection) |path| {
        self.onNewProjectDirectory(path);
    }
}

fn openProject(self: *EditorContext) void {
    const selection = native_file_dialog.chooseDirectory(self.allocator, self.io, "Open Project") catch |err| {
        std.log.err("could not open the native open-project picker: {}", .{err});
        return;
    };
    defer if (selection) |path| self.allocator.free(path);

    if (selection) |path| {
        self.onOpenProjectDirectory(path);
    }
}

fn saveProject(self: *EditorContext) void {
    _ = self;
    std.log.info("Save Project selected (project saving is not implemented yet)", .{});
}

fn onNewProjectDirectory(self: *EditorContext, directory: []const u8) void {
    _ = self;
    std.log.info("New Project selected directory: {s}", .{directory});
}

fn onOpenProjectDirectory(self: *EditorContext, directory: []const u8) void {
    _ = self;
    std.log.info("Open Project selected directory: {s}", .{directory});
}

fn bindCommand(comptime label: []const u8, context: *EditorContext, comptime command: Command) action_mod.Action {
    return action_mod.Action.bind(label, context, commandAction(command)).withEnabled(commandEnabled(command));
}

fn commandAction(comptime command: Command) fn (*EditorContext) void {
    return struct {
        fn execute(context: *EditorContext) void {
            const transition = context.session.handle(command) orelse return;
            context.executeTransition(transition.to) catch |err| {
                std.log.err("failed to execute transition: {}", .{err});
            };
        }
    }.execute;
}

fn commandEnabled(comptime command: Command) fn (*EditorContext) bool {
    return struct {
        fn enabled(context: *EditorContext) bool {
            return context.session.canHandle(command);
        }
    }.enabled;
}

fn executeTransition(self: *EditorContext, state: EditorPlayback.PlayState) !void {
    var camera: zp.EntityID = undefined;
    switch (state) {
        .Play => {
            camera = self.session.play_state.scene_camera;
        },
        .Pause => {
            camera = self.session.play_state.editor_camera;
        },
        .Stop => {
            try self.world.resetActiveScene(self.assets);
            const cam = zp.activeCamera(&self.world.world) orelse return error.NoActiveCamera;
            self.session.play_state.scene_camera = cam;

            camera = self.session.play_state.editor_camera;
        },
    }
    try zp.setActiveCamera(&self.world.world, camera);

    self.world.getResource(zp.Input).clear();
    self.scene_input_capture.reset();
}
