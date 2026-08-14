const zp = @import("zephyr_runtime");
const std = @import("std");
const ui = @import("zGUI");

const panel = @import("panel.zig");

pub const panel_id = panel.id("editor.assets");
pub const descriptor: panel.Descriptor = .{
    .id = panel_id,
    .title = "Assets",
    .min_size = .{ .x = 240, .y = 96 },
};

pub const Icons = struct {
    folder: ui.TextureHandle,
    file: ui.TextureHandle,
};

const ItemKind = enum {
    folder,
    file,
};

const Item = struct {
    path: []u8,
    kind: ItemKind,
};

const refresh_interval_frames = 300;
const grid_tile_width: f32 = 112;
const grid_tile_height: f32 = 118;
const grid_gap: f32 = 8;

const Assets = @This();

allocator: std.mem.Allocator,
project: *const zp.Project,
io: std.Io,
icons: Icons,
items: std.ArrayList(Item) = .empty,
history: std.ArrayList([]u8) = .empty,
history_index: usize = 0,
root_node: ui.NodeId = ui.invalid_node,
body_node: ui.NodeId = ui.invalid_node,
list_node: ui.NodeId = ui.invalid_node,
back_button: ui.NodeId = ui.invalid_node,
forward_button: ui.NodeId = ui.invalid_node,
path_label: ui.NodeId = ui.invalid_node,
tile_nodes: std.ArrayList(ui.NodeId) = .empty,
grid_columns: usize = 1,
frames_since_refresh: u16 = refresh_interval_frames,

pub fn init(allocator: std.mem.Allocator, project: *const zp.Project, io: std.Io, icons: Icons) Assets {
    return .{
        .allocator = allocator,
        .project = project,
        .io = io,
        .icons = icons,
    };
}

pub fn deinit(self: *Assets) void {
    deinitItems(self.allocator, &self.items);
    for (self.history.items) |path| self.allocator.free(path);
    self.history.deinit(self.allocator);
    self.tile_nodes.deinit(self.allocator);
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

    const header = try ui.widgets.row(state, root_node, .{
        .width = .fill,
        .height = .{ .px = 42 },
        .gap = 4,
        .padding = .{ .left = 10, .right = 14, .top = 6, .bottom = 6 },
        .background = .shell,
    });
    const back_button = try navigationButton(state, header, "‹");
    const forward_button = try navigationButton(state, header, "›");
    _ = try ui.widgets.text(state, header, "PROJECT ASSETS", .{
        .width = .{ .px = 102 },
        .height = .fill,
        .padding = .{ .left = 6, .top = 7 },
        .color = .text_dim,
        .size = 11,
    });
    const path_label = try ui.widgets.text(state, header, "", .{
        .width = .fill,
        .height = .fill,
        .padding = .{ .left = 2, .top = 7 },
        .size = 12,
        .color = .text_muted,
    });
    _ = try ui.widgets.divider(state, root_node);

    const body_node = try ui.widgets.column(state, root_node, .{
        .width = .fill,
        .height = .fill,
        .padding = .{ .left = 8, .right = 8, .top = 8, .bottom = 10 },
        .background = .shell,
        .overflow_y = .scroll,
    });

    self.root_node = root_node;
    self.body_node = body_node;
    self.back_button = back_button;
    self.forward_button = forward_button;
    self.path_label = path_label;
    self.frames_since_refresh = refresh_interval_frames;
    try self.ensureHistory();
    try self.refresh(state, true);
}

