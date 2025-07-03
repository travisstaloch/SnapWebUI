
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
          getEncodedTemplateSize: function(selectorPtr, selectorLen) {
            try {
              const selector = stringFromMemory(selectorPtr, selectorLen);
              const element = document.querySelector(selector);
              if (!element) {
                  console.warn('Template not found:', selector);
                  return 0;
              }
              const templateEncoder = new TemplateEncoder();
              templateEncoder.reset();
              for (const child of element.content ? element.content.childNodes : element.childNodes) {
                  templateEncoder.encodeNode(child);
              }
              const serialized = templateEncoder.serialize();
              // Return the length, and store the serialized data in a temporary global
              // This is a workaround for the current synchronous WASM call pattern.
              // A more robust solution would involve passing the data directly.
              window._currentSerializedTemplate = serialized;
              return serialized.length;
            } catch (error) {
              console.error('Error getting encoded template size:', error);
              return 0;
            }
          },
          encodeTemplate: function(bufferPtr, bufferLen) {
            try {
              const serialized = window._currentSerializedTemplate;
              if (!serialized) {
                  console.error('No serialized template data available.');
                  return 0;
              }
              if (bufferLen < serialized.length) {
                  console.error('Buffer too small for encoded template.');
                  return 0;
              }
              const wasmBuffer = new Uint8Array(memory.buffer, bufferPtr, bufferLen);
              wasmBuffer.set(serialized);
              delete window._currentSerializedTemplate; // Clean up
              return serialized.length;
            } catch (error) {
              console.error('Error encoding template:', error);
              return 0;
            }
          },
          setTextContent: function(nodeId, textPtr, textLen) {
            const element = elementCache[nodeId];
            const text = stringFromMemory(textPtr, textLen);
            if (element) element.textContent = text;
          },
          requestAnimationFrame: function(callbackPtr, ctxPtr) {
            requestAnimationFrame(() => {
              instance.exports.callZigCallback(callbackPtr, ctxPtr, 0);
            });
          }
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

  // Helper function to check if a string contains dynamic content
function isDynamic(str) {
    return str.includes('{') && str.includes('}');
}

// Helper function to extract field name from dynamic string
function extractFieldName(str) {
    const match = str.match(/\{([^}]+)\}/);
    return match ? match[1] : str;
}

// Helper function to parse dynamic attribute values like "{part1} static {part2}"
function parseDynamicAttributeValue(value) {
    const parts = [];
    let lastIndex = 0;
    const dynamicRegex = /\{([^}]+)\}/g;
    let match;

    while ((match = dynamicRegex.exec(value)) !== null) {
        // Add static part before the dynamic part
        if (match.index > lastIndex) {
            parts.push({ type: 'static', value: value.substring(lastIndex, match.index) });
        }
        // Add dynamic part
        parts.push({ type: 'dynamic', value: match[1] });
        lastIndex = match.index + match[0].length;
    }

    // Add any remaining static part
    if (lastIndex < value.length) {
        parts.push({ type: 'static', value: value.substring(lastIndex) });
    }
    return parts;
}

// TODO use 'eh__' prefix of attr value instead of 'on' prefix of attr name
// Helper function to check if attribute is an event handler
function isEventHandler(attrName) {
    return attrName.startsWith('on');
}

// Helper function to extract event name from attribute name
function getEventName(attrName) {
    return attrName.startsWith('on') ? attrName.slice(2) : attrName;
}

class TemplateEncoder {
    constructor() {
        this.reset();
    }
    
    reset() {
        this.instructions = [];
        this.strings = [];
        this.stringMap = new Map(); // For deduplication
        
        this.tagOpens = [];
        this.texts = [];
        this.staticAttrs = [];
        this.dynTexts = [];
        this.staticDynAttrs = [];
        this.dynStaticAttrs = [];
        this.dynDynAttrs = [];
        this.dynEvents = [];
        this.serializedDynAttrValueParts = []; // Stores raw serialized bytes for each part
        this.dynAttributeValuePartRefs = []; // Stores StringRefs to serializedDynAttrValueParts
    }
    
    addString(str) {
        if (this.stringMap.has(str)) {
            return this.stringMap.get(str);
        }
        
        const offset = this.strings.length;
        for (let i = 0; i < str.length; i++) {
            this.strings.push(str.charCodeAt(i));
        }
        
        const ref = { offset, len: str.length };
        this.stringMap.set(str, ref);
        return ref;
    }
    
    addInstruction(tag, payloadIndex) {
        // Pack tag (8 bits) and payload index (24 bits) into 32-bit value
        const packed = (tag & 0xFF) | ((payloadIndex & 0xFFFFFF) << 8);
        this.instructions.push(packed);
    }
    
