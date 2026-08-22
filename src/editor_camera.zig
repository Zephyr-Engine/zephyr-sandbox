const std = @import("std");

const editor_components = @import("editor_components.zig");
const zp = @import("zephyr_runtime");

pub const max_pitch: f32 = std.math.pi / 2.0 - 0.02;

pub fn updateActive(world: *zp.EcsWorld, input: *const zp.Input) void {
    const entity = zp.activeCamera(world) orelse return;
    const transform = world.getComponent(entity, zp.components.TransformComponent) orelse return;
    const controller = world.getComponent(entity, editor_components.FlyCameraController) orelse return;
    update(transform, controller, input);
}

pub fn updateActiveSystem(world: *zp.EcsWorld, commands: *zp.CommandBuffer) !void {
    std.debug.assert(commands.world == world);
    updateActive(world, world.getResource(zp.Input));
}

pub fn update(
    transform: *zp.components.TransformComponent,
    controller: *editor_components.FlyCameraController,
    input: *const zp.Input,
) void {
    const delta = input.mouse_delta;

    if (input.isMouseButtonDown(.Right)) {
        controller.yaw -= delta.x * controller.look_sensitivity;
        controller.pitch -= delta.y * controller.look_sensitivity;
        controller.pitch = std.math.clamp(controller.pitch, -max_pitch, max_pitch);
        transform.rotation = orientation(controller.yaw, controller.pitch);
    }

    if (input.isMouseButtonDown(.Left)) {
        transform.position = transform.position.sub(
            transform.right().scale(delta.x * controller.pan_sensitivity),
        );
        transform.position = transform.position.sub(
            transform.up().scale(delta.y * controller.pan_sensitivity),
        );
    }

    const scroll = input.mouse_scroll;
    if (scroll.y != 0) {
        transform.position = transform.position.add(
            transform.forward().scale(scroll.y * controller.zoom_speed),
        );
    }
}

fn orientation(yaw: f32, pitch: f32) zp.Quat {
    const yaw_rotation = zp.Quat.fromAxisAngle(zp.Vec3.new(0, 1, 0), yaw);
    const pitch_rotation = zp.Quat.fromAxisAngle(zp.Vec3.new(1, 0, 0), pitch);
    return yaw_rotation.mul(pitch_rotation);
}

test "editor camera orientation uses controller yaw and pitch" {
    const rotation = orientation(std.math.pi / 2.0, 0);
    const forward = rotation.rotateVec3(zp.Vec3.new(0, 0, -1));

    try std.testing.expectApproxEqAbs(@as(f32, -1), forward.x, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), forward.y, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), forward.z, 0.0001);
}

test "editor camera clamps look pitch and applies scroll zoom" {
    var transform: zp.components.TransformComponent = .{};
    var controller: editor_components.FlyCameraController = .{};
    var input: zp.Input = .{};

    input.applyEvent(.{ .MousePressed = .Right });
    input.applyEvent(.{ .MouseMove = .{ .x = 0, .y = 0 } });
    input.applyEvent(.{ .MouseMove = .{ .x = 0, .y = 1_000_000 } });
    input.applyEvent(.{ .MouseScroll = .{ .x = 0, .y = 2 } });
    update(&transform, &controller, &input);

    try std.testing.expectApproxEqAbs(-max_pitch, controller.pitch, 0.0001);
    const expected_position = transform.forward().scale(2);
    try std.testing.expectApproxEqAbs(expected_position.x, transform.position.x, 0.0001);
    try std.testing.expectApproxEqAbs(expected_position.y, transform.position.y, 0.0001);
    try std.testing.expectApproxEqAbs(expected_position.z, transform.position.z, 0.0001);
}
