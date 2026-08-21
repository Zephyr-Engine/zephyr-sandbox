const ui = @import("zGUI");

pub fn theme() ui.Theme {
    var value = ui.theme.zephyr_dark;
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
