function stringFromMemory(ptr, len) {
  if (!cachedTextDecoder) {
    cachedTextDecoder = new TextDecoder("utf-8");
  }
  return cachedTextDecoder.decode(new Uint8Array(memory.buffer, ptr, len));
}

let memory;
let instance;
let elementCache = [];
let elementEventHandlers = new Map(); // Map to store event handlers
let cachedTextDecoder = null;

// fetch('target/wasm32-unknown-unknown/release/simple-virtual-dom.wasm')
fetch("zig-out/bin/lib.wasm")
  .then((response) => response.arrayBuffer())
  .then((bytes) =>
    WebAssembly.instantiate(bytes, {
      env: {
        js_log: function (start, len) {
          console.log(stringFromMemory(start, len));
        },
        js_query_selector: function (start, len) {
          const query = stringFromMemory(start, len);
          const el = document.querySelector(query);
          const index = elementCache.length;
          elementCache.push(el);
          return index;
        },
        js_create_element: function (start, len) {
          const text = stringFromMemory(start, len);
          const el = document.createElement(text);
          const index = elementCache.length;
          elementCache.push(el);
          return index;
        },
        js_create_text_element: function (start, len) {
          const type = stringFromMemory(start, len);
          const el = document.createTextNode(type);
          const index = elementCache.length;
          elementCache.push(el);
          return index;
        },
        js_append_element: function (parent, child) {
          const parentElement = elementCache[parent];
          const childElement = elementCache[child];
          parentElement.append(childElement);
        },
        js_remove_child: function (parent, childIndex) {
          const parentElement = elementCache[parent];
          parentElement.removeChild(parentElement.childNodes[childIndex]);
        },
        js_get_child: function (parent, childIndex) {
          const parentElement = elementCache[parent];
          const el = parentElement.childNodes[childIndex];
          // Check if the element is already in the cache
          for (let i = 0; i < elementCache.length; i++) {
            if (elementCache[i] === el) {
              return i; // Return existing NodeId
            }
          }
          // If not in cache, add it and return new NodeId
          const index = elementCache.length;
          elementCache.push(el);
          return index;
        },
        js_replace_child: function (parent, childIndex, child) {
          const parentElement = elementCache[parent];
          const childElement = elementCache[child];
          parentElement.replaceChild(
            childElement,
            parentElement.childNodes[childIndex],
          );
        },
        js_add_event_listener: function (
          element_id,
          event_name_ptr,
          event_name_len,
          callback_ptr,
          ctx_ptr,
        ) {
          const element_ref = elementCache[element_id];
          const event_name = stringFromMemory(event_name_ptr, event_name_len);

          // Store the callback and context for later use
          if (!elementEventHandlers.has(element_id)) {
            elementEventHandlers.set(element_id, new Map());
          }
          elementEventHandlers
            .get(element_id)
            .set(event_name, { callback_ptr, ctx_ptr });

          element_ref.addEventListener(event_name, (event) => {
            // Call the Zig function with the stored callback and context pointers
            instance.exports.call_zig_callback(callback_ptr, ctx_ptr);
          });
        },
        js_set_attribute: function (
          element_id,
          name_ptr,
          name_len,
          value_ptr,
          value_len,
        ) {
          const element_ref = elementCache[element_id];
          const name = stringFromMemory(name_ptr, name_len);
          const value = stringFromMemory(value_ptr, value_len);
          element_ref.setAttribute(name, value);
        },
      },
    }),
  )
  .then((results) => {
    instance = results.instance;
    memory = results.instance.exports.memory;
    results.instance.exports.init();
  });