    addStaticTagOpen(tagName) {
        const stringRef = this.addString(tagName);
        const payloadIndex = this.tagOpens.length;
        this.tagOpens.push(stringRef);
        this.addInstruction(0, payloadIndex); // static_tag_open = 0
    }
    
    addStaticTagClose() {
        this.addInstruction(1, 0); // static_tag_close = 1
    }
    
    addStaticText(text) {
        const stringRef = this.addString(text);
        const payloadIndex = this.texts.length;
        this.texts.push(stringRef);
        this.addInstruction(3, payloadIndex); // static_text = 3
    }
    
    addStaticAttribute(name, value) {
        const nameRef = this.addString(name);
        const valueRef = this.addString(value);
        const payloadIndex = this.staticAttrs.length;
        this.staticAttrs.push([nameRef, valueRef]);
        this.addInstruction(4, payloadIndex); // static_attribute = 4
    }
    
    addDynText(fieldName) {
        const stringRef = this.addString(fieldName);
        const payloadIndex = this.dynTexts.length;

        this.dynTexts.push(stringRef);
        this.addInstruction(5, payloadIndex); // dyn_text = 5
    }
    
    addStaticDynAttr(name, fieldName) {
        const nameRef = this.addString(name);
        const fieldRef = this.addString(fieldName);
        const payloadIndex = this.staticDynAttrs.length;
        this.staticDynAttrs.push([nameRef, fieldRef]);
        this.addInstruction(6, payloadIndex); // static_dyn_attr = 6
    }
    
    addDynStaticAttr(fieldName, value) {
        const fieldRef = this.addString(fieldName);
        const valueRef = this.addString(value);
        const payloadIndex = this.dynStaticAttrs.length;
        this.dynStaticAttrs.push([fieldRef, valueRef]);
        this.addInstruction(7, payloadIndex); // dyn_static_attr = 7
    }
    
    addDynDynAttr(nameField, valueField) {
        const nameRef = this.addString(nameField);
        const valueRef = this.addString(valueField);
        const payloadIndex = this.dynDynAttrs.length;
        this.dynDynAttrs.push([nameRef, valueRef]);
        this.addInstruction(8, payloadIndex); // dyn_dyn_attr = 8
    }
    
    addDynEvent(eventName, handlerField) {
        const eventRef = this.addString(eventName);
        const handlerRef = this.addString(handlerField);
        const payloadIndex = this.dynEvents.length;
        this.dynEvents.push([eventRef, handlerRef]);
        this.addInstruction(9, payloadIndex); // dyn_event = 9
    }

    addDynAttributeValueParts(name, parts) {
        const SIZEOF_UINT32 = 4;
        const SIZEOF_STRING_REF = 8;

        // Calculate size for this specific attribute's parts
        let currentPartSize = SIZEOF_STRING_REF; // For nameRef
        currentPartSize += SIZEOF_UINT32; // For parts.length
        currentPartSize += parts.length * (SIZEOF_UINT32 + SIZEOF_STRING_REF); // For each part (type + ref)

        const tempBuffer = new ArrayBuffer(currentPartSize);
        const tempView = new DataView(tempBuffer);
        let tempOffset = 0;

        // Write nameRef
        const nameRef = this.addString(name);
        tempView.setUint32(tempOffset, nameRef.offset, true); tempOffset += SIZEOF_UINT32;
        tempView.setUint32(tempOffset, nameRef.len, true); tempOffset += SIZEOF_UINT32;

        // Write parts.length
        tempView.setUint32(tempOffset, parts.length, true); tempOffset += SIZEOF_UINT32;

        // Write each part
        for (const part of parts) {
            tempView.setUint32(tempOffset, part.type === 'static' ? 0 : 1, true); tempOffset += SIZEOF_UINT32;
            const partRef = this.addString(part.value);
            tempView.setUint32(tempOffset, partRef.offset, true); tempOffset += SIZEOF_UINT32;
            tempView.setUint32(tempOffset, partRef.len, true); tempOffset += SIZEOF_UINT32;
        }

        // Store the serialized part data and a reference to it
        const serializedPart = new Uint8Array(tempBuffer);
        const offset = this.serializedDynAttrValueParts.length;
        for (let i = 0; i < serializedPart.length; i++) {
            this.serializedDynAttrValueParts.push(serializedPart[i]);
        }
        
        const ref = { offset, len: serializedPart.length };
        const payloadIndex = this.dynAttributeValuePartRefs.length;
        this.dynAttributeValuePartRefs.push(ref);
        this.addInstruction(10, payloadIndex); // dyn_attribute_value_parts = 10
    }
    