pub fn update(self: *Assets, state: *ui.Ui, _: panel.Frame) !void {
    if (state.clicked(self.back_button) and self.history_index > 0) {
        self.history_index -= 1;
        self.resetScroll(state);
        try self.refresh(state, true);
        return;
    }
    if (state.clicked(self.forward_button) and self.history_index + 1 < self.history.items.len) {
        self.history_index += 1;
        self.resetScroll(state);
        try self.refresh(state, true);
        return;
    }

    for (self.tile_nodes.items, self.items.items) |tile, item| {
        if (item.kind == .folder and state.clicked(tile)) {
            try self.navigateTo(state, item.path);
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
    if (self.frames_since_refresh >= refresh_interval_frames) {
        try self.refresh(state, false);
    }

    if (state.interaction(self.back_button).hovered or state.interaction(self.forward_button).hovered) {
        state.requestCursor(.hand);
        return;
    }
    for (self.tile_nodes.items) |tile| {
        if (state.interaction(tile).hovered) {
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
    self.back_button = ui.invalid_node;
    self.forward_button = ui.invalid_node;
    self.path_label = ui.invalid_node;
    self.tile_nodes.clearRetainingCapacity();
}

pub fn root(self: *const Assets) ui.NodeId {
    return self.root_node;
}

fn refresh(self: *Assets, state: *ui.Ui, force_rebuild: bool) !void {
    self.frames_since_refresh = 0;
    var next: std.ArrayList(Item) = .empty;
    errdefer deinitItems(self.allocator, &next);

    try self.collectCurrentDirectory(&next);
    std.mem.sort(Item, next.items, {}, lessThanItem);

    if (itemsEqual(self.items.items, next.items)) {
        deinitItems(self.allocator, &next);
        if (force_rebuild or self.list_node == ui.invalid_node) {
            try self.rebuildList(state);
        }
        return;
    }

    deinitItems(self.allocator, &self.items);
    self.items = next;
    try self.rebuildList(state);
}

fn collectCurrentDirectory(self: *Assets, items: *std.ArrayList(Item)) !void {
    const path = self.currentPath();
    if (path.len == 0) {
        try appendItem(self.allocator, items, self.project.manifest.assets_dir, .folder);
        try appendItem(self.allocator, items, self.project.manifest.scenes_dir, .folder);
        return;
    }

    var dir = std.Io.Dir.openDir(self.project.root_dir, self.io, path, .{ .iterate = true }) catch return;
    defer dir.close(self.io);
    var iter = dir.iterate();
    while (try iter.next(self.io)) |entry| {
        const kind: ItemKind = if (entry.kind == .directory) .folder else .file;
        const entry_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ path, entry.name });
        errdefer self.allocator.free(entry_path);
        try items.append(self.allocator, .{ .path = entry_path, .kind = kind });
    }
}

fn rebuildList(self: *Assets, state: *ui.Ui) !void {
    if (self.list_node != ui.invalid_node) {
        state.destroySubtree(self.list_node);
    }
    self.tile_nodes.clearRetainingCapacity();

    try state.setText(self.path_label, if (self.currentPath().len == 0) "Project folders" else self.currentPath());
    try syncNavigationButton(state, self.back_button, self.history_index > 0);
    try syncNavigationButton(state, self.forward_button, self.history_index + 1 < self.history.items.len);

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
            .height = .{ .px = grid_tile_height },
            .gap = grid_gap,
            .background = .transparent,
        });
        var column: usize = 0;
        while (column < self.grid_columns and item_index < self.items.items.len) : (column += 1) {
            try self.addTile(state, row, self.items.items[item_index]);
            item_index += 1;
        }
    }

    self.list_node = list_node;
}

fn addTile(self: *Assets, state: *ui.Ui, parent: ui.NodeId, item: Item) !void {
    const tile = try ui.widgets.button(state, parent, "", state.theme.style(.{
        .width = .{ .px = grid_tile_width },
        .height = .{ .px = grid_tile_height },
        .padding = .{ .left = 8, .right = 8, .top = 8, .bottom = 7 },
        .gap = 2,
        .direction = .column,
        .background = .transparent,
        .border = .transparent,
        .radius = .control,
    }));
    var tile_style = state.nodeStyle(tile).?;
    tile_style.hover_background = ui.Color.rgba(255, 255, 255, 18);
    tile_style.hover_border_color = ui.Color.rgba(139, 92, 246, 150);
    tile_style.pressed_background = ui.Color.rgba(139, 92, 246, 50);
    tile_style.pressed_border_color = ui.Color.rgba(167, 139, 250, 220);
    tile_style.border_width = 1;
    try state.setStyle(tile, tile_style);
    try self.tile_nodes.append(self.allocator, tile);

    const thumbnail = try ui.widgets.row(state, tile, .{
        .width = .fill,
        .height = .{ .px = 62 },
        .background = .transparent,
    });

    _ = try ui.widgets.spacer(state, thumbnail);
    _ = try ui.widgets.image(state, thumbnail, .{
        .texture = if (item.kind == .folder) self.icons.folder else self.icons.file,
        .style = state.theme.style(.{
            .width = .{ .px = 58 },
            .height = .{ .px = 58 },
            .background = .transparent,
        }),
    });

    _ = try ui.widgets.spacer(state, thumbnail);
    var name_buffer: [16]u8 = undefined;
    var type_buffer: [16]u8 = undefined;
    try centeredLabel(
        state,
        tile,
        shortenedLabel(std.fs.path.basename(item.path), &name_buffer),
        .text,
        12,
        18,
    );
    try centeredLabel(
        state,
        tile,
        shortenedLabel(if (item.kind == .folder) folderKindLabel(self.currentPath()) else fileKindLabel(item.path), &type_buffer),
        .text_muted,
        10,
        13,
    );
}

