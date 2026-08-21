const std = @import("std");
const ui = @import("zGUI");

const SceneController = @import("../editor/scene_controller.zig");
const ProjectModel = @import("../editor/project_model.zig");
const AssetNavigation = @import("components/asset_navigation.zig").AssetNavigation;
const AssetTile = @import("components/asset_tile.zig").AssetTile;
const panel = @import("panel.zig");

pub const panel_id = panel.id("editor.assets");
pub const descriptor: panel.Descriptor = .{
    .id = panel_id,
    .title = "Assets",
    .min_size = .{ .x = 240, .y = 96 },
};

pub const Icons = AssetTile.Icons;

const Item = ProjectModel.Item;
const refresh_interval_frames = 300;
const grid_gap: f32 = 7;
const Assets = @This();

allocator: std.mem.Allocator,
project: *ProjectModel,
scenes: *SceneController,
icons: Icons,
items: std.ArrayList(Item) = .empty,
history: std.ArrayList([]u8) = .empty,
history_index: usize = 0,
root_node: ui.NodeId = ui.invalid_node,
body_node: ui.NodeId = ui.invalid_node,
list_node: ui.NodeId = ui.invalid_node,
navigation: AssetNavigation = undefined,
tiles: std.ArrayList(AssetTile) = .empty,
grid_columns: usize = 1,
frames_since_refresh: u16 = refresh_interval_frames,
last_clicked_tile: ?ui.NodeId = null,
project_generation: u64,

pub const Dependencies = struct {
    allocator: std.mem.Allocator,
    project: *ProjectModel,
    scenes: *SceneController,
    icons: Icons,
};

pub fn init(dependencies: Dependencies) Assets {
    return .{
        .allocator = dependencies.allocator,
        .project = dependencies.project,
        .scenes = dependencies.scenes,
        .icons = dependencies.icons,
        .project_generation = dependencies.project.generation,
    };
}

pub fn deinit(self: *Assets) void {
    deinitItems(self.allocator, &self.items);
    for (self.history.items) |path| self.allocator.free(path);
    self.history.deinit(self.allocator);
    self.tiles.deinit(self.allocator);
}

pub fn mount(self: *Assets, state: *ui.Ui, parent: ui.NodeId, _: panel.Services) !void {
    const root_node = try ui.widgets.column(state, parent, .{
        .width = .fill,
        .height = .fill,
        .background = .shell,
        .border = .stroke_soft,
        .border_edges = .{ .top = 1 },
    });
    errdefer state.destroySubtree(root_node);

    const navigation = try AssetNavigation.init(state, root_node);
    _ = try ui.widgets.divider(state, root_node);
    const body_node = try ui.widgets.column(state, root_node, .{
        .width = .fill,
        .height = .fill,
        .padding = .{
            .left = state.theme.space.md,
            .right = state.theme.space.md,
            .top = state.theme.space.md,
            .bottom = state.theme.space.lg,
        },
        .background = .shell,
        .overflow_y = .scroll,
    });

    self.root_node = root_node;
    self.body_node = body_node;
    self.navigation = navigation;
    self.frames_since_refresh = refresh_interval_frames;
    try self.ensureHistory();
    try self.refresh(state, true);
}

pub fn update(self: *Assets, state: *ui.Ui, _: panel.Frame) !void {
    if (self.project_generation != self.project.generation) {
        self.project_generation = self.project.generation;
        self.resetProjectNavigation();
        self.resetScroll(state);
        try self.ensureHistory();
        try self.refresh(state, true);
        return;
    }

    if (self.navigation.backClicked(state) and self.history_index > 0) {
        self.history_index -= 1;
        self.resetScroll(state);
        try self.refresh(state, true);
        return;
    }
    if (self.navigation.forwardClicked(state) and self.history_index + 1 < self.history.items.len) {
        self.history_index += 1;
        self.resetScroll(state);
        try self.refresh(state, true);
        return;
    }

    for (self.tiles.items, self.items.items) |tile, item| {
        if (item.kind == .folder and tile.clicked(state)) {
            try self.navigateTo(state, item.path);
            return;
        }
        if (item.kind == .file and self.project.isScenePath(item.path) and tile.clicked(state)) {
            if (self.last_clicked_tile == tile.node) {
                self.last_clicked_tile = null;
                try self.scenes.openScene(item.path);
            } else {
                self.last_clicked_tile = tile.node;
            }
            return;
        }
    }

    const next_columns = self.columnsForWidth(state);
    if (next_columns != self.grid_columns) {
        self.grid_columns = next_columns;
        try self.rebuildList(state);
        return;
    }

    self.frames_since_refresh +|= 1;
    if (self.frames_since_refresh >= refresh_interval_frames) try self.refresh(state, false);

    if (self.navigation.hovered(state)) {
        state.requestCursor(.hand);
        return;
    }
    for (self.tiles.items) |tile| {
        if (tile.hovered(state)) {
            state.requestCursor(.hand);
            return;
        }
    }
}

