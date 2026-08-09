const native_ui = @import("zGUI_native");
const zp = @import("zephyr_runtime");
const ui = @import("zGUI");
const std = @import("std");

const Backend = @import("../ui/zgui_runtime_backend.zig");
const ViewportTarget = @import("../viewport_target.zig");
const Icons = @import("../icons/editor_icons.zig");
const EditorUi = @import("../ui/editor_ui.zig");
const EditorContext = @import("context.zig");
const actions = @import("actions.zig");
const Game = @import("../game.zig");

pub fn run(allocator: std.mem.Allocator, io: std.Io, project: *const zp.Project) !void {
    const App = zp.Application(Game.definition);
    const app = try App.init(allocator, io, .{
        .width = null,
        .height = null,
        .title = "Zephyr Editor",
    }, project);
    defer app.deinit();
    app.setDebugStatsEnabled(true);

    try app.start();

    const editor_context = try EditorContext.create(
        allocator,
        io,
        &app.runtime.world,
        &app.runtime.assets,
    );
    defer editor_context.destroy();

    var native_menu_context = NativeMenuContext{ .registry = editor_context.actionRegistry(), .window = app.window };
    const window_handle = try app.window.nativeMenuWindowHandle();
    var native_menu = try native_ui.NativeMenu.init(window_handle, "Zephyr Editor", &native_menu_context, nativeMenuAction);
    defer native_menu.deinit();

    const file = try native_menu.addMenu("File");
    try native_menu.addItem(file, "New Project", actions.ids.new_project);
    try native_menu.addItem(file, "Open Project", actions.ids.open_project);
    try native_menu.addItem(file, "Save Project", actions.ids.save_project);

    var ui_renderer = try ui.OpenGlRenderer.init(allocator, zp.Window.getProcAddress);
    defer ui_renderer.deinit();

    const font_bytes = @embedFile("../resources/fonts/Inter-Regular.ttf");
    var font_atlas = try ui.FontAtlas.init(allocator, font_bytes, 1024, 1024);
    defer font_atlas.deinit();

    var icons = try Icons.init(&ui_renderer, allocator);
    defer icons.deinit(&ui_renderer);

    var ui_state = try ui.Ui.init(allocator);
    defer ui_state.deinit();
    ui_state.setFontAtlas(&font_atlas);

    var viewport_target = try ViewportTarget.init(&app.runtime.renderer.device);
    defer viewport_target.deinit();

    var viewport_texture = try ui_renderer.registerExternalTexture(viewport_target.nativeTextureId());
    defer ui_renderer.destroyTexture(&viewport_texture);

    var editor = try EditorUi.init(allocator, &ui_state, editor_context.actionRegistry(), viewport_texture, .{
        .play = icons.play,
        .pause = icons.pause,
        .stop = icons.stop,
    });
    defer editor.deinit(&ui_state);

    var ui_backend = Backend.init(allocator, &ui_renderer);
    defer ui_backend.deinit();

    while (app.window.shouldCloseWindow()) {
        native_menu.poll();
        const window_size = app.window.getWindowSize();
        const native_ui_scale = @max(
            native_menu.scaleFactor(window_size.width),
            xwaylandScaleFactor(),
        );

        const runtime_events = app.beginFrame();
        const frame = try ui_backend.beginFrame(.{
            .window_size = Backend.toUiSize(window_size, native_ui_scale),
            .framebuffer_size = Backend.toPixelSize(app.window.getFramebufferSize()),
            .ui_scale = native_ui_scale,
            .dt = app.deltaTime(),
            .font_atlas = &font_atlas,
        }, runtime_events);
        try ui_state.beginFrame(frame.toBeginFrame());

        _ = try editor.dockSpace(&ui_state, frame.window_size);
        try editor.update(&ui_state, .{ .debug_stats = app.debugStats() });
        Backend.setCursor(app.window, ui_state.requestedCursor());

        ui_state.setTextRasterScale(frame.text_raster_scale);
        try ui_state.endFrame();

        const viewport_rect = editor.viewportRect();
        _ = try viewport_target.ensureSize(viewport_rect, frame.text_raster_scale);
        editor_context.sceneInputCapture().processSceneEvents(
            app.input(),
            runtime_events,
            viewport_rect,
            ui_state.mousePosition(),
            ui_state.inputCapture().wants_mouse or editor.isInteracting(),
        );

        switch (editor_context.playState()) {
            .Play => try app.update(),
            .Pause => try app.updateWithSchedule(Game.editor_schedule_override),
            .Stop => try app.updateWithSchedule(Game.editor_schedule_override),
        }
        if (viewport_target.renderTarget()) |target| {
            try app.renderScene(target);
        }

        try ui_renderer.render(ui_state.drawData());
        try ui_renderer.endFrame();
        app.present();
    }
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
    _ = native_menu_context.registry.invoke(action);
}

fn xwaylandScaleFactor() f32 {
    return if (@import("builtin").os.tag == .linux and @import("std").c.getenv("WAYLAND_DISPLAY") != null) 2 else 1;
}

test {
    _ = @import("actions.zig");
    _ = @import("command.zig");
    _ = @import("context.zig");
    _ = @import("session.zig");
}
