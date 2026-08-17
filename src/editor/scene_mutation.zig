const zp = @import("zephyr_runtime");
const zimp = @import("zimp");
const std = @import("std");

const SceneComponent = zimp.scene.SceneComponent;
const LoadedScene = zp.scene_schema.LoadedScene;
const SceneDocument = zimp.scene.SceneDocument;
const ComponentTypeId = zimp.ComponentTypeId;
const SceneEntity = zimp.scene.SceneEntity;
const SceneField = zimp.scene.SceneField;
const SceneEntityId = zimp.SceneEntityId;
const Value = zimp.scene.Value;

pub const DeletePolicy = enum {
    reject_if_children,
    reparent_children,
    delete_subtree,
};

const CreateEntity = struct {
    id: SceneEntityId,
    parent_id: ?SceneEntityId,
    name: []const u8,
};

const RenameEntity = struct {
    id: SceneEntityId,
    name: []const u8,
};

const DeleteEntity = struct {
    id: SceneEntityId,
    policy: DeletePolicy,
};

const ReparentEntity = struct {
    id: SceneEntityId,
    parent_id: ?SceneEntityId,
};

const SetActiveCamera = struct {
    id: ?SceneEntityId,
};

const AddComponent = struct {
    entity: SceneEntityId,
    component: SceneComponent,
};

const RemoveComponent = struct {
    entity: SceneEntityId,
    type_id: ComponentTypeId,
};

const SetField = struct {
    entity_id: SceneEntityId,
    type_id: ComponentTypeId,
    field_number: u32,
    value: Value,
};

const RemoveField = struct {
    entity_id: SceneEntityId,
    type_id: ComponentTypeId,
    field_number: u32,
};

pub const Mutation = union(enum) {
    create_entity: CreateEntity,
    rename_entity: RenameEntity,
    delete_entity: DeleteEntity,
    reparent_entity: ReparentEntity,
    set_active_camera: SetActiveCamera,
    add_component: AddComponent,
    remove_component: RemoveComponent,
    set_field: SetField,
    remove_field: RemoveField,

    pub fn apply(self: *const Mutation, scene: *LoadedScene) !void {
        return switch (self.*) {
            .create_entity => |create| applyCreateEntity(scene, create),
            .rename_entity => |rename| applyRenameEntity(scene, rename),
            .delete_entity => |delete| applyDeleteEntity(scene, delete),
            .reparent_entity => |reparent| applyReparentEntity(scene, reparent),
            .set_active_camera => |camera| applySetActiveCamera(scene, camera),
            .add_component => |add| applyAddComponent(scene, add),
            .remove_component => |remove| applyRemoveComponent(scene, remove),
            .set_field => |set| applySetField(scene, set),
            .remove_field => |remove| applyRemoveField(scene, remove),
        };
    }
};

fn requireEntity(scene: *LoadedScene, id: SceneEntityId) !usize {
    return scene.document.entityIndex(id) orelse error.MissingEntity;
}

fn applyCreateEntity(scene: *LoadedScene, input: CreateEntity) !void {
    if (input.id.isZero()) {
        return error.ZeroEntityId;
    }

    const scene_document = &scene.document;

    const entity_id = scene_document.entityIndex(input.id);
    if (entity_id != null) {
        return error.DuplicateEntityId;
    }

    if (input.parent_id) |parent_id| {
        if (scene_document.entityIndex(parent_id) == null) {
            return error.MissingParentEntity;
        }
    }

    const gpa = scene_document.arena.allocator();
    const new_entities = try gpa.alloc(
        SceneEntity,
        scene_document.entities.len + 1,
    );
    @memcpy(new_entities[0..scene_document.entities.len], scene_document.entities);

    const entity = SceneEntity{
        .id = input.id,
        .parent_id = input.parent_id,
        .name = try gpa.dupe(u8, input.name),
        .components = &.{},
        .prefab = .{},
    };

    new_entities[scene_document.entities.len] = entity;
    scene_document.entities = new_entities;

    _ = try scene.spawnEntity(entity);
}

fn applyRenameEntity(scene: *LoadedScene, input: RenameEntity) !void {
    const document = &scene.document;
    const index = try requireEntity(scene, input.id);
    document.entities[index].name = try document.arena.allocator().dupe(u8, input.name);
}

