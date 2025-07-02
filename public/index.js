
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
let cachedTextDecoder = null;
let lastError = null;

// immediate renderer state
let nodeStack = []; // Stack for building DOM tree
let currentParent = null;

const wasm_url = document.currentScript.getAttribute("data-wasm-url");
const wasm_init_method = document.currentScript.getAttribute("data-wasm-init-method");

async function init() {
  fetch(wasm_url)
    .then((response) => response.arrayBuffer())
    .then((bytes) =>
      WebAssembly.instantiate(bytes, {
        env: {
          consoleLog: function (start, len) {
            console.log(stringFromMemory(start, len));
          },
          captureBacktrace: function() {
            lastError = new Error().stack;
          },
          printCapturedBacktrace: function() {
            console.log(lastError);
          },
          querySelector: function (start, len) {
            const el = document.querySelector(stringFromMemory(start, len));
            const index = elementCache.length;
            elementCache.push(el);
            return index;
          },
          createElement: function (start, len) {
            const text = stringFromMemory(start, len);
            const el = document.createElement(text);
            const index = elementCache.length;
            elementCache.push(el);
            return index;
          },
          createTextElement: function (start, len) {
            const type = stringFromMemory(start, len);
            const el = document.createTextNode(type);
            const index = elementCache.length;
            elementCache.push(el);
            return index;
          },
          appendElement: function (parent, child) {
            const parentElement = elementCache[parent];
            const childElement = elementCache[child];
            parentElement.append(childElement);
          },
          removeChild: function (parent, childIndex) {
            const parentElement = elementCache[parent];
            parentElement.removeChild(parentElement.childNodes[childIndex]);
          },
          getChild: function (parent, childIndex) {
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
          replaceChild: function (parent, childIndex, child) {
            const parentElement = elementCache[parent];
            const childElement = elementCache[child];
            parentElement.replaceChild(
              childElement,
              parentElement.childNodes[childIndex],
            );
          },
          // let elementEventHandlers = new Map(); // Map to store event handlers

          // addEventListener: function (
          //   element_id,
          //   event_name_ptr,
          //   event_name_len,
          //   callback_ptr,
          //   ctx_ptr,
          // ) {
          //   const element_ref = elementCache[element_id];
          //   const event_name = stringFromMemory(event_name_ptr, event_name_len);

          //   // Store the callback and context for later use
          //   if (!elementEventHandlers.has(element_id)) {
          //     elementEventHandlers.set(element_id, new Map());
          //   }
          //   elementEventHandlers
          //     .get(element_id)
          //     .set(event_name, { callback_ptr, ctx_ptr });

          //   element_ref.addEventListener(event_name, (event) => {
          //     // Call the zig function with the stored callback and context pointers
          //     instance.exports.callZigCallback(callback_ptr, ctx_ptr, 0);
          //   });
          // },
          setAttribute: function (
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
          querySelectorValue: function(selectorPtr, selectorLen, propPtr, propLen, bufPtr, bufLen) {
            const element = document.querySelector(stringFromMemory(selectorPtr, selectorLen));
            if (element && typeof element.value !== 'undefined') {
              const value = element[stringFromMemory(propPtr, propLen)];
              const encoder = new TextEncoder();
              const encodedValue = encoder.encode(value);
              const wasmMemory = new Uint8Array(memory.buffer);
              const len = Math.min(encodedValue.length, bufLen);
              wasmMemory.set(encodedValue.subarray(0, len), bufPtr);
              return len;
            } else {
              return 0;
            }
          },
          getElementInnerHTML: function(selectorPtr, selectorLen, bufPtr, bufLen) {
              const element = document.querySelector(stringFromMemory(selectorPtr, selectorLen));
              if (element && typeof element.innerHTML !== 'undefined') {
                  const value = element.innerHTML;
                  const encoder = new TextEncoder();
                  const encodedValue = encoder.encode(value);
                  const wasmMemory = new Uint8Array(memory.buffer);
                  const len = Math.min(encodedValue.length, bufLen);
                  wasmMemory.set(encodedValue.subarray(0, len), bufPtr);
                  return len;
              } else {
                  return 0;
              }
          },
          
          // immediate-mode functions
          beginRender: function(parentId) {
            const parent = elementCache[parentId];
            // Clear existing content
            parent.innerHTML = '';
            currentParent = parent;
            nodeStack = [parent];
          },
          createElementImmediate: function(tagPtr, tagLen) {
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
          createTextImmediate: function(textPtr, textLen) {
            const text = stringFromMemory(textPtr, textLen);
            const textNode = document.createTextNode(text);
            nodeStack.push(textNode);
          },
          createHtmlImmediate: function(htmlPtr, htmlLen) {
            const parser = new DOMParser();
            const doc = parser.parseFromString(stringFromMemory(htmlPtr, htmlLen), 'text/html');
            nodeStack.push(doc.body);
          },
          setAttributeImmediate: function(namePtr, nameLen, valuePtr, valueLen) {
            const name = stringFromMemory(namePtr, nameLen);
            const value = stringFromMemory(valuePtr, valueLen);
            const current = nodeStack[nodeStack.length - 1];
            if (current.nodeType === 1) { // Element node
              current.setAttribute(name, value);
            }
          },
          addEventImmediate: function(eventPtr, eventLen, callbackPtr, ctxPtr, data) {
            const eventName = stringFromMemory(eventPtr, eventLen);
            const current = nodeStack[nodeStack.length - 1];
            if (current.nodeType === 1) { // Element node
              current.addEventListener(eventName, () => {
                instance.exports.callZigCallback(callbackPtr, ctxPtr, data);
              });
            }
          },
          appendChildImmediate: function() {
            if (nodeStack.length >= 2) {
              const child = nodeStack.pop();
              const parent = nodeStack[nodeStack.length - 1];
              parent.appendChild(child);
            }
          },
          endRender: function() {
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
  }

  window.addEventListener("load", init);

  function callWasmCallback(callbackPtr, ctxPtr, data) {
    instance.exports.callZigCallback(callbackPtr, ctxPtr, data);
  }