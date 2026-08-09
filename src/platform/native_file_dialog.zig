const builtin = @import("builtin");
const std = @import("std");

pub fn chooseDirectory(allocator: std.mem.Allocator, io: std.Io, title: []const u8) !?[]u8 {
    const result = switch (builtin.os.tag) {
        .linux => try std.process.run(allocator, io, .{
            .argv = &.{ "zenity", "--file-selection", "--directory", "--title", title },
        }),
        .macos => try std.process.run(allocator, io, .{
            .argv = &.{ "osascript", "-e", "POSIX path of (choose folder)" },
        }),
        .windows => try std.process.run(allocator, io, .{
            .argv = &.{
                "powershell.exe",
                "-NoProfile",
                "-Command",
                "Add-Type -AssemblyName System.Windows.Forms; $dialog = New-Object System.Windows.Forms.FolderBrowserDialog; $dialog.Description = 'Select project folder'; if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { [Console]::Write($dialog.SelectedPath) }",
            },
        }),
        else => return error.UnsupportedPlatform,
    };
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    switch (result.term) {
        .exited => |code| switch (code) {
            0 => {},
            1 => return null,
            else => return error.NativeDialogFailed,
        },
        else => return error.NativeDialogFailed,
    }

    const path = std.mem.trimEnd(u8, result.stdout, "\r\n");
    if (path.len == 0) {
        return null;
    }
    return try allocator.dupe(u8, path);
}