pub fn unmount(self: *Assets, state: *ui.Ui) void {
    state.destroySubtree(self.root_node);
    self.root_node = ui.invalid_node;
    self.body_node = ui.invalid_node;
    self.list_node = ui.invalid_node;
    self.tiles.clearRetainingCapacity();
}

pub fn root(self: *const Assets) ui.NodeId {
    return self.root_node;
}

fn refresh(self: *Assets, state: *ui.Ui, force_rebuild: bool) !void {
    self.frames_since_refresh = 0;
    var listing = try self.project.listDirectory(self.currentPath());
    var next = listing.items;
    listing.items = .empty;
    listing.deinit();
    errdefer deinitItems(self.allocator, &next);
    std.mem.sort(Item, next.items, {}, lessThanItem);

    if (itemsEqual(self.items.items, next.items)) {
        deinitItems(self.allocator, &next);
        if (force_rebuild or self.list_node == ui.invalid_node) try self.rebuildList(state);
        return;
    }

    deinitItems(self.allocator, &self.items);
    self.items = next;
    try self.rebuildList(state);
}

fn rebuildList(self: *Assets, state: *ui.Ui) !void {
    if (self.list_node != ui.invalid_node) state.destroySubtree(self.list_node);
    self.tiles.clearRetainingCapacity();
    try self.navigation.sync(
        state,
        self.currentPath(),
        self.history_index > 0,
        self.history_index + 1 < self.history.items.len,
    );

    const list_node = try ui.widgets.column(state, self.body_node, .{
        .width = .fill,
        .height = .hug,
        .gap = grid_gap,
        .background = .transparent,
    });
    errdefer state.destroySubtree(list_node);

    var item_index: usize = 0;
    while (item_index < self.items.items.len) {
        const row = try ui.widgets.row(state, list_node, .{
            .width = .fill,
            .height = .{ .px = AssetTile.height },
            .gap = grid_gap,
            .background = .transparent,
        });
        var column: usize = 0;
        while (column < self.grid_columns and item_index < self.items.items.len) : (column += 1) {
            const tile = try AssetTile.init(state, row, self.items.items[item_index], self.icons, self.currentPath());
            try self.tiles.append(self.allocator, tile);
            item_index += 1;
        }
    }
    self.list_node = list_node;
}

fn columnsForWidth(self: *const Assets, state: *const ui.Ui) usize {
    const body = state.bounds(self.body_node) orelse return self.grid_columns;
    const usable_width = @max(0, body.w - 14);
    return @max(1, @as(usize, @intFromFloat(@floor((usable_width + grid_gap) / (AssetTile.width + grid_gap)))));
}

fn ensureHistory(self: *Assets) !void {
    if (self.history.items.len != 0) return;
    try self.history.append(self.allocator, try self.allocator.dupe(u8, ""));
    self.history_index = 0;
}

fn resetProjectNavigation(self: *Assets) void {
    deinitItems(self.allocator, &self.items);
    self.items = .empty;
    for (self.history.items) |path| self.allocator.free(path);
    self.history.clearRetainingCapacity();
    self.history_index = 0;
    self.last_clicked_tile = null;
}

fn navigateTo(self: *Assets, state: *ui.Ui, path: []const u8) !void {
    while (self.history.items.len > self.history_index + 1) self.allocator.free(self.history.pop().?);
    try self.history.append(self.allocator, try self.allocator.dupe(u8, path));
    self.history_index = self.history.items.len - 1;
    self.resetScroll(state);
    try self.refresh(state, true);
}

fn resetScroll(self: *Assets, state: *ui.Ui) void {
    if (state.tree.get(self.body_node)) |body| {
        body.scroll_offset = .{};
        body.scroll_target_offset = .{};
    }
}

fn currentPath(self: *const Assets) []const u8 {
    return self.history.items[self.history_index];
}

fn deinitItems(allocator: std.mem.Allocator, items: *std.ArrayList(Item)) void {
    for (items.items) |item| allocator.free(item.path);
    items.deinit(allocator);
}

fn itemsEqual(first: []const Item, second: []const Item) bool {
    if (first.len != second.len) return false;
    for (first, second) |a, b| {
        if (a.kind != b.kind or !std.mem.eql(u8, a.path, b.path)) return false;
    }
    return true;
}

fn lessThanItem(_: void, a: Item, b: Item) bool {
    if (a.kind != b.kind) return a.kind == .folder;
    return std.mem.order(u8, a.path, b.path) == .lt;
}
