# SnapUI

Write your web app in Zig in a reactive style. Compiles to WebAssembly binaries.

## Features

-   **Immediate mode DOM rendering**: Efficiently update the UI based on your application state.
-   **Event handling with callbacks**: Connect user interactions to Zig logic.
-   **Reactive state management**:  Automatic re-rendering when your application state changes.
-   **HTML Templating**: Parse templates in JavaScript, render from WebAssembly. Any HTML element can be a template and templates can be nested.
-   **Dynamic HTML Attributes**: Control attributes like class names dynamically.
-   **Partial DOM Updates**: Update only the changed parts of your UI.
-   **Animation Support**: `requestAnimationFrame` integration.

## Examples
See [`public/index.html`](public/index.html) and [`src/snap-demo.zig`](src/snap-demo.zig) for a demo app with a counter, a todo app and more.

## Quick Start

```console
zig build --release=small
python -m http.server
```
Open [localhost:8000](http://localhost:8000) in your browser.

### Prerequisites
- Zig 0.14.0 or later
- A modern web browser

## Contributing

This project is in early development. Contributions welcome!

1. Fork the repository
1. Create a feature branch
1. Add tests for new functionality
1. Ensure `zig build test` passes
1. Submit a pull request

## License

MIT License - see LICENSE file for details.

## Roadmap / Ideas

- [ ] Component system architecture
- [ ] Server-side rendering support
- [ ] WebAssembly module bundling / loading

---

**Note**: This is version 0.x software. APIs may change.