fn centeredLabel(state: *ui.Ui, parent: ui.NodeId, label: []const u8, color: ui.ColorRole, size: f32, height: f32) !void {
    const row = try ui.widgets.row(state, parent, .{
        .width = .fill,
        .height = .{ .px = height },
        .background = .transparent,
    });
    _ = try ui.widgets.spacer(state, row);
    _ = try ui.widgets.text(state, row, label, .{
        .width = .hug,
        .height = .fill,
        .color = color,
        .size = size,
    });
    _ = try ui.widgets.spacer(state, row);
}

fn columnsForWidth(self: *const Assets, state: *const ui.Ui) usize {
    const body = state.bounds(self.body_node) orelse return self.grid_columns;
    const usable_width = @max(0, body.w - 16);
    return @max(1, @as(usize, @intFromFloat(@floor((usable_width + grid_gap) / (grid_tile_width + grid_gap)))));
}

fn navigationButton(state: *ui.Ui, parent: ui.NodeId, label: []const u8) !ui.NodeId {
    const button = try ui.widgets.button(state, parent, label, state.theme.style(.{
        .width = .{ .px = 22 },
        .height = .{ .px = 26 },
        .padding = .{ .left = 6, .top = 4 },
        .background = .transparent,
        .border = .transparent,
        .radius = .control,
        .font_size = 14,
    }));
    var style = state.nodeStyle(button).?;
    style.hover_background = ui.Color.rgba(255, 255, 255, 18);
    style.pressed_background = ui.Color.rgba(139, 92, 246, 45);
    try state.setStyle(button, style);
    return button;
}

fn syncNavigationButton(state: *ui.Ui, button: ui.NodeId, enabled: bool) !void {
    var style = state.nodeStyle(button).?;
    style.foreground = if (enabled) ui.Color.rgba(210, 212, 221, 255) else ui.Color.rgba(91, 94, 106, 255);
    style.hover_background = if (enabled) ui.Color.rgba(255, 255, 255, 18) else null;
    style.pressed_background = if (enabled) ui.Color.rgba(139, 92, 246, 45) else null;

    try state.setStyle(button, style);
    try state.setInteractive(button, enabled);
}

fn ensureHistory(self: *Assets) !void {
    if (self.history.items.len != 0) {
        return;
    }

    try self.history.append(self.allocator, try self.allocator.dupe(u8, ""));
    self.history_index = 0;
}

fn navigateTo(self: *Assets, state: *ui.Ui, path: []const u8) !void {
    while (self.history.items.len > self.history_index + 1) {
        self.allocator.free(self.history.pop().?);
    }

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

fn appendItem(allocator: std.mem.Allocator, items: *std.ArrayList(Item), path: []const u8, kind: ItemKind) !void {
    try items.append(allocator, .{
        .path = try allocator.dupe(u8, path),
        .kind = kind,
    });
}

fn deinitItems(allocator: std.mem.Allocator, items: *std.ArrayList(Item)) void {
    for (items.items) |item| {
        allocator.free(item.path);
    }
    items.deinit(allocator);
}

fn itemsEqual(first: []const Item, second: []const Item) bool {
    if (first.len != second.len) {
        return false;
    }

    for (first, second) |a, b| {
        if (a.kind != b.kind or !std.mem.eql(u8, a.path, b.path)) {
            return false;
        }
    }
    return true;
}

fn lessThanItem(_: void, a: Item, b: Item) bool {
    if (a.kind != b.kind) {
        return a.kind == .folder;
    }
    return std.mem.order(u8, a.path, b.path) == .lt;
}

fn fileKindLabel(path: []const u8) []const u8 {
    const extension = std.fs.path.extension(path);
    if (extension.len == 0) {
        return "FILE";
    }
    return extension[1..];
}

fn folderKindLabel(current_path: []const u8) []const u8 {
    return if (current_path.len == 0) "PROJECT FOLDER" else "FOLDER";
}

fn shortenedLabel(label: []const u8, buffer: *[16]u8) []const u8 {
    if (label.len <= buffer.len) {
        return label;
    }

    @memcpy(buffer[0..13], label[0..13]);
    @memcpy(buffer[13..16], "...");
    return buffer;
}
