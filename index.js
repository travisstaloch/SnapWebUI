
function stringFromMemory(ptr, len) {
  if (!cachedTextDecoder) {
    cachedTextDecoder = new TextDecoder("utf-8");
  }
  const memoryToUse = memory || (instance && instance.exports.memory);
  if (!memoryToUse) {
    console.error("Memory not available for stringFromMemory");
    return "";
  }
  return cachedTextDecoder.decode(new Uint8Array(memoryToUse.buffer, ptr, len));
}

let memory;
let instance;
let elementCache = [];
let elementEventHandlers = new Map(); // Map to store event handlers
let cachedTextDecoder = null;

// immediate renderer state
let nodeStack = []; // Stack for building DOM tree
let currentParent = null;

function stringFromMemory(ptr, len) {
  if (!cachedTextDecoder) {
    cachedTextDecoder = new TextDecoder("utf-8");
  }
  if (!memory) {
    console.error("Memory not available in stringFromMemory, ptr:", ptr, "len:", len);
    return "";
  }
  const result = cachedTextDecoder.decode(new Uint8Array(memory.buffer, ptr, len));
  return result;
}
const wasm_url = document.currentScript.getAttribute("data-wasm-url")
const wasm_init_method = document.currentScript.getAttribute("data-wasm-init-method")
fetch(wasm_url)
  .then((response) => response.arrayBuffer())
  .then((bytes) =>
    WebAssembly.instantiate(bytes, {
      env: {
        js_log: function (start, len) {
          console.log(stringFromMemory(start, len));
        },
        js_query_selector: function (start, len) {
          const el = document.querySelector(stringFromMemory(start, len));
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
            // Call the zig function with the stored callback and context pointers
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
        
        // immediate-mode functions
        js_begin_render: function(parentId) {
          const parent = elementCache[parentId];
          // Clear existing content
          parent.innerHTML = '';
          currentParent = parent;
          nodeStack = [parent];
        },
        js_create_element_immediate: function(tagPtr, tagLen) {
          const tag = stringFromMemory(tagPtr, tagLen);
          if (!tag || tag.trim() === '') {
            console.error("Empty tag name received, ptr:", tagPtr, "len:", tagLen);
            // Push a placeholder div instead of crashing
            const element = document.createElement("div");
            nodeStack.push(element);
            return;
          }
          const element = document.createElement(tag);
          nodeStack.push(element);
        },
        js_create_text_immediate: function(textPtr, textLen) {
          const text = stringFromMemory(textPtr, textLen);
          const textNode = document.createTextNode(text);
          nodeStack.push(textNode);
        },
        js_set_attribute_immediate: function(namePtr, nameLen, valuePtr, valueLen) {
          const name = stringFromMemory(namePtr, nameLen);
          const value = stringFromMemory(valuePtr, valueLen);
          const current = nodeStack[nodeStack.length - 1];
          if (current.nodeType === 1) { // Element node
            current.setAttribute(name, value);
          }
        },
        js_add_event_immediate: function(eventPtr, eventLen, callbackPtr, ctxPtr) {
          const eventName = stringFromMemory(eventPtr, eventLen);
          const current = nodeStack[nodeStack.length - 1];
          if (current.nodeType === 1) { // Element node
            current.addEventListener(eventName, () => {
              instance.exports.call_zig_callback(callbackPtr, ctxPtr);
            });
          }
        },
        js_append_child_immediate: function() {
          if (nodeStack.length >= 2) {
            const child = nodeStack.pop();
            const parent = nodeStack[nodeStack.length - 1];
            parent.appendChild(child);
          }
        },
        js_end_render: function() {
          // If there's exactly one root element left on the stack, append it to the parent
          if (nodeStack.length === 2) { // parent + root element
            const rootElement = nodeStack[1];
            const parent = nodeStack[0];
            parent.appendChild(rootElement);
          }
          nodeStack = [];
          currentParent = null;
        },
      },
    }),
  )
  .then((results) => {
    instance = results.instance;
    memory = results.instance.exports.memory;
    results.instance.exports[wasm_init_method]();
  });
  