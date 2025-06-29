const std = @import("std");
const snap = @import("snap");
const NodeId = snap.NodeId;
const h = snap.h;
const t = snap.t;
const tf = snap.tf;
const hi = snap.hi;
const hiBegin = snap.hiBegin;
const hiEnd = snap.hiEnd;
const ti = snap.ti;

const TodoItem = struct {
    id: u32,
    text: []const u8,
    completed: bool = false,
};

const App = struct {
    root_element: NodeId,
    count: i32 = 0,
    todos: std.ArrayList(TodoItem),
    next_id: u32 = 1,
    input_text: [256]u8 = std.mem.zeroes([256]u8),
    input_len: usize = 0,
    arena: std.heap.ArenaAllocator,

    pub fn render(self: *App) !void {
        _ = self.arena.reset(.retain_capacity);
        self.createViewTemplate();
    }

    fn createViewTemplate(self: *App) void {
        snap.renderTemplate(
            self.arena.allocator(),
            self.root_element,
            @embedFile("snap-demo-app.html"),
            .{
                snap.eh("", &decrementCallback, self),
                snap.eh("", &incrementCallback, self),
                self.count,
                self.input_text[0..self.input_len],
                snap.eh("", &updateInputCallback, self),
                snap.eh("", &addTodoCallback, self),
                std.fmt.Formatter(renderTodos){ .data = self },
            },
        );
    }

    pub fn renderTodos(data: *App, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        for (data.todos.items) |todo| {
            try writer.print(@embedFile("snap-demo-todo-frag.html"), .{
                if (todo.completed) "todo-item completed" else "todo-item",
                if (todo.completed) "checked" else "data-unchecked",
                snap.ehd("", &toggleTodoCallback, data, todo.id),
                todo.text,
                snap.ehd("", &deleteTodoCallback, data, todo.id),
            });
        }
    }

    /// render app with Builder api
    fn createViewBuilder(self: *App) void {
        var b = snap.Builder{};
        _ = b.elem("div", &.{.a("class", "app")}, &.{});
        _ = b.elem("h1", &.{}, &.{}).text("Counter")
            .end();
        _ = b.elem("div", &.{}, &.{})
            .elem("button", &.{.a("class", "m05")}, &.{.e("click", &decrementCallback, self)})
            .text("-")
            .end()
            .elem("button", &.{.a("class", "m05")}, &.{.e("click", &incrementCallback, self)})
            .text("+")
            .end();
        _ = b.elem("span", &.{}, &.{})
            .textf("count: {}", .{self.count})
            .end()
            .end()
            .end();

        _ = b.elem("h1", &.{}, &.{})
            .text("Todos")
            .end();
        _ = b.elem("div", &.{.a("class", "add-todo-section")}, &.{})
            .elem("input", &.{
                .a("type", "text"),
                .a("placeholder", "Add a new todo..."),
                .a("id", "new-todo"),
                .a("value", self.input_text[0..self.input_len]),
            }, &.{.e("input", &updateInputCallback, self)})
            .end()
            .elem("button", &.{}, &.{.e("click", &addTodoCallback, self)})
            .text("Add Todo")
            .end()
            .end();
        _ = b.elem("ul", &.{.a("class", "todo-list")}, &.{})
            .elem("ul", &.{.a("class", "todo-list")}, &.{})
            .childrenWith(self, renderTodoList)
            .end()
            .end()
            .end();
    }

    fn renderTodoList(self: *App, b: *snap.Builder) void {
        for (self.todos.items) |todo| {
            const todo_class = if (todo.completed) "todo-item completed" else "todo-item";
            _ = b.elem("li", &.{.a("class", todo_class)}, &.{})
                .elem("input", &.{
                    .a("type", "checkbox"),
                    .a(if (todo.completed) "checked" else "data-unchecked", ""),
                }, &.{.ed("change", &toggleTodoCallback, self, todo.id)})
                .end()
                .elem("span", &.{}, &.{}).text(todo.text)
                .end()
                .elem("button", &.{}, &.{.ed("click", &deleteTodoCallback, self, todo.id)})
                .text("Delete")
                .end()
                .end();
        }
    }
};

fn updateInputCallback(ctx: *anyopaque, _: usize) !void {
    const app: *App = @ptrCast(@alignCast(ctx));
    const value = snap.querySelectorValue("input[id=new-todo]", "value", &app.input_text);
    app.input_len = value.len;
    // No need to re-render on every input change
}

fn addTodoCallback(ctx: *anyopaque, _: usize) !void {
    const app: *App = @ptrCast(@alignCast(ctx));

    if (app.input_len == 0) return; // Don't add empty todos

    const new_text = try app.arena.child_allocator.dupe(u8, app.input_text[0..app.input_len]);

    try app.todos.append(.{ .id = app.next_id, .text = new_text, .completed = false });
    app.next_id += 1;

    // Clear the input field
    app.input_len = 0;
    app.input_text[0] = 0;

    try app.render();
}

fn toggleTodoCallback(ctx: *anyopaque, data: usize) !void {
    const app: *App = @ptrCast(@alignCast(ctx));

    for (app.todos.items) |*todo| {
        if (todo.id == data) {
            todo.completed = !todo.completed;
            break;
        }
    }
    try app.render();
}

fn deleteTodoCallback(ctx: *anyopaque, data: usize) !void {
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

fn incrementCallback(ctx: *anyopaque, _: usize) !void {
    const app: *App = @ptrCast(@alignCast(ctx));
    app.count += 1;
    try app.render();
}

fn decrementCallback(ctx: *anyopaque, _: usize) !void {
    const app: *App = @ptrCast(@alignCast(ctx));
    app.count -= 1;
    try app.render();
}

fn initInner() !void {
    const alloc = std.heap.wasm_allocator;
    const app = try alloc.create(App);
    const root_element = snap.querySelector("#app");
    app.* = .{
        .root_element = root_element,
        .todos = std.ArrayList(TodoItem).init(alloc),
        .arena = .init(alloc),
    };
    try app.render();
}

export fn init() void {
    snap.unwrapErr(initInner());
}
