const std = @import("std");
const ui = @import("zGUI");
const zimp = @import("zimp");

const Value = zimp.scene.Value;

pub const ReferenceField = struct {
    field: ui.TextField,
    kind: Kind,
    invalid: bool = false,

    const Kind = enum { asset, entity };

    pub fn initAsset(
        allocator: std.mem.Allocator,
        state: *ui.Ui,
        parent: ui.NodeId,
        value: zimp.AssetId,
    ) !ReferenceField {
        const text = value.toString();
        return .{
            .field = try ui.TextField.init(allocator, state, parent, .{ .text = &text, .max_bytes = 36 }),
            .kind = .asset,
        };
    }

    pub fn initEntity(
        allocator: std.mem.Allocator,
        state: *ui.Ui,
        parent: ui.NodeId,
        value: zimp.SceneEntityId,
    ) !ReferenceField {
        const text = value.toString();
        return .{
            .field = try ui.TextField.init(allocator, state, parent, .{ .text = &text, .max_bytes = 36 }),
            .kind = .entity,
        };
    }

    pub fn deinit(self: *ReferenceField, state: *ui.Ui) void {
        self.field.deinit(state);
    }

    pub fn update(self: *ReferenceField, state: *ui.Ui) !?Value {
        const result = try self.field.update(state, .{ .max_bytes = 36, .invalid = self.invalid });
        if (!result.changed and !result.committed) return null;

        const value: Value = switch (self.kind) {
            .asset => .{ .asset_ref = zimp.AssetId.parse(self.field.text()) catch {
                self.invalid = true;
                return null;
            } },
            .entity => .{ .entity_ref = zimp.SceneEntityId.parse(self.field.text()) catch {
                self.invalid = true;
                return null;
            } },
        };
        self.invalid = false;
        return value;
    }
};
