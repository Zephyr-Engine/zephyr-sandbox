const std = @import("std");
const runtime = @import("zephyr_runtime");

pub const std_options = runtime.recommended_std_options;

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const application = try runtime.Application.init(allocator);
    defer application.deinit(allocator);
    application.run();
}
