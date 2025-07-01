# Snap Wasm VDOM

Reactive immediate DOM rendering with Wasm in Zig.  Compiles to a small WebAssembly binary.

## Features

- **DOM rendering**: simple immediate mode rendering
- **Event System**: event handlers with callback support
- **Reactive State**: state management with automatic re-rendering
- **Templating**: with Zig std library formatting and `snap.renderTemplate()`

## Examples
See [`src/snap-demo.zig`](src/snap-demo.zig) for a demo app with a counter and todos.

## Quick Start

```console
zig build --release=small
python -m http.server
```
open [localhost:8000](http://localhost:8000) in your browser

### Prerequisites
- Zig 0.14.0 or later
- A modern web browser

## Architecture
The library is designed around:

1. **Virtual DOM**: Immutable tree structures representing UI state
1. **Immediate Mode**: Direct DOM manipulation for simplicity
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
- [ ] More comprehensive examples

---

**Note**: This is version 0.x software. APIs may change.
