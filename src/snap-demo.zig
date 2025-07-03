const std = @import("std");
const snap = @import("snap");

const Todo = struct {
    id: u32,
    text: []const u8,
    completed: bool = false,
};

const App = struct {
    arena: std.heap.ArenaAllocator,
    root_element: snap.NodeId,
    count: snap.State(i32, *App),
    frame_count: snap.State(u32, *App),
    animation_id: u32 = 0,
    todos: snap.State(std.ArrayList(Todo), *App),
    /// needed for unique ids, todos.items.len won't work when deletes happen.
    todo_id: u32 = 1,
    input_text: [256]u8 = std.mem.zeroes([256]u8),
    input_len: usize = 0,
    animation_running: bool,
    show_stress_test: bool,
    stress_rows: u8 = 4,
    stress_cols: u8 = 4,
    app_template: snap.HtmlTemplate,
    todo_item_template: snap.HtmlTemplate,
    stress_table_template: snap.HtmlTemplate,
    stress_row_template: snap.HtmlTemplate,
    stress_cell_template: snap.HtmlTemplate,
    dynamic_class_template: snap.HtmlTemplate,

    pub fn render(self: *App) !void {
        _ = self.arena.reset(.retain_capacity);
        try self.createView();
    }

    pub fn onStateChange(self: *App) !void {
        try self.render();
    }

    fn createView(self: *App) !void {
        try snap.renderEncodedTemplate(
            self.root_element,
            self.app_template,
            .{
                .onDecClick = snap.eh(&onDecClick, self),
                .onIncClick = snap.eh(&onIncClick, self),
                .onNewTodoInput = snap.eh(&onNewTodoInput, self),
                .onAddTodoClick = snap.eh(&onAddTodoClick, self),
                .count = self.count.inner,
                .frame_count = self.frame_count.inner,
                .input = self.input_text[0..self.input_len],
                .todos = snap.renderableAction(&renderTodos, self, .{}),
                .onToggleStressTest = snap.eh(&onToggleStressTest, self),
                .stress_test_label = @as([]const u8, if (self.show_stress_test) "Hide Stress Test" else "Show Stress Test"),
                .stress_table = snap.renderableAction(&renderStressTable, self, .{}),
                .onToggleAnimation = snap.eh(&onToggleAnimation, self),
                .animation_label = @as([]const u8, if (self.animation_running) "Stop Animation" else "Start Animation"),
            },
        );

        // Render the dynamic class test template
        try snap.renderEncodedTemplate(
            snap.querySelector("#multi-dynamic-attr-container"),
            self.dynamic_class_template,
            .{
                .class_part_1 = @as([]const u8, "foo"),
                .class_part_2 = @as([]const u8, "bar"),
            },
        );
    }

    pub fn renderTodos(ctx: *anyopaque) !void {
        const app: *App = @ptrCast(@alignCast(ctx));
        for (app.todos.inner.items) |todo| {
            try snap.renderEncodedTemplateInner(app.todo_item_template, .{
                .onTodoChange = snap.ehd(&onTodoChange, app, todo.id),
                .onTodoDeleteClick = snap.ehd(&onTodoDeleteClick, app, todo.id),
                .class = if (todo.completed) "todo-item completed" else "todo-item",
                .id = todo.id,
                .checked = if (todo.completed) "checked" else "data-unchecked",
                .text = todo.text,
            });
        }
    }

    pub fn renderStressTable(ctx: *anyopaque) !void {
        const app: *App = @ptrCast(@alignCast(ctx));
        if (!app.show_stress_test) return;

        try snap.renderEncodedTemplateInner(app.stress_table_template, .{
            .stress_rows = snap.renderableAction(&renderStressRows, app, .{}),
        });
    }

    const RowCtx = struct { app: *App, row: u32 };
    fn renderStressRows(ctx: *anyopaque) !void {
        const app: *App = @ptrCast(@alignCast(ctx));
        var row: u32 = 0;
        while (row < app.stress_rows) : (row += 1) {
            var rowctx = RowCtx{ .app = app, .row = row };
            try snap.renderEncodedTemplateInner(app.stress_row_template, .{
                .stress_cells = snap.renderableAction(&renderStressCells, &rowctx, .{ .row = row }),
            });
        }
    }

    fn renderStressCells(ctx: *anyopaque) !void {
        const rc: *RowCtx = @ptrCast(@alignCast(ctx));
        var col: u32 = 0;
        while (col < rc.app.stress_cols) : (col += 1) {
            const seed = rc.app.frame_count.inner +% (rc.row * 1000) +% (col * 100);
            const value = seed % 1000;

            var buf: [16]u8 = undefined;
            const text = try std.fmt.bufPrint(&buf, "{d}", .{value});

            try snap.renderEncodedTemplateInner(rc.app.stress_cell_template, .{ .value = text });
        }
    }

    fn onIncClick(ctx: *anyopaque, _: usize) !void {
        const app: *App = @ptrCast(@alignCast(ctx));
        try app.count.set(app.count.inner + 1);
    }

    fn onDecClick(ctx: *anyopaque, _: usize) !void {
        const app: *App = @ptrCast(@alignCast(ctx));
        try app.count.set(app.count.inner - 1);
    }

    fn onNewTodoInput(ctx: *anyopaque, _: usize) !void {
        const app: *App = @ptrCast(@alignCast(ctx));
        const value = snap.querySelectorValue("input[id=new-todo]", "value", &app.input_text);
        app.input_len = value.len;
        // No need to re-render on every input change
    }

    fn onAddTodoClick(ctx: *anyopaque, _: usize) !void {
        const app: *App = @ptrCast(@alignCast(ctx));
        if (app.input_len == 0) return; // Don't add empty todos

        try app.todos.getForUpdate().append(.{
            .id = app.todo_id,
            .text = try app.arena.child_allocator.dupe(u8, app.input_text[0..app.input_len]),
            .completed = false,
        });
        app.todo_id += 1;

        // Clear the input field
        app.input_len = 0;
        app.input_text[0] = 0;

        try app.todos.didUpdate();
    }

    fn onTodoChange(ctx: *anyopaque, data: usize) !void {
        const app: *App = @ptrCast(@alignCast(ctx));

        for (app.todos.getForUpdate().items) |*todo| {
            if (todo.id == data) {
                todo.completed = !todo.completed;
                break;
            }
        }
        try app.todos.didUpdate();
    }

    fn onTodoDeleteClick(ctx: *anyopaque, data: usize) !void {
        const app: *App = @ptrCast(@alignCast(ctx));
        const todo_id: u32 = @intCast(data);

        for (app.todos.getForUpdate().items, 0..) |todo, i| {
            if (todo.id == todo_id) {
                _ = app.todos.getForUpdate().orderedRemove(i);
                try app.todos.didUpdate();
                break;
            }
        }
    }

    fn onToggleAnimation(ctx: *anyopaque, _: usize) !void {
        const app: *App = @ptrCast(@alignCast(ctx));
        app.animation_running = !app.animation_running;
        if (app.animation_running) snap.startAnimationLoop(snap.eh(&App.onAnimationFrame, app));
        try app.render();
    }

    fn onAnimationFrame(ctx: *anyopaque, _: usize) !void {
        const app: *App = @ptrCast(@alignCast(ctx));
        if (app.show_stress_test) {
            const frame = app.frame_count.inner;
            // Vary between 1-20 rows and 1-15 cols based on frame count
            app.stress_rows = @truncate(1 + (frame % 20));
            app.stress_cols = @truncate(1 + ((frame / 3) % 15));

            // Only re-render the stress test part
            const stress_container = snap.querySelector(".stress-test-container");
            snap.js.beginRender(stress_container);
            try App.renderStressTable(app);
            snap.js.endRender();
        }

        // Update frame count without triggering full re-render
        app.frame_count.inner += 1;
        // Only update the frame counter display, not the whole DOM
        var buf: [32]u8 = undefined;
        const frame_text = std.fmt.bufPrint(&buf, "{d}", .{app.frame_count.inner}) catch "0";
        const frame_span = snap.querySelector("#frame-counter");
        snap.setTextContent(frame_span, frame_text);
        if (app.animation_running) {
            snap.startAnimationLoop(snap.eh(&App.onAnimationFrame, app));
        }
    }

    fn onToggleStressTest(ctx: *anyopaque, _: usize) !void {
        const app: *App = @ptrCast(@alignCast(ctx));
        app.show_stress_test = !app.show_stress_test;
        try app.render();
    }
};