    encodeElement(element) {
        const tagName = element.tagName.toLowerCase();
        this.addStaticTagOpen(tagName);
        
        // Process attributes
        for (const attr of element.attributes) {
            const name = attr.name;
            const value = attr.value;
            
            const isNameDynamic = isDynamic(name);
            const isValueDynamic = isDynamic(value);
            
            if (isEventHandler(name) && isValueDynamic) {
                // Event handler
                const eventName = getEventName(name);
                let handlerField = extractFieldName(value);
                // Remove eh__ prefix if present
                if (handlerField.startsWith('eh__')) {
                    handlerField = handlerField.slice(4);
                }
                this.addDynEvent(eventName, handlerField);
            } else if (isNameDynamic && isValueDynamic) {
                // Both name and value are dynamic
                this.addDynDynAttr(extractFieldName(name), extractFieldName(value));
            } else if (!isNameDynamic && isValueDynamic) {
                const parsedValue = parseDynamicAttributeValue(value);
                if (parsedValue.length > 1) {
                    // Value has mixed static and dynamic parts
                    this.addDynAttributeValueParts(name, parsedValue);
                } else {
                    // Static name, single dynamic value
                    this.addStaticDynAttr(name, extractFieldName(value));
                }
            } else if (isNameDynamic && !isValueDynamic) {
                // Dynamic name, static value
                this.addDynStaticAttr(extractFieldName(name), value);
            } else {
                // Both static
                this.addStaticAttribute(name, value);
            }
        }
        
        // Process children
        for (const child of element.childNodes) {
            this.encodeNode(child);
        }
        
        // The Zig renderer handles both closing tags and self-closing tags the same way
        this.addStaticTagClose();
    }
    
    encodeTextNode(textNode) {
        const text = textNode.textContent;
        
        // Handle mixed static/dynamic text
        let currentIndex = 0;
        let match;
        const dynamicRegex = /\{([^}]+)\}/g;
        
        while ((match = dynamicRegex.exec(text)) !== null) {
            // Add static text before the dynamic part
            if (match.index > currentIndex) {
                const staticText = text.slice(currentIndex, match.index);
                if (staticText.trim()) {
                    this.addStaticText(staticText);
                }
            }
            
            // Add dynamic text
            const fieldName = match[1];
            this.addDynText(fieldName);
            
            currentIndex = match.index + match[0].length;
        }
        
