const std = @import("std");
const snap = @import("snap");

// TODO remove this.  only necessary because snap's superhtml dep does std.log.<level>() somewhere
// TODO send pr to superhtml to disable logging by default so that this isn't needed
pub fn logFn(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    const level_txt = comptime message_level.asText();
    const prefix2 = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";
    snap.log(level_txt ++ prefix2 ++ format ++ "\n", args);
}

pub const std_options: std.Options = .{
    .logFn = logFn,
    .log_level = .warn,
};

/// FIXME not working.  because of panics?
pub fn returnErrorHook() void {
    const st = @errorReturnTrace().?;
    if (st.index == 0) {
        snap.js.captureBacktrace();
    }
}

const Todo = struct {
    id: u32,
    text: []const u8,
    completed: bool = false,
};

const App = struct {
    root_element: snap.NodeId,
    count: snap.State(i32, *App),
    todos: std.ArrayList(Todo),
    /// needed for unique ids, todos.items.len won't work when deletes happen.
    next_id: u32 = 1,
    input_text: [256]u8 = std.mem.zeroes([256]u8),
    input_len: usize = 0,
    arena: std.heap.ArenaAllocator,
    app_template: snap.ParsedTemplate,
    todo_item_template: snap.ParsedTemplate,

    pub fn render(self: *App) !void {
        _ = self.arena.reset(.retain_capacity);
        self.createViewTemplate();
    }

    pub fn updateView(self: *App, new_count: i32) !void {
        _ = new_count;
        try self.render();
    }

    fn createViewTemplate(self: *App) void {
        snap.renderTemplate(self.root_element, snap.renderable(
            self.app_template,
            .{
                .onDecClick = snap.eh(&onDecClick, self),
                .onIncClick = snap.eh(&onIncClick, self),
                .onNewTodoInput = snap.eh(&onNewTodoInput, self),
                .onAddTodoClick = snap.eh(&onAddTodoClick, self),
                .count = self.count.inner,
                .input = self.input_text[0..self.input_len],
                .todos = snap.renderableAction(&renderTodos, self, .{}),
            },
        ));
    }

    pub fn renderTodos(ctx: *anyopaque) !void {
        const data: *App = @ptrCast(@alignCast(ctx));
        for (data.todos.items) |todo| {
            snap.renderTemplateInner(snap.renderable(data.todo_item_template, .{
                .onTodoChange = snap.ehd(&onTodoChange, data, todo.id),
                .onTodoDeleteClick = snap.ehd(&onTodoDeleteClick, data, todo.id),
                .class = if (todo.completed) "todo-item completed" else "todo-item",
                .id = todo.id,
                .checked = if (todo.completed) "checked" else "data-unchecked",
                .text = todo.text,
            }));
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

        try app.todos.append(.{
            .id = app.next_id,
            .text = try app.arena.child_allocator.dupe(u8, app.input_text[0..app.input_len]),
            .completed = false,
        });
        app.next_id += 1;

        // Clear the input field
        app.input_len = 0;
        app.input_text[0] = 0;

        try app.render();
    }

    fn onTodoChange(ctx: *anyopaque, data: usize) !void {
        const app: *App = @ptrCast(@alignCast(ctx));

        for (app.todos.items) |*todo| {
            if (todo.id == data) {
                todo.completed = !todo.completed;
                break;
            }
        }
        try app.render();
    }

    fn onTodoDeleteClick(ctx: *anyopaque, data: usize) !void {
        const app: *App = @ptrCast(@alignCast(ctx));
        const todo_id: u32 = @intCast(data);

        for (app.todos.items, 0..) |todo, i| {
            if (todo.id == todo_id) {
                _ = app.todos.orderedRemove(i);
                break;
            }
        }
        try app.render();
    }
};

fn initInner() !void {
    const alloc = std.heap.wasm_allocator;
    const app = try alloc.create(App);
    const root_element = snap.querySelector("#app");
    // buffer must be big enough to read template contents one at a time
    var template_buf: [4096]u8 = undefined;
    const asrc = try alloc.dupeZ(u8, snap.querySelectorInnerHTML("#app-template", &template_buf));
    const bsrc = try alloc.dupeZ(u8, snap.querySelectorInnerHTML("#todo-item-template", &template_buf));
    app.* = .{
        .root_element = root_element,
        .count = snap.useState(@as(i32, 0), app),
        .todos = .init(alloc),
        .arena = .init(alloc),
        .app_template = try snap.parseTemplate(alloc, asrc),
        .todo_item_template = try snap.parseTemplate(alloc, bsrc),
    };
    try app.render();
}

export fn init() void {
    snap.unwrapErr(initInner());
}

// /// render app with Builder api.  working but deemed too verbose.  only left as demo.
// fn createViewBuilder(self: *App) void {
//     var b = snap.Builder{};
//     _ = b.elem("div", &.{.a("class", "app")}, &.{});
//     _ = b.elem("h1", &.{}, &.{}).text("Counter")
//         .end();
//     _ = b.elem("div", &.{}, &.{})
//         .elem("button", &.{.a("class", "m05")}, &.{.e("click", &decrementCallback, self)})
//         .text("-")
//         .end()
//         .elem("button", &.{.a("class", "m05")}, &.{.e("click", &incrementCallback, self)})
//         .text("+")
//         .end();
//     _ = b.elem("span", &.{}, &.{})
//         .textf("count: {}", .{self.count})
//         .end()
//         .end()
//         .end();

//     _ = b.elem("h1", &.{}, &.{})
//         .text("Todos")
//         .end();
//     _ = b.elem("div", &.{.a("class", "add-todo-section")}, &.{})
//         .elem("input", &.{
//             .a("type", "text"),
//             .a("placeholder", "Add a new todo..."),
//             .a("id", "new-todo"),
//             .a("value", self.input_text[0..self.input_len]),
//         }, &.{.e("input", &updateInputCallback, self)})
//         .end()
//         .elem("button", &.{}, &.{.e("click", &addTodoCallback, self)})
//         .text("Add Todo")
//         .end()
//         .end();
//     _ = b.elem("ul", &.{.a("class", "todo-list")}, &.{})
//         .elem("ul", &.{.a("class", "todo-list")}, &.{})
//         .childrenWith(self, renderTodoList)
//         .end()
//         .end()
//         .end();
// }

// fn renderTodoList(self: *App, b: *snap.Builder) void {
//     for (self.todos.items) |todo| {
//         const todo_class = if (todo.completed) "todo-item completed" else "todo-item";
//         _ = b.elem("li", &.{.a("class", todo_class)}, &.{})
//             .elem("input", &.{
//                 .a("type", "checkbox"),
//                 .a(if (todo.completed) "checked" else "data-unchecked", ""),
//             }, &.{.ed("change", &toggleTodoCallback, self, todo.id)})
//             .end()
//             .elem("span", &.{}, &.{}).text(todo.text)
//             .end()
//             .elem("button", &.{}, &.{.ed("click", &deleteTodoCallback, self, todo.id)})
//             .text("Delete")
//             .end()
//             .end();
//     }
// }