fn initInner() !void {
    const alloc = std.heap.wasm_allocator;
    const app = try alloc.create(App);
    const root_element = snap.querySelector("#app");
    app.* = .{
        .root_element = root_element,
        .count = snap.useState(@as(i32, 0), app),
        .todos = snap.useState(std.ArrayList(Todo).init(alloc), app),
        .frame_count = snap.useState(@as(u32, 0), app),
        .arena = .init(alloc),
        .app_template = try snap.encodeTemplateFromDOM(alloc, "#app-template"),
        .todo_item_template = try snap.encodeTemplateFromDOM(alloc, "#todo-item-template"),
        .show_stress_test = false,
        .animation_running = false,
        .stress_table_template = try snap.encodeTemplateFromDOM(alloc, "#stress-table-template"),
        .stress_row_template = try snap.encodeTemplateFromDOM(alloc, "#stress-row-template"),
        .stress_cell_template = try snap.encodeTemplateFromDOM(alloc, "#stress-cell-template"),
        .dynamic_class_template = try snap.encodeTemplateFromDOM(alloc, "#multi-dynamic-attr-template"),
    };

    try app.render();
}

export fn init() void {
    snap.unwrapErr(initInner());
}

// log error traces
// depends on modded std lib for now as discussed here https://github.com/ziglang/zig/issues/24285
pub fn returnErrorHook() void {
    const st = @errorReturnTrace().?;
    if (st.index == 0) {
        snap.js.captureBacktrace();
    }
}
