const std = @import("std");
const runtime = @import("zephyr_runtime");
const gl = runtime.gl;

pub const std_options = runtime.recommended_std_options;

const GameScene = struct {
    vao: runtime.VertexArray,
    shader: runtime.Shader,
    rotation: f32,

    pub fn create(allocator: std.mem.Allocator) !*GameScene {
        const self = try allocator.create(GameScene);
        self.* = GameScene{
            .vao = undefined,
            .shader = undefined,
            .rotation = 0.0,
        };
        return self;
    }

    pub fn onStartup(self: *GameScene, allocator: std.mem.Allocator) !void {
        _ = allocator;

        std.log.info("GameScene starting up...", .{});

        const vertices = [_]f32{
            0.5, 0.5, 0.0, // top right
            0.5, -0.5, 0.0, // bottom right
            -0.5, -0.5, 0.0, // bottom left
            -0.5, 0.5, 0.0, // top left
        };

        const indices = [_]u32{
            0, 1, 3, // first triangle
            1, 2, 3, // second triangle
        };

        self.vao = runtime.VertexArray.init(&vertices, &indices);

        const vs_src = @embedFile("shaders/vertex.glsl");
        const fs_src = @embedFile("shaders/fragment.glsl");
        self.shader = runtime.Shader.init(vs_src, fs_src);

        gl.glVertexAttribPointer(0, 3, gl.GL_FLOAT, gl.GL_FALSE, 3 * @sizeOf(f32), @ptrFromInt(0));
        gl.glEnableVertexAttribArray(0);
    }

    pub fn onUpdate(self: *GameScene, delta_time: f32) void {
        self.rotation += delta_time * 45.0; // 45 degrees per second

        if (runtime.Input.isKeyPressed(.Escape)) {
            std.log.info("Escape key pressed, exiting...", .{});
        } else if (runtime.Input.isKeyHeld(.Space)) {
            std.log.info("Space key pressed!", .{});
        }

        self.shader.bind();
        self.vao.bind();
        gl.glDrawElements(gl.GL_TRIANGLES, @intCast(self.vao.indexCount()), gl.GL_UNSIGNED_INT, @ptrFromInt(0));
        self.vao.unbind();
    }

    pub fn onEvent(self: *GameScene, e: runtime.ZEvent) void {
        _ = self;
        switch (e) {
            .KeyPressed => |key| {
                std.log.info("GameScene received key: {s}", .{@tagName(key)});
            },
            .WindowClose => {
                std.log.info("GameScene shutting down...", .{});
            },
            else => {},
        }
    }

    pub fn onCleanup(self: *GameScene, allocator: std.mem.Allocator) void {
        std.log.info("GameScene cleaning up...", .{});
        allocator.destroy(self);
    }
};

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const application = try runtime.Application.init(allocator, .{
        .width = 1920,
        .height = 1080,
        .title = "Zephyr Game",
    });
    defer application.deinit(allocator);

    const game_scene = try GameScene.create(allocator);
    const scene = runtime.Scene.init(game_scene);
    try application.pushScene(scene);

    application.run();
}
