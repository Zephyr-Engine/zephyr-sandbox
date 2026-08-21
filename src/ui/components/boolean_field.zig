const ui = @import("zGUI");

pub const BooleanField = struct {
    widget: ui.Checkbox,
    value: bool,

    pub fn init(state: *ui.Ui, parent: ui.NodeId, value: bool) !BooleanField {
        return .{
            .widget = try ui.Checkbox.init(state, parent, ""),
            .value = value,
        };
    }

    pub fn deinit(self: *BooleanField, state: *ui.Ui) void {
        self.widget.deinit(state);
    }

    pub fn update(self: *BooleanField, state: *ui.Ui) !bool {
        return self.widget.update(state, &self.value);
    }
};
