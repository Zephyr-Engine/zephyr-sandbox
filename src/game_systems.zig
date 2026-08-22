const std = @import("std");

const game_components = @import("game_components.zig");
const zp = @import("zephyr_runtime");

const KeyboardMovementComponent = game_components.KeyboardMovementComponent;
const TransformComponent = zp.components.TransformComponent;
const Vec3 = zp.Vec3;

pub fn keyboardMovementSystem(world: *zp.EcsWorld, commands: *zp.CommandBuffer) !void {
    std.debug.assert(commands.world == world);
    const input = world.getResource(zp.Input);
    const direction = keyboardDirection(input);
    if (direction.x == 0 and direction.z == 0) {
        return;
    }

    const delta_time = world.getResource(zp.DeltaTime).seconds;
    var iter = world.query(.{
        .write = &.{TransformComponent},
        .read = &.{KeyboardMovementComponent},
    });

    while (iter.each()) |entity| {
        const transform = entity.write(TransformComponent);
        const controller = entity.read(KeyboardMovementComponent);

        const speed = controller.speed * if (input.isKeyDown(.LeftShift))
            controller.sprint_multiplier
        else
            1.0;
        const movement = direction.normalize().scale(speed * delta_time);
        transform.position = transform.position.add(movement);
        transform.rotation = zp.Quat.fromAxisAngle(
            Vec3.new(0, 1, 0),
            std.math.atan2(-movement.x, -movement.z),
        );
    }
}

fn keyboardDirection(input: *const zp.Input) Vec3 {
    var direction = Vec3.zero;

    if (input.isKeyDown(.W) or input.isKeyDown(.Up)) direction.z -= 1;
    if (input.isKeyDown(.S) or input.isKeyDown(.Down)) direction.z += 1;
    if (input.isKeyDown(.A) or input.isKeyDown(.Left)) direction.x -= 1;
    if (input.isKeyDown(.D) or input.isKeyDown(.Right)) direction.x += 1;

    return direction;
}

const testing = std.testing;

fn inputWithKeysDown(keys: []const zp.Key) zp.Input {
    var input: zp.Input = .{};
    for (keys) |key| {
        input.applyEvent(.{ .KeyPressed = key });
    }
    return input;
}

test "keyboardDirection is zero with no keys held" {
    const input: zp.Input = .{};
    const direction = keyboardDirection(&input);

    try testing.expectEqual(@as(f32, 0), direction.x);
    try testing.expectEqual(@as(f32, 0), direction.z);
}

test "keyboardDirection maps WASD to forward/back/left/right" {
    try testing.expectEqual(@as(f32, -1), keyboardDirection(&inputWithKeysDown(&.{.W})).z);
    try testing.expectEqual(@as(f32, 1), keyboardDirection(&inputWithKeysDown(&.{.S})).z);
    try testing.expectEqual(@as(f32, -1), keyboardDirection(&inputWithKeysDown(&.{.A})).x);
    try testing.expectEqual(@as(f32, 1), keyboardDirection(&inputWithKeysDown(&.{.D})).x);
}

test "keyboardDirection treats arrow keys as aliases for WASD" {
    try testing.expectEqual(@as(f32, -1), keyboardDirection(&inputWithKeysDown(&.{.Up})).z);
    try testing.expectEqual(@as(f32, 1), keyboardDirection(&inputWithKeysDown(&.{.Down})).z);
    try testing.expectEqual(@as(f32, -1), keyboardDirection(&inputWithKeysDown(&.{.Left})).x);
    try testing.expectEqual(@as(f32, 1), keyboardDirection(&inputWithKeysDown(&.{.Right})).x);
}

test "keyboardDirection combines simultaneous keys" {
    const direction = keyboardDirection(&inputWithKeysDown(&.{ .W, .D }));

    try testing.expectEqual(@as(f32, -1), direction.z);
    try testing.expectEqual(@as(f32, 1), direction.x);
}

test "keyboardDirection cancels opposing keys" {
    const direction = keyboardDirection(&inputWithKeysDown(&.{ .W, .S, .A, .D }));

    try testing.expectEqual(@as(f32, 0), direction.z);
    try testing.expectEqual(@as(f32, 0), direction.x);
}

test "keyboard movement system applies delta time and sprint speed to matching entities" {
    var world = zp.EcsWorld.init(testing.allocator);
    defer world.deinit();
    _ = try world.registerType(TransformComponent, .{ .schema_hash = 0 });
    _ = try world.registerType(KeyboardMovementComponent, .{ .schema_hash = 0 });
    try world.setResource(zp.Input, inputWithKeysDown(&.{ .W, .LeftShift }));
    try world.setResource(zp.DeltaTime, .{ .seconds = 1 });

    const moving = try world.spawnWith(.{
        TransformComponent{},
        KeyboardMovementComponent{},
    });
    const stationary = try world.spawnWith(.{TransformComponent{}});
    var commands = zp.CommandBuffer.init(&world);
    defer commands.deinit();

    try keyboardMovementSystem(&world, &commands);

    try testing.expectApproxEqAbs(@as(f32, -5), world.getComponent(moving, TransformComponent).?.position.z, 0.0001);
    try testing.expectApproxEqAbs(@as(f32, 0), world.getComponent(stationary, TransformComponent).?.position.z, 0.0001);
}
