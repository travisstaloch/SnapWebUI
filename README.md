# Snap Wasm VDOM

Reactive immediate DOM rendering with Wasm in Zig. Build interactive web applications in Zig for the browser which compile to a small WebAssembly binary (currently around 2.7K release small build).

## Features

- **DOM rendering**: simple immediate mode rendering
- **Event System**: event handlers with callback support
- **Reactive State**: state management and automatic re-rendering

## Examples
See the included counter example in [`src/main.zig`](src/main.zig) for small application.

## Quick Start

```console
zig build --release=small
python -m http.server
```
open [localhost:8000](http://localhost:8000) in your browser

### Prerequisites
- Zig 0.14.0 or later
- A modern web browser

### Building

```bash
# Build WASM library
zig build

# Run tests
zig build test

# Build optimized for production
zig build --release=small
```

## API Reference

### Core Types

#### `Node`
Virtual DOM node representing elements, text, or empty nodes.

#### `Attribute`
HTML attribute with name-value pairs.

```zig
// Create attribute
const attr: Attribute = .a("class", "my-class");
```

#### `EventHandler`
Type-safe event handling with callbacks.

```zig
// Create event handler
const handler: EventHandler = .e("click", &myCallback, &context);
```

### DOM Helpers

#### `h()` - Element Node
```zig
pub fn h(
    tag: []const u8,
    attributes: []const Attribute,
    events: []const EventHandler,
    children: []const Node,
) Node
```

#### `t()` - Text Node
```zig
pub fn t(text: []const u8) Node
```

#### `tf()` - Formatted Text Node
```zig
pub fn tf(buf: []u8, comptime fmt: []const u8, args: anytype) Node
```

#### `hi()` - Immediate Element Node
```zig
pub fn hi(
    tag: []const u8,
    attributes: []const Attribute,
    events: []const EventHandler,
    children: []const Node,
) void
```

#### `ti()` - Immediate Text Node
```zig
pub fn ti(text: []const u8) void
```

### State Management

#### `State(T, Subscriber)`
Generic state container with automatic invalidation.

```zig
pub fn useState(
    state: anytype,
    subscriber: anytype,
) State(@TypeOf(state), @TypeOf(subscriber))
```

## Browser Integration
Include the generated WASM file and JavaScript bridge:

```html
<!DOCTYPE html>
<html>
<head>
    <title>My Zig App</title>
</head>
<body>
    <div id="app"></div>
    <script src="index.js" data-wasm-url="zig-out/bin/snap-demo.wasm" data-wasm-init-method="init"></script>
</body>
</html>
```

The JavaScript bridge (`index.js`) provides:
- DOM manipulation functions
- Event system
- Element caching with minimal memory management in Zig/Wasm.  Most of app memory lives in JS.

## Architecture
The library is designed around these core concepts:

1. **Virtual DOM**: Immutable tree structures representing UI state
1. **Immediate Mode**: Direct DOM manipulation for performance
1. **Event System**: Type-safe callbacks with context preservation
1. **State Management**: Reactive updates triggering re-renders

## Contributing

This project is in early development. Contributions welcome!

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure `zig build test` passes
5. Submit a pull request

## License

MIT License - see LICENSE file for details.

## Roadmap

- [ ] Component system architecture
- [ ] Server-side rendering support
- [ ] Performance optimizations
- [ ] More comprehensive examples

---

**Note**: This is version 0.x software. APIs may change.
