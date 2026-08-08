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
