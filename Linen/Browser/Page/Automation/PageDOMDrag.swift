// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import WebKit

extension PageDriver {
    /// AppKit's local mouse events do not set WebKit's held-button state. Use an explicit
    /// DOM event sequence for application drag handlers; these events are not trusted input.
    static func dispatchDrag(path: [CGPoint], modifiers: NSEvent.ModifierFlags, in view: WKWebView) async throws {
        let points = path.map { [Double($0.x / view.pageZoom), Double($0.y / view.pageZoom)] }
        let encoded = String(decoding: try JSONEncoder().encode(points), as: UTF8.self)
        let result = await evaluateJSON(scripted("""
            const path = \(encoded);
            const hit = ([x,y]) => {
              let el = document.elementFromPoint(x,y);
              for (let i=0; i<30 && el?.shadowRoot; i++) {
                const child = el.shadowRoot.elementFromPoint(x,y);
                if (!child || child === el) break;
                el = child;
              }
              return el;
            };
            const eligible = el => el?.isConnected && !['IFRAME','FRAME'].includes(el.tagName) &&
              !R.isSensitiveField(el) && !R.disabled(el) && !(el.tagName === 'INPUT' && el.type === 'file');
            if (!path.every(p => eligible(hit(p)))) return JSON.stringify({ ok: false });
            const source = hit(path[0]), end = path[path.length-1];
            const options = (p,buttons) => ({ bubbles:true, composed:true, cancelable:true, view:window,
              clientX:p[0], clientY:p[1], button:0, buttons,
              shiftKey:\(modifiers.contains(.shift)), ctrlKey:\(modifiers.contains(.control)),
              altKey:\(modifiers.contains(.option)), metaKey:\(modifiers.contains(.command)) });
            const mouse = (el,type,p,buttons) => el.dispatchEvent(new MouseEvent(type,options(p,buttons)));
            const pointer = (el,type,p,buttons) => el.dispatchEvent(new PointerEvent(type, {
              ...options(p,buttons), pointerId:1, pointerType:'mouse', isPrimary:true, pressure:buttons ? 0.5 : 0 }));
            const draggable = source.closest('[draggable=true]');
            if (draggable) {
              const data = new DataTransfer();
              const drag = (el,type,p) => el.dispatchEvent(new DragEvent(type,{...options(p,1),dataTransfer:data}));
              if (!drag(draggable,'dragstart',path[0])) return JSON.stringify({ ok:false });
              let previous = source;
              try {
                for (const p of path.slice(1)) {
                  const target = hit(p);
                  if (!eligible(target) || !draggable.isConnected) return JSON.stringify({ ok:false });
                  drag(draggable,'drag',p);
                  if (target !== previous) { drag(previous,'dragleave',p); drag(target,'dragenter',p); }
                  const accepts = !drag(target,'dragover',p);
                  if (p === end && accepts) drag(target,'drop',p);
                  previous = target;
                }
              } finally { drag(draggable,'dragend',end); }
            } else {
              pointer(source,'pointerdown',path[0],1);
              mouse(source,'mousedown',path[0],1);
              try {
                for (const p of path.slice(1)) {
                  if (!source.isConnected || !eligible(hit(p))) return JSON.stringify({ ok:false });
                  pointer(source,'pointermove',p,1);
                  mouse(source,'mousemove',p,1);
                }
              } finally {
                pointer(source,'pointerup',end,0);
                mouse(source,'mouseup',end,0);
              }
            }
            return JSON.stringify({ ok:true });
            """), in: view)
        guard result?["ok"] as? Bool == true else { throw PageComputerFailure.unverified }
    }
}
