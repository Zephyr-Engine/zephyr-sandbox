# Zephyr Editor
The actual editor of Zephyr. 

## Usage
```bash
mkdir zephyr

cd zephyr
git clone git@github.com:Zephyr-Engine/zephyr-runtime.git
git clone git@github.com:Zephyr-Engine/zephyr-editor.git

mkdir game

cd zephyr-editor
zig build run -- create ../game
zig build run -- open ../game
```

## Development

The editor currently targets Zig 0.16.0.

```bash
zig build check
zig build test
```

Run the zGUI test suite from the sibling checkout with `zig build test`.

## UI architecture

`src/editor/context.zig` owns stable, editor-wide services such as the play
session and action registry. It lives outside the game ECS world. Editor
behavior is registered once through `src/editor/actions.zig`; buttons and
future menus bind action IDs rather than directly owning session callbacks.
`src/ui/action_button.zig` also keeps enabled state and visuals synchronized.

Each editor panel is a stateful type with this lifecycle:

```zig
fn mount(self: *Panel, state: *zgui.Ui, parent: zgui.NodeId, services: panel.Services) !void
fn update(self: *Panel, state: *zgui.Ui, frame: panel.Frame) !void
fn unmount(self: *Panel, state: *zgui.Ui) void
fn root(self: *const Panel) zgui.NodeId
```

`panel.Instance` gives the workspace stable, type-erased ownership of those
types. `Workspace` registers, opens, closes, updates, and destroys panels and
their dock windows. A panel must create its subtree transactionally in `mount`
and destroy that subtree in `unmount`; an optional parameterless `deinit`
releases non-UI resources. Adding a panel does not require adding its nodes or
mutable state to `EditorUi`.