fn applyDeleteEntity(scene: *LoadedScene, input: DeleteEntity) !void {
    const document = &scene.document;
    const target_index = try requireEntity(scene, input.id);
    const target_parent_id = document.entities[target_index].parent_id;

    var deleted_count: usize = 0;
    for (document.entities) |entity| {
        const deleted = switch (input.policy) {
            .reject_if_children, .reparent_children => entity.id.eql(input.id),
            .delete_subtree => isInSubtree(scene, entity.id, input.id),
        };

        if (deleted) {
            deleted_count += 1;
        } else if (entity.parent_id) |parent_id| {
            if (parent_id.eql(input.id) and input.policy == .reject_if_children) {
                return error.EntityHasChildren;
            }
        }
    }

    for (document.entities) |entity| {
        if (isInDeletedSet(scene, entity.id, input)) {
            continue;
        }

        if (entity.prefab.source_entity) |source_entity| {
            if (!source_entity.isZero() and isInDeletedSet(scene, source_entity, input)) {
                return error.EntityStillReferenced;
            }
        }

        for (entity.components) |component| {
            for (component.fields) |field| {
                switch (field.value) {
                    .entity_ref => |reference| {
                        if (!reference.isZero() and isInDeletedSet(scene, reference, input)) {
                            return error.EntityStillReferenced;
                        }
                    },
                    else => {},
                }
            }
        }
    }

    const gpa = document.arena.allocator();
    const new_entities = try gpa.alloc(SceneEntity, document.entities.len - deleted_count);

    var next_index: usize = 0;
    for (document.entities) |entity| {
        if (isInDeletedSet(scene, entity.id, input)) {
            try scene.removeEntity(entity.id);
            continue;
        }

        new_entities[next_index] = entity;
        if (input.policy == .reparent_children) {
            if (new_entities[next_index].parent_id) |parent_id| {
                if (parent_id.eql(input.id)) {
                    new_entities[next_index].parent_id = target_parent_id;
                }
            }
        }
        next_index += 1;
    }

    document.entities = new_entities;
    if (document.active_camera) |active_camera| {
        if (isInDeletedSet(scene, active_camera, input)) {
            document.active_camera = null;
        }
    }
}

fn isInDeletedSet(scene: *const LoadedScene, id: SceneEntityId, input: DeleteEntity) bool {
    return switch (input.policy) {
        .reject_if_children, .reparent_children => id.eql(input.id),
        .delete_subtree => isInSubtree(scene, id, input.id),
    };
}

fn isInSubtree(scene: *const LoadedScene, id: SceneEntityId, subtree_root_id: SceneEntityId) bool {
    const document = &scene.document;
    var cursor: ?SceneEntityId = id;
    while (cursor) |current_id| {
        if (current_id.eql(subtree_root_id)) return true;
        const index = document.entityIndex(current_id) orelse return false;
        cursor = document.entities[index].parent_id;
    }
    return false;
}

fn wouldReparentCreateCycle(scene: *LoadedScene, entity_id: SceneEntityId, candidate_parent_id: SceneEntityId) bool {
    const document = &scene.document;
    var cursor: ?zimp.SceneEntityId = candidate_parent_id;

    while (cursor) |parent_id| {
        if (parent_id.eql(entity_id)) {
            return true;
        }

        const index = document.entityIndex(parent_id) orelse return false;
        cursor = document.entities[index].parent_id;
    }

    return false;
}

fn applyReparentEntity(scene: *LoadedScene, input: ReparentEntity) !void {
    const document = &scene.document;
    const index = try requireEntity(scene, input.id);

    if (input.parent_id) |parent_id| {
        if (document.entityIndex(parent_id) == null) {
            return error.MissingParentEntity;
        }
        if (wouldReparentCreateCycle(scene, input.id, parent_id)) {
            return error.EntityParentCycle;
        }
    }
    document.entities[index].parent_id = input.parent_id;
}

fn applySetActiveCamera(scene: *LoadedScene, input: SetActiveCamera) !void {
    if (input.id) |id| {
        _ = try requireEntity(scene, id);
    }
    scene.document.active_camera = input.id;
    try scene.setActiveCamera(input.id.?);
}

