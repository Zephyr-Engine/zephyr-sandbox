const std = @import("std");
const ui = @import("zGUI");

const panel = @import("panel.zig");

pub const Workspace = @This();

const Entry = struct {
    panel: panel.Instance,
    window: ui.DockWindowId = ui.invalid_window,
};

allocator: std.mem.Allocator,
services: panel.Services,
dock: ui.DockSpace,
dock_host: ui.NodeId,
entries: std.ArrayList(Entry) = .empty,
index: std.AutoHashMapUnmanaged(panel.Id, usize) = .empty,

pub fn init(allocator: std.mem.Allocator, state: *ui.Ui, services: panel.Services) !Workspace {
    state.setTheme(ui.theme.zephyr_dark);
    try state.setStyle(state.rootNode(), state.theme.style(.{
        .width = .fill,
        .height = .fill,
        .direction = .column,
        .background = .app,
    }));

    var dock = try ui.DockSpace.init(allocator);
    errdefer dock.deinit();
    const dock_host = try ui.widgets.surface(state, state.rootNode(), .{
        .width = .fill,
        .height = .fill,
        .direction = .absolute,
        .background = .app,
    });

    return .{
        .allocator = allocator,
        .services = services,
        .dock = dock,
        .dock_host = dock_host,
    };
}

pub fn deinit(self: *Workspace, state: *ui.Ui) void {
    for (self.entries.items) |*item| {
        if (item.window != ui.invalid_window) self.dock.closeWindow(item.window) catch {};
        item.panel.deinit(state);
    }
    self.index.deinit(self.allocator);
    self.entries.deinit(self.allocator);
    state.destroySubtree(self.dock_host);
    self.dock.deinit();
    self.* = undefined;
}

pub fn registerPanel(self: *Workspace, state: *ui.Ui, instance: *panel.Instance) !ui.DockWindowId {
    const descriptor = instance.descriptor;
    if (self.index.contains(descriptor.id)) return error.DuplicatePanel;

    try instance.mount(state, self.dock_host, self.services);
    errdefer instance.unmount(state);
    const window_id = try self.dock.createWindow(descriptor.title, instance.root(), descriptor.min_size, .{});
    errdefer self.dock.closeWindow(window_id) catch {};

    try self.entries.append(self.allocator, .{ .panel = instance.*, .window = window_id });
    errdefer _ = self.entries.pop();
    try self.index.put(self.allocator, descriptor.id, self.entries.items.len - 1);
    instance.* = undefined;
    return window_id;
}

pub fn unregisterPanel(self: *Workspace, state: *ui.Ui, id: panel.Id) !void {
    const entry_index = self.index.get(id) orelse return error.UnknownPanel;
    var removed = self.entries.items[entry_index];
    if (removed.window != ui.invalid_window) try self.dock.closeWindow(removed.window);
    removed.panel.deinit(state);

    _ = self.index.remove(id);
    _ = self.entries.swapRemove(entry_index);
    if (entry_index < self.entries.items.len) {
        const moved_id = self.entries.items[entry_index].panel.descriptor.id;
        self.index.getPtr(moved_id).?.* = entry_index;
    }
}

pub fn openPanel(self: *Workspace, state: *ui.Ui, id: panel.Id) !ui.DockWindowId {
    const item = self.lookupEntry(id) orelse return error.UnknownPanel;
    if (item.window != ui.invalid_window) return item.window;

    try item.panel.mount(state, self.dock_host, self.services);
    errdefer item.panel.unmount(state);
    const descriptor = item.panel.descriptor;
    const window_id = try self.dock.createWindow(descriptor.title, item.panel.root(), descriptor.min_size, .{});
    errdefer self.dock.closeWindow(window_id) catch {};
    try self.dock.moveWindowToLeaf(window_id, self.dock.rootLeaf());
    item.window = window_id;
    return window_id;
}

pub fn closePanel(self: *Workspace, state: *ui.Ui, id: panel.Id) !void {
    const item = self.lookupEntry(id) orelse return error.UnknownPanel;
    if (item.window == ui.invalid_window) return;
    try self.dock.closeWindow(item.window);
    item.window = ui.invalid_window;
    item.panel.unmount(state);
}

