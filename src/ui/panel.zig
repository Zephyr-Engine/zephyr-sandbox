const std = @import("std");
const ui = @import("zGUI");
const zp = @import("zephyr_runtime");

const actions = @import("../editor/actions.zig");

pub const Id = u64;

pub fn id(comptime name: []const u8) Id {
    comptime var hash: u64 = 14695981039346656037;
    inline for (name) |byte| {
        hash = (hash ^ byte) *% 1099511628211;
    }
    return hash;
}

pub const Descriptor = struct {
    id: Id,
    title: []const u8,
    min_size: ui.Vec2,
};

pub const Services = struct {
    actions: *actions.Registry,
};

pub const Frame = struct {
    debug_stats: ?zp.DebugStats = null,
};

pub const Instance = struct {
    allocator: std.mem.Allocator,
    descriptor: Descriptor,
    object: *anyopaque,
    vtable: *const VTable,
    mounted: bool = false,

    const VTable = struct {
        mount: *const fn (*anyopaque, *ui.Ui, ui.NodeId, Services) anyerror!void,
        update: *const fn (*anyopaque, *ui.Ui, Frame) anyerror!void,
        unmount: *const fn (*anyopaque, *ui.Ui) void,
        root: *const fn (*const anyopaque) ui.NodeId,
        destroy: *const fn (*anyopaque, std.mem.Allocator) void,
    };

    pub fn create(allocator: std.mem.Allocator, descriptor: Descriptor, value: anytype) !Instance {
        const Panel = @TypeOf(value);
        const object = try allocator.create(Panel);
        object.* = value;
        return .{
            .allocator = allocator,
            .descriptor = descriptor,
            .object = object,
            .vtable = vtableFor(Panel),
        };
    }

    pub fn mount(self: *Instance, state: *ui.Ui, parent: ui.NodeId, services: Services) !void {
        if (self.mounted) {
            return error.PanelAlreadyMounted;
        }
        try self.vtable.mount(self.object, state, parent, services);
        self.mounted = true;
    }

    pub fn update(self: *Instance, state: *ui.Ui, frame: Frame) !void {
        if (!self.mounted) {
            return;
        }
        try self.vtable.update(self.object, state, frame);
    }

    pub fn unmount(self: *Instance, state: *ui.Ui) void {
        if (!self.mounted) {
            return;
        }
        self.vtable.unmount(self.object, state);
        self.mounted = false;
    }

    pub fn root(self: *const Instance) ui.NodeId {
        return if (self.mounted) self.vtable.root(self.object) else ui.invalid_node;
    }

    pub fn deinit(self: *Instance, state: *ui.Ui) void {
        self.unmount(state);
        self.vtable.destroy(self.object, self.allocator);
        self.* = undefined;
    }

    fn vtableFor(comptime Panel: type) *const VTable {
        return &struct {
            const vtable: VTable = .{
                .mount = mountPanel,
                .update = updatePanel,
                .unmount = unmountPanel,
                .root = panelRoot,
                .destroy = destroyPanel,
            };

            fn mountPanel(raw: *anyopaque, state: *ui.Ui, parent: ui.NodeId, services: Services) !void {
                try cast(raw).mount(state, parent, services);
            }

            fn updatePanel(raw: *anyopaque, state: *ui.Ui, frame: Frame) !void {
                try cast(raw).update(state, frame);
            }

            fn unmountPanel(raw: *anyopaque, state: *ui.Ui) void {
                cast(raw).unmount(state);
            }

            fn panelRoot(raw: *const anyopaque) ui.NodeId {
                const object: *const Panel = @ptrCast(@alignCast(raw));
                return object.root();
            }

            fn destroyPanel(raw: *anyopaque, allocator: std.mem.Allocator) void {
                const object = cast(raw);
                if (@hasDecl(Panel, "deinit")) object.deinit();
                allocator.destroy(object);
            }

            fn cast(raw: *anyopaque) *Panel {
                return @ptrCast(@alignCast(raw));
            }
        }.vtable;
    }
};
