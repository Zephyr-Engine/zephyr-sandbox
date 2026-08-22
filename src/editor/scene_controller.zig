const zp = @import("zephyr_runtime");
const zimp = @import("zimp");
const std = @import("std");

const SceneMutation = @import("scene_mutation.zig").Mutation;
const SceneInputCapture = @import("../ui/scene_input.zig");
const EditorPlayback = @import("../state/play_state.zig");
const ProjectModel = @import("project_model.zig");
const Game = @import("../game.zig");

const Runtime = zp.Runtime(Game.definition);

const SceneController = @This();

const ActiveScene = struct {
    file_name: []const u8,
    dirty: bool,
};

project: *ProjectModel,
runtime: *Runtime,
playback: EditorPlayback,
input_capture: SceneInputCapture = .{},
active_scene: ?ActiveScene = null,
selected_entity: ?zp.SceneEntityId = null,
revision_number: u64 = 0,

pub fn init(project: *ProjectModel, runtime: *Runtime) !SceneController {
    var controller = SceneController{
        .project = project,
        .runtime = runtime,
        .playback = try EditorPlayback.init(&runtime.world),
    };

    if (project.project.manifest.default_scene) |scene| {
        controller.active_scene = .{
            .file_name = scene,
            .dirty = false,
        };
    }

    return controller;
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

    try deactivateEditorCamera(&self.runtime.world.world, self.playback.editor_camera);
    try self.runtime.world.startScene(self.runtime.allocator, &self.runtime.assets, document);
    self.playback.scene_camera = zp.activeCamera(&self.runtime.world.world) orelse self.playback.editor_camera;
    try zp.setActiveCamera(&self.runtime.world.world, self.playback.editor_camera);

    self.selected_entity = null;
    self.revision_number +%= 1;
    self.active_scene = .{
        .file_name = path,
        .dirty = false,
    };
}

pub fn saveScene(self: *SceneController) !void {
    const active_scene = self.activeDocument() orelse return error.NoActiveScene;
    if (self.active_scene) |*scene| {
        if (scene.dirty) {
            try self.project.saveScene(scene.file_name, &active_scene.document);
            scene.dirty = false;
        }
    }
}

pub fn markDirty(self: *SceneController) void {
    if (self.active_scene) |*scene| {
        scene.dirty = true;
    }
}

pub fn activeDocument(self: *SceneController) ?*zp.scene_schema.LoadedScene {
    return @constCast(self.runtime.world.activeSceneDocument());
}

pub fn componentSchema(self: *const SceneController, id: zp.ComponentTypeId) ?*const zimp.scene.ComponentSchema {
    const codec = self.runtime.schemas.get(id) orelse return null;
    return &codec.schema;
}

pub fn commitSceneMutation(self: *SceneController, mutation: SceneMutation) !void {
    const active_scene = self.activeDocument();
    if (active_scene) |scene| {
        try mutation.apply(scene);
        self.markDirty();
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

fn deactivateEditorCamera(world: *zp.EcsWorld, editor_camera: zp.EntityID) !void {
    if (world.hasComponent(editor_camera, zp.ActiveCamera)) {
        try world.removeComponent(editor_camera, zp.ActiveCamera);
    }
}

test "opening a scene removes the persistent editor camera active marker" {
    var world = zp.EcsWorld.init(std.testing.allocator);
    defer world.deinit();
    inline for (.{ zp.components.TransformComponent, zp.components.CameraComponent, zp.ActiveCamera }) |Component| {
        _ = try world.registerType(Component, .{ .schema_hash = 0 });
    }

    const editor_camera = try world.spawnWith(.{
        zp.components.TransformComponent{},
        zp.components.CameraComponent{},
    });
    const scene_camera = try world.spawnWith(.{
        zp.components.TransformComponent{},
        zp.components.CameraComponent{},
    });
    try zp.setActiveCamera(&world, editor_camera);

    // Scene deserialization can add this marker directly, before the editor
    // gets the chance to switch active cameras back to its own camera.
    try world.addComponent(scene_camera, zp.ActiveCamera, .{});
    try deactivateEditorCamera(&world, editor_camera);

    try std.testing.expect(!world.hasComponent(editor_camera, zp.ActiveCamera));
    try std.testing.expectEqual(scene_camera, zp.activeCamera(&world).?);
}