        // Add remaining static text
        if (currentIndex < text.length) {
            const remainingText = text.slice(currentIndex);
            if (remainingText.trim()) {
                this.addStaticText(remainingText);
            }
        }
    }
    
    encodeNode(node) {
        switch (node.nodeType) {
            case Node.ELEMENT_NODE:
                this.encodeElement(node);
                break;
            case Node.TEXT_NODE:
                if (node.textContent.trim()) {
                    this.encodeTextNode(node);
                }
                break;
            case Node.COMMENT_NODE:
                // Skip comments
                break;
            default:
                console.warn('Unhandled node type:', node.nodeType);
        }
    }
    
    serialize() {
        const SIZEOF_UINT32 = 4;
        const SIZEOF_STRING_REF = 8;
        const ALIGN_OF_STRING_REF = 4;
        const SIZEOF_ATTR_PART_REF = SIZEOF_UINT32 + SIZEOF_STRING_REF; // 12

        const align = (offset, alignment) => {
            return (offset + alignment - 1) & ~(alignment - 1);
        };

        // --- 1. Calculate layout and total size ---
        const layout = {};
        let currentOffset = 0;

        // Header
        layout.header = { offset: currentOffset, size: 12 * SIZEOF_UINT32 };
        currentOffset += layout.header.size;

        // Instructions
        layout.instructions = { offset: currentOffset, size: this.instructions.length * SIZEOF_UINT32 };
        currentOffset += layout.instructions.size;
        
        // Strings
        currentOffset = align(currentOffset, 1); // No-op, for clarity
        layout.strings = { offset: currentOffset, size: this.strings.length };
        currentOffset += layout.strings.size;

        // Helper for StringRef arrays
        const layoutStringRefArray = (name, arr, isPair) => {
            currentOffset = align(currentOffset, ALIGN_OF_STRING_REF);
            const size = arr.length * (isPair ? SIZEOF_STRING_REF * 2 : SIZEOF_STRING_REF);
            layout[name] = { offset: currentOffset, size: size };
            currentOffset += size;
        };

        layoutStringRefArray('tagOpens', this.tagOpens, false);
        layoutStringRefArray('texts', this.texts, false);
        layoutStringRefArray('staticAttrs', this.staticAttrs, true);
        layoutStringRefArray('dynTexts', this.dynTexts, false);
        layoutStringRefArray('staticDynAttrs', this.staticDynAttrs, true);
        layoutStringRefArray('dynStaticAttrs', this.dynStaticAttrs, true);
        layoutStringRefArray('dynDynAttrs', this.dynDynAttrs, true);
        layoutStringRefArray('dynEvents', this.dynEvents, true);

        // New array for dynAttributeValuePartRefs
        currentOffset = align(currentOffset, ALIGN_OF_STRING_REF);
        layout.dynAttributeValuePartRefs = { offset: currentOffset, size: this.dynAttributeValuePartRefs.length * SIZEOF_STRING_REF };
        currentOffset += layout.dynAttributeValuePartRefs.size;

        // Raw serialized bytes for dynamic attribute value parts
        // skip alignment here for bytes
        layout.serializedDynAttrValueParts = { offset: currentOffset, size: this.serializedDynAttrValueParts.length };
        currentOffset += layout.serializedDynAttrValueParts.size;

        const totalSize = currentOffset;

        // --- 2. Create buffer and write data ---
        const buffer = new ArrayBuffer(totalSize);
        const view = new DataView(buffer);
        
        // Write header (array lengths)
        let headerOffset = layout.header.offset;
        view.setUint32(headerOffset, this.instructions.length, true); headerOffset += 4;
        view.setUint32(headerOffset, this.strings.length, true); headerOffset += 4;
        view.setUint32(headerOffset, this.tagOpens.length, true); headerOffset += 4;
        view.setUint32(headerOffset, this.texts.length, true); headerOffset += 4;
        view.setUint32(headerOffset, this.staticAttrs.length, true); headerOffset += 4;
        view.setUint32(headerOffset, this.dynTexts.length, true); headerOffset += 4;
        view.setUint32(headerOffset, this.staticDynAttrs.length, true); headerOffset += 4;
        view.setUint32(headerOffset, this.dynStaticAttrs.length, true); headerOffset += 4;
        view.setUint32(headerOffset, this.dynDynAttrs.length, true); headerOffset += 4;
        view.setUint32(headerOffset, this.dynEvents.length, true); headerOffset += 4;
        view.setUint32(headerOffset, this.dynAttributeValuePartRefs.length, true); headerOffset += 4; // New length
        view.setUint32(headerOffset, this.serializedDynAttrValueParts.length, true); headerOffset += 4; // New length

        // Write instructions
        let instOffset = layout.instructions.offset;
        for (const instruction of this.instructions) {
            view.setUint32(instOffset, instruction, true);
            instOffset += 4;
        }

        // Write strings
        let stringsOffset = layout.strings.offset;
        for (const byte of this.strings) {
            view.setUint8(stringsOffset, byte);
            stringsOffset += 1;
        }

        // Helper to write StringRef
        const writeStringRef = (ref, offset) => {
            view.setUint32(offset, ref.offset, true);
            view.setUint32(offset + 4, ref.len, true);
            return offset + SIZEOF_STRING_REF;
        };

        // Helper to write StringRef arrays
        const writeArray = (name, arr, isPair) => {
            let offset = layout[name].offset;
            if (isPair) {
                for (const [item1, item2] of arr) {
                    offset = writeStringRef(item1, offset);
                    offset = writeStringRef(item2, offset);
                }
            } else {
                for (const item of arr) {
                    offset = writeStringRef(item, offset);
                }
            }
        };

        writeArray('tagOpens', this.tagOpens, false);
        writeArray('texts', this.texts, false);
        writeArray('staticAttrs', this.staticAttrs, true);
        writeArray('dynTexts', this.dynTexts, false);
        writeArray('staticDynAttrs', this.staticDynAttrs, true);
        writeArray('dynStaticAttrs', this.dynStaticAttrs, true);
        writeArray('dynDynAttrs', this.dynDynAttrs, true);
        writeArray('dynEvents', this.dynEvents, true);

        // Write dynAttributeValuePartRefs
        writeArray('dynAttributeValuePartRefs', this.dynAttributeValuePartRefs, false);

        // Write serializedDynAttrValueParts
        let serializedDynAttrValuePartsOffset = layout.serializedDynAttrValueParts.offset;
        for (const byte of this.serializedDynAttrValueParts) {
            view.setUint8(serializedDynAttrValuePartsOffset, byte);
            serializedDynAttrValuePartsOffset += 1;
        }

        return new Uint8Array(buffer);
    }
}
