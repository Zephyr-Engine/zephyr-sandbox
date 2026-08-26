const std = @import("std");
const ui = @import("zGUI");

const EditorIcons = @import("../icons/editor_icons.zig");
const EditorContext = @import("../editor/context.zig");
const Workspace = @import("workspace.zig");
const inspector = @import("inspector.zig");
const viewport = @import("viewport.zig");
const console = @import("console.zig");
const assets = @import("assets.zig");
const panel = @import("panel.zig");
const scene = @import("scene.zig");

const min_side_width: f32 = 190;
const min_center_width: f32 = 240;
const min_bottom_height: f32 = 96;
const min_main_height: f32 = 240;

const EditorUi = @This();

workspace: Workspace,

pub const Dependencies = struct {
    context: *EditorContext,
    viewport_texture: *const viewport.TextureBinding,
    icons: EditorIcons,
};

pub fn init(
    allocator: std.mem.Allocator,
    state: *ui.Ui,
    dependencies: Dependencies,
) !EditorUi {
    const ctx = dependencies.context;
    const icons = dependencies.icons;
    var workspace = try Workspace.init(
        allocator,
        state,
        .{ .actions = ctx.actionRegistry() },
    );
    errdefer workspace.deinit(state);

    const scene_window = try addPanel(&workspace, state, scene.descriptor, scene.init(.{
        .allocator = allocator,
        .scenes = ctx.sceneController(),
        .icons = .{
            .camera = icons.camera,
            .model = icons.model,
        },
    }));
    const viewport_window = try addPanel(&workspace, state, viewport.descriptor, viewport.init(
        dependencies.viewport_texture,
        .{
            .play = icons.play,
            .pause = icons.pause,
            .stop = icons.stop,
        },
    ));

    const inspector_window = try addPanel(&workspace, state, inspector.descriptor, inspector.init(.{
        .allocator = allocator,
        .scenes = ctx.sceneController(),
        .icons = .{ .component_menu = icons.component_menu },
    }));

    const assets_window = try addPanel(&workspace, state, assets.descriptor, assets.init(.{
        .allocator = allocator,
        .project = ctx.projectModel(),
        .scenes = ctx.sceneController(),
        .icons = .{
            .folder = icons.folder,
            .file = icons.file,
        },
    }));
    const console_window = try addPanel(&workspace, state, console.descriptor, console.init());

    try createDefaultLayout(&workspace.dock, .{
        .scene = scene_window,
        .viewport = viewport_window,
        .inspector = inspector_window,
        .assets = assets_window,
        .console = console_window,
    });

    return .{ .workspace = workspace };
}

pub fn deinit(self: *EditorUi, state: *ui.Ui) void {
    self.workspace.deinit(state);
}

pub fn update(self: *EditorUi, state: *ui.Ui, frame: panel.Frame) !void {
    try self.workspace.update(state, frame);
}

pub fn dockSpace(self: *EditorUi, state: *ui.Ui, window_size: ui.Vec2) !ui.DockSpaceResult {
    return self.workspace.run(state, window_size);
}

pub fn openPanel(self: *EditorUi, state: *ui.Ui, id: panel.Id) !ui.DockWindowId {
    return self.workspace.openPanel(state, id);
}

pub fn closePanel(self: *EditorUi, state: *ui.Ui, id: panel.Id) !void {
    try self.workspace.closePanel(state, id);
}

pub fn viewportRect(self: *const EditorUi) ui.Rect {
    return self.workspace.contentRect(viewport.panel_id) orelse .{};
}

pub fn isInteracting(self: *const EditorUi) bool {
    return self.workspace.dock.isInteracting();
}

fn addPanel(workspace: *Workspace, state: *ui.Ui, descriptor: panel.Descriptor, value: anytype) !ui.DockWindowId {
    var instance = try panel.Instance.create(workspace.allocator, descriptor, value);
    errdefer instance.deinit(state);
    return workspace.registerPanel(state, &instance);
}

const DefaultWindows = struct {
    scene: ui.DockWindowId,
    viewport: ui.DockWindowId,
    inspector: ui.DockWindowId,
    assets: ui.DockWindowId,
    console: ui.DockWindowId,
};

fn createDefaultLayout(dock: *ui.DockSpace, windows: DefaultWindows) !void {
    try dock.moveWindowToLeaf(windows.viewport, dock.rootLeaf());

    const right = try dock.splitNode(dock.rootLeaf(), .right, 0.72);
    try dock.setSplitMinimums(right.split, min_center_width + min_side_width, min_side_width);
    try dock.moveWindowToLeaf(windows.inspector, right.new_leaf);

    const bottom = try dock.splitNode(right.old_node, .bottom, 0.74);
    try dock.setSplitMinimums(bottom.split, min_main_height, min_bottom_height);
    try dock.moveWindowToLeaf(windows.assets, bottom.new_leaf);
    try dock.moveWindowToLeaf(windows.console, bottom.new_leaf);
    _ = dock.dock.setActiveWindow(bottom.new_leaf, windows.assets);

    const left = try dock.splitNode(bottom.old_node, .left, 0.2);
    try dock.setSplitMinimums(left.split, min_side_width, min_center_width);
    try dock.moveWindowToLeaf(windows.scene, left.new_leaf);
}