fn applyAddComponent(scene: *LoadedScene, input: AddComponent) !void {
    if (input.component.type_id.isZero()) {
        return error.ZeroComponentTypeId;
    }

    const entity_index = try requireEntity(scene, input.entity);
    const entity = &scene.document.entities[entity_index];

    if (entity.componentIndex(input.component.type_id) != null) {
        return error.DuplicateComponentTypeId;
    }

    const gpa = scene.document.arena.allocator();
    const new_components = try gpa.alloc(
        SceneComponent,
        entity.components.len + 1,
    );
    @memcpy(new_components[0..entity.components.len], entity.components);
    new_components[entity.components.len] = try input.component.clone(gpa);

    entity.components = new_components;
    try scene.addComponent(entity, input.component);
}

fn applyRemoveComponent(scene: *LoadedScene, input: RemoveComponent) !void {
    const entity_index = try requireEntity(scene, input.entity);
    const entity = &scene.document.entities[entity_index];

    const remove_index = entity.componentIndex(input.type_id) orelse {
        return error.MissingComponent;
    };

    const gpa = scene.document.arena.allocator();
    const new_components = try gpa.alloc(
        SceneComponent,
        entity.components.len - 1,
    );
    @memcpy(new_components[0..remove_index], entity.components[0..remove_index]);
    @memcpy(new_components[remove_index..], entity.components[remove_index + 1 ..]);

    entity.components = new_components;
    try scene.removeComponent(entity, input.type_id);
}

fn applySetField(scene: *LoadedScene, input: SetField) !void {
    if (input.field_number == 0) {
        return error.ZeroFieldNumber;
    }

    if (input.value == .none) {
        return error.InvalidFieldValue;
    }

    const entity_index = try requireEntity(scene, input.entity_id);
    const entity = &scene.document.entities[entity_index];
    const component_index = entity.componentIndex(input.type_id) orelse {
        return error.MissingComponent;
    };

    const component = &entity.components[component_index];
    const value = try input.value.clone(scene.document.arena.allocator());

    if (component.fieldIndex(input.field_number)) |index| {
        component.fields[index].value = value;
        try scene.setField(entity, input.type_id, input.field_number, value);
        return;
    }

    const gpa = scene.document.arena.allocator();
    const new_fields = try gpa.alloc(
        SceneField,
        component.fields.len + 1,
    );

    @memcpy(new_fields[0..component.fields.len], component.fields);
    new_fields[component.fields.len] = .{
        .number = input.field_number,
        .value = value,
    };

    component.fields = new_fields;
}

fn applyRemoveField(scene: *LoadedScene, input: RemoveField) !void {
    const entity_index = try requireEntity(scene, input.entity_id);
    const entity = &scene.document.entities[entity_index];
    const component_index = entity.componentIndex(input.type_id) orelse {
        return error.MissingComponent;
    };

    const component = &entity.components[component_index];
    const remove_index = component.fieldIndex(input.field_number) orelse {
        return error.MissingField;
    };

    const gpa = scene.document.arena.allocator();
    const new_fields = try gpa.alloc(
        SceneField,
        component.fields.len - 1,
    );
    @memcpy(new_fields[0..remove_index], component.fields[0..remove_index]);
    @memcpy(new_fields[remove_index..], component.fields[remove_index + 1 ..]);

    component.fields = new_fields;
}

const testing = std.testing;

const test_scene_id = zimp.SceneId.parseComptime("4f7a4c61-0a9f-479c-8da9-f86bf2a8c0d1");
const test_project_id = zimp.ProjectId.parseComptime("d3421676-c0eb-4f8c-a7ef-e1ad5faa789d");
const root_id = SceneEntityId.parseComptime("11111111-1111-4111-8111-111111111111");
const child_id = SceneEntityId.parseComptime("22222222-2222-4222-8222-222222222222");
const grandchild_id = SceneEntityId.parseComptime("33333333-3333-4333-8333-333333333333");
const created_id = SceneEntityId.parseComptime("44444444-4444-4444-8444-444444444444");
const missing_id = SceneEntityId.parseComptime("55555555-5555-4555-8555-555555555555");
const component_id = ComponentTypeId.parseComptime("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa");
const extra_component_id = ComponentTypeId.parseComptime("bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb");

