const native_ui = @import("zGUI_native");
const zp = @import("zephyr_runtime");
const ui = @import("zGUI");
const std = @import("std");

const Backend = @import("../ui/zgui_runtime_backend.zig");
const ViewportTarget = @import("../viewport_target.zig");
const SceneController = @import("scene_controller.zig");
const Icons = @import("../icons/editor_icons.zig");
const ProjectState = @import("project_state.zig");
const EditorUi = @import("../ui/editor_ui.zig");
const viewport = @import("../ui/viewport.zig");
const EditorContext = @import("context.zig");
const log = @import("../utilities/log.zig");
const actions = @import("actions.zig");
const Game = @import("../game.zig");

const Runtime = zp.Runtime(Game.definition);
pub const EditorApplication = @This();

project: ProjectState,
app: *zp.Application(Game.definition),
io: std.Io,
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator, io: std.Io, root_path: []const u8) !EditorApplication {
    var project = try ProjectState.init(allocator, io, root_path);
    errdefer project.deinit(allocator, io);

    const App = zp.Application(Game.definition);
    const app = try App.init(allocator, io, .{
        .width = null,
        .height = null,
        .title = "Zephyr Editor",
    }, project.project);

    return .{
        .project = project,
        .app = app,
        .io = io,
        .allocator = allocator,
    };
}

pub fn deinit(self: *EditorApplication) void {
    self.app.deinit();
    self.project.deinit(self.allocator, self.io);
    self.* = undefined;
}

pub fn run(self: *EditorApplication) !void {
    const app = self.app;
    const native_ui_scale = xwaylandScaleFactor();
    app.setDebugStatsEnabled(true);
    try app.start();

    const editor_context = try EditorContext.create(
        self.allocator,
        self.io,
        self.project.project,
        app.runtime,
    );
    defer editor_context.destroy();

    var native_menu_context = NativeMenuContext{ .registry = editor_context.actionRegistry(), .window = app.window };
    const window_handle = try app.window.nativeMenuWindowHandle();
    var native_menu = try native_ui.NativeMenu.init(window_handle, "Zephyr Editor", &native_menu_context, nativeMenuAction);
    defer native_menu.deinit();

    const file = try native_menu.addMenu("File");
    try native_menu.addItem(file, "New Project", actions.ids.new_project);
    try native_menu.addItem(file, "Open Project", actions.ids.open_project);
    try native_menu.addItem(file, "Save", actions.ids.save_project);

    var ui_renderer = try ui.OpenGlRenderer.init(self.allocator, zp.Window.getProcAddress);
    defer ui_renderer.deinit();

    const font_bytes = @embedFile("../resources/fonts/Inter-Regular.ttf");
    var font_atlas = try ui.FontAtlas.init(self.allocator, font_bytes, 1024, 1024);
    defer font_atlas.deinit();
    try font_atlas.prewarmAscii(&.{ 10, 11, 12, 13, 14, 16, 18 }, native_ui_scale);

    var icons = try Icons.init(&ui_renderer, self.allocator);
    defer icons.deinit(&ui_renderer);

    var ui_state = try ui.Ui.init(self.allocator);
    defer ui_state.deinit();
    ui_state.setFontAtlas(&font_atlas);

    var viewport_target = try ViewportTarget.init(&app.runtime.renderer.device);
    defer viewport_target.deinit();

    var viewport_texture = try ui_renderer.registerExternalTexture(viewport_target.nativeTextureId());
    defer ui_renderer.destroyTexture(&viewport_texture);
    var viewport_binding = viewport.TextureBinding{ .texture = viewport_texture };

    var editor = try EditorUi.init(self.allocator, &ui_state, .{
        .context = editor_context,
        .viewport_texture = &viewport_binding,
        .icons = icons,
    });
    defer editor.deinit(&ui_state);

    var ui_backend = Backend.init(self.allocator, &ui_renderer);
    defer ui_backend.deinit();

    while (app.window.shouldCloseWindow()) {
        native_menu.poll();

        if (editor_context.takeCommand()) |command| switch (command) {
            .switch_project => |root_path| {
                self.switchProject(
                    root_path,
                    editor_context,
                    &ui_renderer,
                    &viewport_target,
                    &viewport_texture,
                    &viewport_binding,
                ) catch |err| log.err("Failed to switch project: {}", .{err});
                self.allocator.free(root_path);
            },
        };

        const window_size = app.window.getWindowSize();
        const runtime_events = app.beginFrame();
        const frame = try ui_backend.beginFrame(.{
            .window = app.window,
            .window_size = Backend.toUiSize(window_size, native_ui_scale),
            .framebuffer_size = Backend.toPixelSize(app.window.getFramebufferSize()),
            .ui_scale = native_ui_scale,
            .dt = app.deltaTime(),
        }, runtime_events);
        try ui_state.beginFrame(frame.toBeginFrame());

        _ = try editor.dockSpace(&ui_state, frame.window_size);
        try editor.update(&ui_state, .{ .debug_stats = app.debugStats() });
        Backend.setCursor(app.window, ui_state.requestedCursor());

        ui_state.setTextRasterScale(frame.text_raster_scale);
        try ui_state.endFrame();
        // endFrame can lazily rasterize new glyphs; upload them before this
        // frame's draw instead of leaving them blank until the next frame.
        try ui_renderer.syncFontAtlas(&font_atlas);

        const viewport_rect = editor.viewportRect();
        _ = try viewport_target.ensureSize(viewport_rect, frame.text_raster_scale);
        var input_capture = ui_state.inputCapture();
        input_capture.wants_mouse = input_capture.wants_mouse or editor.isInteracting();
        editor_context.sceneController().sceneInputCapture().processSceneEvents(
            app.input(),
            runtime_events,
            viewport_rect,
            ui_state.mousePosition(),
            input_capture,
        );

        switch (editor_context.sceneController().playState()) {
            .Play => try app.update(),
            .Pause, .Stop => try app.updateWithSchedule(Game.editor_schedule_override),
        }
        if (viewport_target.renderTarget()) |target| try app.renderScene(target);

        try ui_renderer.render(ui_state.drawData());
        try ui_renderer.endFrame();
        app.present();
    }
}