pub fn update(self: *Workspace, state: *ui.Ui, frame: panel.Frame) !void {
    for (self.entries.items) |*item| try item.panel.update(state, frame);
}

pub fn run(self: *Workspace, state: *ui.Ui, window_size: ui.Vec2) !ui.DockSpaceResult {
    return ui.widgets.dockSpace(state, self.dock_host, &self.dock, .{
        .rect = .{
            .x = 0,
            .y = 0,
            .w = @max(1, window_size.x),
            .h = @max(1, window_size.y),
        },
        .handle_thickness = 4,
        .tab_height = 30,
    });
}

pub fn panelWindow(self: *Workspace, id: panel.Id) ?ui.DockWindowId {
    const value = self.lookupEntry(id) orelse return null;
    return if (value.window == ui.invalid_window) null else value.window;
}

pub fn contentRect(self: *const Workspace, id: panel.Id) ?ui.Rect {
    const entry_index = self.index.get(id) orelse return null;
    const window_id = self.entries.items[entry_index].window;
    if (window_id == ui.invalid_window) return null;
    return self.dock.windowContentRect(window_id);
}

fn lookupEntry(self: *Workspace, id: panel.Id) ?*Entry {
    const entry_index = self.index.get(id) orelse return null;
    return &self.entries.items[entry_index];
}

test "workspace owns panel mount update close reopen and teardown" {
    const actions = @import("../editor/actions.zig");
    const test_id = panel.id("test.panel");

    const Counters = struct {
        mounts: usize = 0,
        updates: usize = 0,
        unmounts: usize = 0,
        deinits: usize = 0,
    };
    const TestPanel = struct {
        counters: *Counters,
        root_node: ui.NodeId = ui.invalid_node,

        fn mount(self: *@This(), state: *ui.Ui, parent: ui.NodeId, services: panel.Services) !void {
            _ = services;
            self.root_node = try ui.widgets.surface(state, parent, .{ .width = .fill, .height = .fill });
            self.counters.mounts += 1;
        }

        fn update(self: *@This(), state: *ui.Ui, frame: panel.Frame) !void {
            _ = state;
            _ = frame;
            self.counters.updates += 1;
        }

        fn unmount(self: *@This(), state: *ui.Ui) void {
            if (self.root_node == ui.invalid_node) return;
            state.destroySubtree(self.root_node);
            self.root_node = ui.invalid_node;
            self.counters.unmounts += 1;
        }

        fn root(self: *const @This()) ui.NodeId {
            return self.root_node;
        }

        fn deinit(self: *@This()) void {
            self.counters.deinits += 1;
        }
    };

    var state = try ui.Ui.init(std.testing.allocator);
    defer state.deinit();
    var action_registry = actions.Registry.init(std.testing.allocator);
    defer action_registry.deinit();
    var workspace = try Workspace.init(std.testing.allocator, &state, .{ .actions = &action_registry });
    defer workspace.deinit(&state);

    var counters: Counters = .{};
    var instance = try panel.Instance.create(std.testing.allocator, .{
        .id = test_id,
        .title = "Test",
        .min_size = .{ .x = 80, .y = 80 },
    }, TestPanel{ .counters = &counters });
    var instance_owned = true;
    errdefer if (instance_owned) instance.deinit(&state);

    const first_window = try workspace.registerPanel(&state, &instance);
    instance_owned = false;
    try std.testing.expectEqual(@as(usize, 1), counters.mounts);
    try workspace.update(&state, .{});
    try std.testing.expectEqual(@as(usize, 1), counters.updates);

    try workspace.closePanel(&state, test_id);
    try std.testing.expectEqual(@as(usize, 1), counters.unmounts);
    const second_window = try workspace.openPanel(&state, test_id);
    try std.testing.expect(first_window != second_window);
    try std.testing.expectEqual(@as(usize, 2), counters.mounts);

    try workspace.unregisterPanel(&state, test_id);
    try std.testing.expectEqual(@as(usize, 2), counters.unmounts);
    try std.testing.expectEqual(@as(usize, 1), counters.deinits);
    try std.testing.expect(workspace.panelWindow(test_id) == null);
}
