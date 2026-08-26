const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const runtime_dep = b.dependency("zephyr_runtime", .{
        .target = target,
        .optimize = optimize,
    });
    const runtime_mod = runtime_dep.module("zephyr_runtime");
    const zimp_mod = runtime_dep.module("zimp");
    const zgui_dep = b.dependency("zGUI", .{
        .target = target,
        .optimize = optimize,
    });
    const zgui_mod = zgui_dep.module("zGUI");
    const zgui_native_mod = zgui_dep.module("zGUI_native");

    const editor_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zephyr_runtime", .module = runtime_mod },
            .{ .name = "zimp", .module = zimp_mod },
            .{ .name = "zGUI", .module = zgui_mod },
            .{ .name = "zGUI_native", .module = zgui_native_mod },
        },
    });

    const exe = b.addExecutable(.{
        .name = "Zephyr Editor",
        .root_module = editor_mod,
    });

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);

    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const editor_tests = b.addTest(.{
        .root_module = editor_mod,
    });
    const run_editor_tests = b.addRunArtifact(editor_tests);
    const test_step = b.step("test", "Run editor tests");
    test_step.dependOn(&run_editor_tests.step);

    const check_step = b.step("check", "Compile the editor and tests");
    check_step.dependOn(&exe.step);
    check_step.dependOn(&editor_tests.step);
}