fn switchProject(
    self: *EditorApplication,
    root_path: []const u8,
    editor_context: *EditorContext,
    ui_renderer: *ui.OpenGlRenderer,
    viewport_target: *ViewportTarget,
    viewport_texture: *ui.TextureHandle,
    viewport_binding: *viewport.TextureBinding,
) !void {
    var next_project = try ProjectState.init(self.allocator, self.io, root_path);
    errdefer next_project.deinit(self.allocator, self.io);

    const next_runtime = try Runtime.init(self.allocator, self.io, next_project.project);
    errdefer next_runtime.deinit();
    try next_runtime.start();
    next_runtime.setDebugStatsEnabled(true);

    const next_playback = try SceneController.preparePlayback(next_runtime);
    var next_viewport_target = try ViewportTarget.init(&next_runtime.renderer.device);
    errdefer next_viewport_target.deinit();
    var next_viewport_texture = try ui_renderer.registerExternalTexture(next_viewport_target.nativeTextureId());
    errdefer ui_renderer.destroyTexture(&next_viewport_texture);

    const previous_runtime = self.app.runtime;
    var previous_project = self.project;
    var previous_viewport_target = viewport_target.*;
    var previous_viewport_texture = viewport_texture.*;

    self.project = next_project;
    self.app.runtime = next_runtime;
    viewport_target.* = next_viewport_target;
    viewport_texture.* = next_viewport_texture;
    viewport_binding.replace(next_viewport_texture);
    editor_context.rebind(self.project.project, next_runtime, next_playback);

    ui_renderer.destroyTexture(&previous_viewport_texture);
    previous_viewport_target.deinit();
    previous_runtime.deinit();
    previous_project.deinit(self.allocator, self.io);
}

const NativeMenuContext = struct {
    registry: *actions.Registry,
    window: *zp.Window,
};

fn nativeMenuAction(context: ?*anyopaque, action: native_ui.ActionId) callconv(.c) void {
    const native_menu_context: *NativeMenuContext = @ptrCast(@alignCast(context.?));
    if (action == native_ui.close_action) {
        native_menu_context.window.requestClose();
        return;
    }
    _ = native_menu_context.registry.invoke(action) catch |err| {
        log.err("failed to invoke action: {}", .{err});
    };
}

fn xwaylandScaleFactor() f32 {
    return if (@import("builtin").os.tag == .linux and std.c.getenv("WAYLAND_DISPLAY") != null) 2 else 1;
}

test {
    _ = @import("actions.zig");
    _ = @import("context.zig");
    _ = @import("project_state.zig");
    _ = @import("scene_controller.zig");
    _ = @import("scene_mutation.zig");
}
