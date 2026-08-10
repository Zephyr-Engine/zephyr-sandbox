const zp = @import("zephyr_runtime");

const components = @import("../editor_components.zig");
const log = @import("../utilities/log.zig");

const EditorPlayback = @This();

play_state: PlayState = .Stop,
editor_camera: zp.EntityID,
scene_camera: zp.EntityID,

pub fn init(world: *zp.World) !EditorPlayback {
    const active_scene_camera = zp.activeCamera(&world.world);

    // default editor camera to the active scene camera
    const editor_transform: zp.components.TransformComponent = if (active_scene_camera) |entity|
        world.world.getComponent(entity, zp.components.TransformComponent).?.*
    else
        .{};
    const editor_camera_component: zp.components.CameraComponent = if (active_scene_camera) |entity|
        world.world.getComponent(entity, zp.components.CameraComponent).?.*
    else
        .{};

    const editor_camera = try world.world.spawnWith(.{
        editor_transform,
        editor_camera_component,
        components.FlyCameraController{},
    });
    const scene_camera = active_scene_camera orelse blk: {
        log.warn("No active camera found, using editor camera", .{});
        break :blk editor_camera;
    };
    errdefer world.world.despawn(editor_camera);

    try zp.setActiveCamera(&world.world, editor_camera);

    return .{
        .editor_camera = editor_camera,
        .scene_camera = scene_camera,
    };
}

pub const PlayState = enum {
    Play,
    Pause,
    Stop,

    pub const Transition = struct {
        from: PlayState,
        to: PlayState,
    };

    pub fn transitionTo(current: PlayState, next: PlayState) ?Transition {
        if (next == current or (next == .Pause and current != .Play)) {
            return null;
        }

        return .{ .from = current, .to = next };
    }
};

const testing = @import("std").testing;

test "play state accepts only meaningful transitions" {
    try testing.expectEqual(PlayState.Play, PlayState.Stop.transitionTo(.Play).?.to);
    try testing.expectEqual(PlayState.Pause, PlayState.Play.transitionTo(.Pause).?.to);
    try testing.expectEqual(PlayState.Stop, PlayState.Pause.transitionTo(.Stop).?.to);
    try testing.expect(PlayState.Stop.transitionTo(.Pause) == null);
    try testing.expect(PlayState.Stop.transitionTo(.Stop) == null);
}

test "pause is only meaningful while playing" {
    try testing.expect(PlayState.Pause.transitionTo(.Pause) == null);
    try testing.expect(PlayState.Stop.transitionTo(.Pause) == null);
}

test "play and stop are idempotent from their own state" {
    try testing.expect(PlayState.Play.transitionTo(.Play) == null);
    try testing.expect(PlayState.Stop.transitionTo(.Stop) == null);
}

test "play restarts playback from a paused state" {
    const transition = PlayState.Pause.transitionTo(.Play).?;
    try testing.expectEqual(PlayState.Pause, transition.from);
    try testing.expectEqual(PlayState.Play, transition.to);
}

test "stop is always reachable from play or pause" {
    try testing.expectEqual(PlayState.Stop, PlayState.Play.transitionTo(.Stop).?.to);
    try testing.expectEqual(PlayState.Stop, PlayState.Pause.transitionTo(.Stop).?.to);
}
