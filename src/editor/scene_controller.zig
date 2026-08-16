const zp = @import("zephyr_runtime");
const SceneMutation = @import("scene_mutation.zig").Mutation;
const SceneInputCapture = @import("../ui/scene_input.zig");
const EditorPlayback = @import("../state/play_state.zig");
const ProjectModel = @import("project_model.zig");
const Game = @import("../game.zig");

const Runtime = zp.Runtime(Game.definition);

const SceneController = @This();

project: *ProjectModel,
runtime: *Runtime,
playback: EditorPlayback,
input_capture: SceneInputCapture = .{},
selected_entity: ?zp.SceneEntityId = null,
revision_number: u64 = 0,

pub fn init(project: *ProjectModel, runtime: *Runtime) !SceneController {
    return .{
        .project = project,
        .runtime = runtime,
        .playback = try EditorPlayback.init(&runtime.world),
    };
}

pub fn preparePlayback(runtime: *Runtime) !EditorPlayback {
    return EditorPlayback.init(&runtime.world);
}

pub fn rebind(self: *SceneController, runtime: *Runtime, playback: EditorPlayback) void {
    self.runtime = runtime;
    self.playback = playback;
    self.input_capture.reset();
    self.selected_entity = null;
    self.revision_number +%= 1;
}

pub fn openScene(self: *SceneController, path: []const u8) !void {
    var document = try self.project.loadScene(path);
    errdefer document.deinit();

    try self.runtime.world.startScene(self.runtime.allocator, &self.runtime.assets, document);
    self.playback.scene_camera = zp.activeCamera(&self.runtime.world.world) orelse self.playback.editor_camera;
    try zp.setActiveCamera(&self.runtime.world.world, self.playback.editor_camera);

    self.selected_entity = null;
    self.revision_number +%= 1;
}

pub fn activeDocument(self: *SceneController) ?*zp.scene_schema.LoadedScene {
    return @constCast(self.runtime.world.activeSceneDocument());
}

pub fn commitSceneMutation(self: *SceneController, mutation: SceneMutation) !void {
    const active_scene = self.activeDocument();
    if (active_scene) |scene| {
        try mutation.apply(scene);
        self.revision_number +%= 1;
    }
}

pub fn selectEntity(self: *SceneController, entity: ?zp.SceneEntityId) void {
    if (optionalEntityEql(self.selected_entity, entity)) {
        return;
    }
    self.selected_entity = entity;
    self.revision_number +%= 1;
}

pub fn selectedEntity(self: *const SceneController) ?zp.SceneEntityId {
    return self.selected_entity;
}

pub fn revision(self: *const SceneController) u64 {
    return self.revision_number;
}

pub fn playState(self: *const SceneController) EditorPlayback.PlayState {
    return self.playback.play_state;
}

pub fn sceneInputCapture(self: *SceneController) *SceneInputCapture {
    return &self.input_capture;
}

pub fn play(self: *SceneController) !void {
    try self.transitionTo(.Play);
}

pub fn pause(self: *SceneController) !void {
    try self.transitionTo(.Pause);
}

pub fn stop(self: *SceneController) !void {
    try self.transitionTo(.Stop);
}

pub fn canPlay(self: *SceneController) bool {
    return self.playback.play_state != .Play;
}

pub fn canPause(self: *SceneController) bool {
    return self.playback.play_state == .Play;
}

pub fn canStop(self: *SceneController) bool {
    return self.playback.play_state != .Stop;
}

fn transitionTo(self: *SceneController, state: EditorPlayback.PlayState) !void {
    const transition = self.playback.play_state.transitionTo(state) orelse return;
    try self.executeTransition(transition.to);
    self.playback.play_state = transition.to;
    self.revision_number +%= 1;
}

fn executeTransition(self: *SceneController, state: EditorPlayback.PlayState) !void {
    const camera: zp.EntityID = switch (state) {
        .Play => self.playback.scene_camera,
        .Pause => self.playback.editor_camera,
        .Stop => blk: {
            try self.runtime.world.resetActiveScene();
            self.playback.scene_camera = zp.activeCamera(&self.runtime.world.world) orelse return error.NoActiveCamera;
            self.selected_entity = null;
            break :blk self.playback.editor_camera;
        },
    };

    try zp.setActiveCamera(&self.runtime.world.world, camera);
    self.runtime.world.getResource(zp.Input).clear();
    self.input_capture.reset();
}

fn optionalEntityEql(a: ?zp.SceneEntityId, b: ?zp.SceneEntityId) bool {
    if (a) |left| {
        if (b) |right| {
            return left.eql(right);
        }
        return false;
    }
    return b == null;
}
