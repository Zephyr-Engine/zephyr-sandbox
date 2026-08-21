const ui = @import("zGUI");
const zimp = @import("zimp");

const EnumSchema = zimp.scene.schema.EnumSchema;

pub const EnumField = struct {
    button: ui.NodeId,
    value: u32,
    schema: EnumSchema,

    pub fn init(state: *ui.Ui, parent: ui.NodeId, value: u32, schema: EnumSchema) !EnumField {
        const button = try ui.widgets.themedButton(state, parent, label(schema, value), .{
            .width = .fill,
            .height = .{ .px = state.theme.metrics.control_height },
            .variant = .neutral,
        });
        return .{ .button = button, .value = value, .schema = schema };
    }

    pub fn deinit(self: *EnumField, state: *ui.Ui) void {
        state.destroySubtree(self.button);
    }

    pub fn update(self: *EnumField, state: *ui.Ui) !bool {
        if (!state.activated(self.button) or self.schema.entries.len == 0) return false;

        var next_index: usize = 0;
        for (self.schema.entries, 0..) |entry, index| {
            if (entry.value == self.value) {
                next_index = (index + 1) % self.schema.entries.len;
                break;
            }
        }
        self.value = self.schema.entries[next_index].value;
        try state.setText(self.button, label(self.schema, self.value));
        return true;
    }

    fn label(schema: EnumSchema, value: u32) []const u8 {
        for (schema.entries) |entry| if (entry.value == value) return entry.name;
        return "Unknown value";
    }
};
