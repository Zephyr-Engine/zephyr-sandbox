const std = @import("std");
const ui = @import("zGUI");
const log = @import("../utilities/log.zig");

pub const ActionId = u64;

pub fn actionId(comptime name: []const u8) ActionId {
    comptime var hash: u64 = 14695981039346656037;
    inline for (name) |byte| {
        hash = (hash ^ byte) *% 1099511628211;
    }
    return hash;
}

pub const ids = struct {
    pub const new_project = actionId("editor.project.new");
    pub const open_project = actionId("editor.project.open");
    pub const save_project = actionId("editor.project.save");
    pub const play = actionId("editor.play");
    pub const pause = actionId("editor.pause");
    pub const stop = actionId("editor.stop");
};

pub const Action = struct {
    label: []const u8,
    context: ?*anyopaque,
    execute_fn: *const fn (?*anyopaque) anyerror!void,
    enabled_fn: ?*const fn (?*anyopaque) bool = null,
    checked_fn: ?*const fn (?*anyopaque) bool = null,

    pub fn bind(label: []const u8, context: anytype, comptime execute_callback: fn (@TypeOf(context)) anyerror!void) Action {
        const Context = requireContextPointer(@TypeOf(context));
        return .{
            .label = label,
            .context = @ptrCast(@constCast(context)),
            .execute_fn = struct {
                fn invoke(raw_context: ?*anyopaque) !void {
                    try execute_callback(toContext(Context, raw_context));
                }
            }.invoke,
        };
    }

    pub fn withEnabled(self: Action, comptime enabled_callback: anytype) Action {
        const Context = actionContext(@TypeOf(enabled_callback));
        var next = self;
        next.enabled_fn = struct {
            fn invoke(raw_context: ?*anyopaque) bool {
                return enabled_callback(toContext(Context, raw_context));
            }
        }.invoke;
        return next;
    }

    pub fn withChecked(self: Action, comptime checked_callback: anytype) Action {
        const Context = actionContext(@TypeOf(checked_callback));
        var next = self;
        next.checked_fn = struct {
            fn invoke(raw_context: ?*anyopaque) bool {
                return checked_callback(toContext(Context, raw_context));
            }
        }.invoke;
        return next;
    }

    pub fn enabled(self: Action) bool {
        return if (self.enabled_fn) |callback| callback(self.context) else true;
    }

    pub fn checked(self: Action) bool {
        return if (self.checked_fn) |callback| callback(self.context) else false;
    }

    fn execute(self: Action) !void {
        try self.execute_fn(self.context);
    }
};

pub const Registry = struct {
    allocator: std.mem.Allocator,
    entries: std.AutoHashMapUnmanaged(ActionId, Action) = .empty,

    pub fn init(allocator: std.mem.Allocator) Registry {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Registry) void {
        self.entries.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn register(self: *Registry, id: ActionId, action: Action) !void {
        if (self.entries.contains(id)) return error.DuplicateAction;
        try self.entries.put(self.allocator, id, action);
    }

    pub fn unregister(self: *Registry, id: ActionId) void {
        _ = self.entries.remove(id);
    }

    pub fn get(self: *const Registry, id: ActionId) ?Action {
        return self.entries.get(id);
    }

    pub fn invoke(self: *Registry, id: ActionId) !bool {
        const action = self.entries.get(id) orelse return false;
        if (!action.enabled()) {
            return false;
        }
        try action.execute();
        return true;
    }

    pub fn enabled(self: *const Registry, id: ActionId) bool {
        const action = self.entries.get(id) orelse return false;
        return action.enabled();
    }

    pub fn checked(self: *const Registry, id: ActionId) bool {
        const action = self.entries.get(id) orelse return false;
        return action.checked();
    }

    /// Adapts an action to zGUI's infallible event callback API. Failures are
    /// logged here because zGUI cannot return them to its event loop.
    pub fn handler(self: *Registry, comptime id: ActionId) ui.EventHandler {
        return ui.EventHandler.bind(self, struct {
            fn activate(registry: *Registry, _: ui.Event) void {
                _ = registry.invoke(id) catch |err| {
                    log.err("failed to invoke action: {}", .{err});
                    return;
                };
            }
        }.activate);
    }
};

fn requireContextPointer(comptime Context: type) type {
    const info = @typeInfo(Context);
    if (info != .pointer or info.pointer.size != .one) {
        @compileError("action context must be a single-item pointer");
    }
    return Context;
}

fn actionContext(comptime Function: type) type {
    const info = @typeInfo(Function);
    if (info != .@"fn" or info.@"fn".params.len != 1) {
        @compileError("action state callbacks must accept exactly one context pointer");
    }
    return requireContextPointer(info.@"fn".params[0].type.?);
}

fn toContext(comptime Context: type, raw_context: ?*anyopaque) Context {
    return @ptrCast(@alignCast(raw_context.?));
}

test "registered actions share execution and enabled state" {
    const State = struct {
        count: usize = 0,
        allow: bool = true,
        selected: bool = false,

        fn increment(self: *@This()) !void {
            self.count += 1;
        }

        fn enabled(self: *@This()) bool {
            return self.allow;
        }

        fn checked(self: *@This()) bool {
            return self.selected;
        }
    };

    var state: State = .{};
    var registry = Registry.init(std.testing.allocator);
    defer registry.deinit();
    try registry.register(ids.play, Action.bind("Play", &state, State.increment).withEnabled(State.enabled).withChecked(State.checked));

    try std.testing.expect(try registry.invoke(ids.play));
    try std.testing.expectEqual(@as(usize, 1), state.count);
    state.allow = false;
    try std.testing.expect(!(try registry.invoke(ids.play)));
    try std.testing.expectEqual(@as(usize, 1), state.count);
    try std.testing.expect(!registry.checked(ids.play));
    state.selected = true;
    try std.testing.expect(registry.checked(ids.play));
}

test "invocation propagates action failures" {
    const State = struct {
        fn fail(_: *@This()) !void {
            return error.ActionFailed;
        }
    };

    var state: State = .{};
    var registry = Registry.init(std.testing.allocator);
    defer registry.deinit();
    try registry.register(ids.play, Action.bind("Fail", &state, State.fail));

    try std.testing.expectError(error.ActionFailed, registry.invoke(ids.play));
}
