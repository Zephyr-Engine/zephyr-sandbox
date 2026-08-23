const ui = @import("zGUI");

pub fn theme() ui.Theme {
    var value = ui.theme.zephyr_dark;
    // A cool, low-contrast slate foundation keeps scene content dominant while
    // the blue accent remains reserved for focus, selection, and primary work.
    value.palette.app = ui.Color.rgba(10, 12, 17, 255);
    value.palette.shell = ui.Color.rgba(15, 17, 24, 255);
    value.palette.panel = ui.Color.rgba(20, 23, 32, 255);
    value.palette.panel_soft = ui.Color.rgba(26, 30, 41, 255);
    value.palette.card = ui.Color.rgba(29, 33, 45, 255);
    value.palette.control = ui.Color.rgba(34, 39, 52, 255);
    value.palette.viewport = ui.Color.rgba(12, 15, 21, 255);
    value.palette.stroke = ui.Color.rgba(55, 62, 78, 255);
    value.palette.stroke_soft = ui.Color.rgba(39, 45, 58, 255);
    value.palette.overlay = ui.Color.rgba(13, 16, 23, 238);
    value.palette.overlay_soft = ui.Color.rgba(24, 28, 39, 232);
    value.palette.overlay_stroke = ui.Color.rgba(255, 255, 255, 30);
    value.palette.interaction_hover = ui.Color.rgba(255, 255, 255, 16);
    value.palette.interaction_pressed = ui.Color.rgba(255, 255, 255, 28);
    value.palette.text = ui.Color.rgba(242, 245, 250, 255);
    value.palette.text_dim = ui.Color.rgba(177, 186, 202, 255);
    value.palette.text_muted = ui.Color.rgba(119, 130, 150, 255);
    value.palette.icon = ui.Color.rgba(181, 191, 208, 255);
    value.palette.icon_selected = ui.Color.rgba(221, 234, 255, 255);
    value.palette.accent = ui.Color.rgba(59, 130, 246, 255);
    value.palette.accent_soft = ui.Color.rgba(22, 48, 87, 255);
    value.palette.accent_hover = ui.Color.rgba(59, 130, 246, 48);
    value.palette.accent_pressed = ui.Color.rgba(59, 130, 246, 72);
    value.palette.accent_border = ui.Color.rgba(96, 165, 250, 150);
    value.palette.accent_border_strong = ui.Color.rgba(147, 197, 253, 230);
    value.radius_tokens = .{
        .control = 7,
        .card = 9,
        .viewport = 10,
        .pill = 10,
        .round = 999,
    };
    value.space = .{
        .xxs = 2,
        .xs = 3,
        .sm = 5,
        .md = 8,
        .lg = 10,
        .xl = 12,
        .xxl = 16,
    };
    value.metrics = .{
        .control_height = 32,
        .compact_control_height = 26,
        .section_header_height = 38,
        .dock_tab_height = 28,
        .dock_handle_thickness = 3,
    };
    return value;
}

test "editor theme stays denser than the zGUI default" {
    const value = theme();
    try @import("std").testing.expect(value.radius_tokens.card < ui.theme.zephyr_dark.radius_tokens.card);
    try @import("std").testing.expect(value.metrics.control_height < ui.theme.zephyr_dark.metrics.control_height);
    try @import("std").testing.expect(value.space.lg < ui.theme.zephyr_dark.space.lg);
}
