// Helper function to check if a string contains dynamic content
function isDynamic(str) {
    return str.includes('{') && str.includes('}');
}

// Helper function to extract field name from dynamic string
function extractFieldName(str) {
    const match = str.match(/\{([^}]+)\}/);
    return match ? match[1] : str;
}

// Helper function to check if attribute is an event handler
function isEventHandler(attrName) {
    return attrName.startsWith('on');
}

// Helper function to extract event name from attribute name
function getEventName(attrName) {
    return attrName.startsWith('on') ? attrName.slice(2) : attrName;
}

// Self-closing HTML tags
const SELF_CLOSING_TAGS = new Set([
    'area', 'base', 'br', 'col', 'embed', 'hr', 'img', 
    'input', 'link', 'meta', 'param', 'source', 'track', 'wbr'
]);

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
    
    addSelfClosingTag() {
        this.addInstruction(2, 0); // self_closing_tag = 2
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
                // Static name, dynamic value
                this.addStaticDynAttr(name, extractFieldName(value));
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
        
        // Close tag (unless self-closing)
        if (SELF_CLOSING_TAGS.has(tagName)) {
            this.addSelfClosingTag();
        } else {
            this.addStaticTagClose();
        }
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
        // Calculate total size needed
        let totalSize = 0;
        
        // Array lengths (10 * 4 bytes)
        totalSize += 10 * 4;
        
        // Instructions array
        totalSize += this.instructions.length * 4;
        
        // Strings array
        totalSize += this.strings.length;
        
        // StringRef arrays (each StringRef is 8 bytes: offset + len)
        totalSize += this.tagOpens.length * 8;
        totalSize += this.texts.length * 8;
        totalSize += this.staticAttrs.length * 16; // 2 StringRefs
        totalSize += this.dynTexts.length * 8;
        totalSize += this.staticDynAttrs.length * 16;
        totalSize += this.dynStaticAttrs.length * 16;
        totalSize += this.dynDynAttrs.length * 16;
        totalSize += this.dynEvents.length * 16;
        
        // Create buffer
        const buffer = new ArrayBuffer(totalSize);
        const view = new DataView(buffer);
        let offset = 0;
        
        // Write array lengths
        view.setUint32(offset, this.instructions.length, true); offset += 4;
        view.setUint32(offset, this.strings.length, true); offset += 4;
        view.setUint32(offset, this.tagOpens.length, true); offset += 4;
        view.setUint32(offset, this.texts.length, true); offset += 4;
        view.setUint32(offset, this.staticAttrs.length, true); offset += 4;
        view.setUint32(offset, this.dynTexts.length, true); offset += 4;
        view.setUint32(offset, this.staticDynAttrs.length, true); offset += 4;
        view.setUint32(offset, this.dynStaticAttrs.length, true); offset += 4;
        view.setUint32(offset, this.dynDynAttrs.length, true); offset += 4;
        view.setUint32(offset, this.dynEvents.length, true); offset += 4;
        
        // Write instructions
        for (const instruction of this.instructions) {
            view.setUint32(offset, instruction, true);
            offset += 4;
        }
        
        // Write strings
        for (const byte of this.strings) {
            view.setUint8(offset, byte);
            offset += 1;
        }
        
        // Helper to write StringRef
        const writeStringRef = (ref) => {
            view.setUint32(offset, ref.offset, true); offset += 4;
            view.setUint32(offset, ref.len, true); offset += 4;
        };
        
        // Write StringRef arrays
        for (const ref of this.tagOpens) writeStringRef(ref);
        for (const ref of this.texts) writeStringRef(ref);
        for (const [name, value] of this.staticAttrs) {
            writeStringRef(name);
            writeStringRef(value);
        }
        for (const ref of this.dynTexts) writeStringRef(ref);
        for (const [name, field] of this.staticDynAttrs) {
            writeStringRef(name);
            writeStringRef(field);
        }
        for (const [field, value] of this.dynStaticAttrs) {
            writeStringRef(field);
            writeStringRef(value);
        }
        for (const [nameField, valueField] of this.dynDynAttrs) {
            writeStringRef(nameField);
            writeStringRef(valueField);
        }
        for (const [event, handler] of this.dynEvents) {
            writeStringRef(event);
            writeStringRef(handler);
        }
        
        return new Uint8Array(buffer);
    }
}
