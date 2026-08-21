const ui = @import("zGUI");

pub fn theme() ui.Theme {
    var value = ui.theme.zephyr_dark;
    value.palette.accent = ui.Color.rgba(0x42, 0x87, 0xf5, 255);
    value.palette.accent_soft = ui.Color.rgba(24, 48, 88, 255);
    value.palette.accent_hover = ui.Color.rgba(0x42, 0x87, 0xf5, 50);
    value.palette.accent_pressed = ui.Color.rgba(0x42, 0x87, 0xf5, 70);
    value.palette.accent_border = ui.Color.rgba(0x42, 0x87, 0xf5, 150);
    value.palette.accent_border_strong = ui.Color.rgba(110, 164, 247, 220);
    value.radius_tokens = .{
        .control = 6,
        .card = 7,
        .viewport = 9,
        .pill = 8,
        .round = 999,
    };
    value.space = .{
        .xxs = 2,
        .xs = 3,
        .sm = 5,
        .md = 7,
        .lg = 8,
        .xl = 10,
        .xxl = 14,
    };
    value.metrics = .{
        .control_height = 30,
        .compact_control_height = 24,
        .section_header_height = 36,
        .dock_tab_height = 24,
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