fn testDocument() !SceneDocument {
    var scene = try SceneDocument.init(testing.allocator, test_scene_id, test_project_id, "Mutation test");
    errdefer scene.deinit();

    const storage = scene.arena.allocator();
    const fields = try storage.dupe(SceneField, &.{.{
        .number = 1,
        .value = .{ .string = "Original" },
    }});
    const components = try storage.dupe(SceneComponent, &.{.{
        .type_id = component_id,
        .fields = fields,
    }});
    scene.entities = try storage.dupe(SceneEntity, &.{
        .{ .id = root_id, .name = "Root", .components = components, .prefab = .{} },
        .{ .id = child_id, .parent_id = root_id, .name = "Child", .components = &.{}, .prefab = .{} },
        .{ .id = grandchild_id, .parent_id = child_id, .name = "Grandchild", .components = &.{}, .prefab = .{} },
    });
    return scene;
}

fn applyToClone(source: *const SceneDocument, mutation: Mutation) !SceneDocument {
    var candidate = try source.clone(testing.allocator);
    errdefer candidate.deinit();
    try applyToDocument(&candidate, mutation);
    return candidate;
}

fn applyToDocument(document: *SceneDocument, mutation: Mutation) !void {
    var scene: LoadedScene = .{
        .instance = undefined,
        .registry = undefined,
        .assets = undefined,
        .world = undefined,
        .document = document.*,
    };
    try mutation.apply(&scene);
    document.* = scene.document;
}

test "create and rename mutations preserve the source document" {
    var source = try testDocument();
    defer source.deinit();

    var name = [_]u8{ 'C', 'r', 'e', 'a', 't', 'e', 'd' };
    var candidate = try applyToClone(&source, .{ .create_entity = .{
        .id = created_id,
        .parent_id = root_id,
        .name = &name,
    } });
    defer candidate.deinit();

    name[0] = 'X';
    try testing.expectEqual(@as(usize, 3), source.entities.len);
    try testing.expectEqual(@as(usize, 4), candidate.entities.len);
    try testing.expectEqualStrings("Created", candidate.entities[3].name);
    try testing.expect(candidate.entities[3].parent_id.?.eql(root_id));

    const rename = Mutation{ .rename_entity = .{ .id = created_id, .name = "Renamed" } };
    try applyToDocument(&candidate, rename);
    try testing.expectEqualStrings("Renamed", candidate.entities[3].name);

    const duplicate = Mutation{ .create_entity = .{ .id = root_id, .parent_id = null, .name = "Duplicate" } };
    try testing.expectError(error.DuplicateEntityId, applyToDocument(&candidate, duplicate));
    const missing_parent = Mutation{ .create_entity = .{ .id = missing_id, .parent_id = missing_id, .name = "Missing parent" } };
    try testing.expectError(error.MissingParentEntity, applyToDocument(&candidate, missing_parent));
}

test "delete mutation implements child policies and preserves references" {
    var source = try testDocument();
    defer source.deinit();

    var reject_candidate = try source.clone(testing.allocator);
    defer reject_candidate.deinit();
    const reject = Mutation{ .delete_entity = .{ .id = root_id, .policy = .reject_if_children } };
    try testing.expectError(error.EntityHasChildren, applyToDocument(&reject_candidate, reject));
    try testing.expectEqual(@as(usize, 3), reject_candidate.entities.len);

    var reparented = try applyToClone(&source, .{ .delete_entity = .{
        .id = child_id,
        .policy = .reparent_children,
    } });
    defer reparented.deinit();
    try testing.expectEqual(@as(usize, 2), reparented.entities.len);
    try testing.expect(reparented.entities[1].id.eql(grandchild_id));
    try testing.expect(reparented.entities[1].parent_id.?.eql(root_id));

    var subtree = try applyToClone(&source, .{ .delete_entity = .{
        .id = child_id,
        .policy = .delete_subtree,
    } });
    defer subtree.deinit();
    try testing.expectEqual(@as(usize, 1), subtree.entities.len);
    try testing.expect(subtree.entities[0].id.eql(root_id));

    source.entities[0].components[0].fields[0].value = .{ .entity_ref = child_id };
    var referenced = try source.clone(testing.allocator);
    defer referenced.deinit();
    const referenced_delete = Mutation{ .delete_entity = .{ .id = child_id, .policy = .delete_subtree } };
    try testing.expectError(error.EntityStillReferenced, applyToDocument(&referenced, referenced_delete));
    try testing.expectEqual(@as(usize, 3), referenced.entities.len);
}

test "reparent and active camera mutations validate targets" {
    var source = try testDocument();
    defer source.deinit();

    var candidate = try applyToClone(&source, .{ .reparent_entity = .{
        .id = grandchild_id,
        .parent_id = root_id,
    } });
    defer candidate.deinit();
    try testing.expect(candidate.entities[2].parent_id.?.eql(root_id));

    const cycle = Mutation{ .reparent_entity = .{ .id = root_id, .parent_id = child_id } };
    try testing.expectError(error.EntityParentCycle, applyToDocument(&candidate, cycle));
    const missing_parent = Mutation{ .reparent_entity = .{ .id = child_id, .parent_id = missing_id } };
    try testing.expectError(error.MissingParentEntity, applyToDocument(&candidate, missing_parent));

    const set_camera = Mutation{ .set_active_camera = .{ .id = child_id } };
    try applyToDocument(&candidate, set_camera);
    try testing.expect(candidate.active_camera.?.eql(child_id));
    const clear_camera = Mutation{ .set_active_camera = .{ .id = null } };
    try applyToDocument(&candidate, clear_camera);
    try testing.expect(candidate.active_camera == null);
}

test "component mutations clone additions and reject invalid removals" {
    var source = try testDocument();
    defer source.deinit();

    var label = [_]u8{ 'E', 'x', 't', 'r', 'a' };
    var extra_fields = [_]SceneField{.{ .number = 1, .value = .{ .string = &label } }};
    const add = Mutation{ .add_component = .{
        .entity = root_id,
        .component = .{
            .type_id = extra_component_id,
            .fields = &extra_fields,
        },
    } };
    var candidate = try applyToClone(&source, add);
    defer candidate.deinit();
    label[0] = 'X';
    try testing.expectEqual(@as(usize, 2), candidate.entities[0].components.len);
    try testing.expectEqualStrings("Extra", candidate.entities[0].components[1].fields[0].value.string);

    try testing.expectError(error.DuplicateComponentTypeId, applyToDocument(&candidate, add));
    const remove = Mutation{ .remove_component = .{ .entity = root_id, .type_id = extra_component_id } };
    try applyToDocument(&candidate, remove);
    try testing.expectEqual(@as(usize, 1), candidate.entities[0].components.len);
    const missing = Mutation{ .remove_component = .{ .entity = root_id, .type_id = extra_component_id } };
    try testing.expectError(error.MissingComponent, applyToDocument(&candidate, missing));
}

test "field mutations replace, append, clone, and remove values" {
    var source = try testDocument();
    defer source.deinit();

    var replacement = [_]u8{ 'R', 'e', 'p', 'l', 'a', 'c', 'e', 'd' };
    var candidate = try applyToClone(&source, .{ .set_field = .{
        .entity_id = root_id,
        .type_id = component_id,
        .field_number = 1,
        .value = .{ .string = &replacement },
    } });
    defer candidate.deinit();
    replacement[0] = 'X';
    try testing.expectEqualStrings("Replaced", candidate.entities[0].components[0].fields[0].value.string);
    try testing.expectEqualStrings("Original", source.entities[0].components[0].fields[0].value.string);

    const append = Mutation{ .set_field = .{
        .entity_id = root_id,
        .type_id = component_id,
        .field_number = 2,
        .value = .{ .bool = true },
    } };
    try applyToDocument(&candidate, append);
    try testing.expectEqual(@as(usize, 2), candidate.entities[0].components[0].fields.len);

    const remove = Mutation{ .remove_field = .{
        .entity_id = root_id,
        .type_id = component_id,
        .field_number = 2,
    } };
    try applyToDocument(&candidate, remove);
    try testing.expectEqual(@as(usize, 1), candidate.entities[0].components[0].fields.len);
    try testing.expectError(error.MissingField, applyToDocument(&candidate, remove));

    const zero = Mutation{ .set_field = .{
        .entity_id = root_id,
        .type_id = component_id,
        .field_number = 0,
        .value = .{ .bool = true },
    } };
    try testing.expectError(error.ZeroFieldNumber, applyToDocument(&candidate, zero));
    const none = Mutation{ .set_field = .{
        .entity_id = root_id,
        .type_id = component_id,
        .field_number = 2,
        .value = .{ .none = {} },
    } };
    try testing.expectError(error.InvalidFieldValue, applyToDocument(&candidate, none));
}
