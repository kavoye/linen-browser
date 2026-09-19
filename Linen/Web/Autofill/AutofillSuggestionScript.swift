// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

nonisolated enum AutofillSuggestionScript {
    static let source = #"""
    (() => {
      if (globalThis.__linenAutofillSuggestions) return;
      const forms = globalThis.__linenAutofillForms;
      const active = () => {
        let el = document.activeElement;
        while (el?.shadowRoot?.activeElement) el = el.shadowRoot.activeElement;
        return el;
      };
      const geometry = target => {
        if (!target?.isConnected) return null;
        let rect = target.getBoundingClientRect();
        let x = rect.x, y = rect.y, width = rect.width, height = rect.height, view = window;
        try {
          for (let depth = 0; view !== view.top && depth < 20; depth++) {
            if (x + width <= 0 || y + height <= 0 || x >= view.innerWidth || y >= view.innerHeight) return null;
            const frame = view.frameElement;
            if (!frame) return {x,y,width,height,viewportWidth:view.innerWidth,viewportHeight:view.innerHeight,embedded:1};
            if (!frame.offsetWidth || !frame.offsetHeight) return null;
            for (let node = frame, count = 0; node?.nodeType === 1 && count < 100; count++) {
              const css = view.parent.getComputedStyle(node);
              if (node.hasAttribute('hidden') || node.hasAttribute('inert') || css.display === 'none' || css.visibility !== 'visible' || Number(css.opacity) === 0) return null;
              node = node.assignedSlot || node.parentElement || node.getRootNode()?.host;
            }
            const bounds = frame.getBoundingClientRect();
            const transform = view.parent.getComputedStyle(frame).transform;
            if (transform !== 'none') {
              const matrix = new DOMMatrixReadOnly(transform);
              if (!matrix.is2D || matrix.b || matrix.c) return null;
            }
            const sx = bounds.width / frame.offsetWidth, sy = bounds.height / frame.offsetHeight;
            x = bounds.x + (frame.clientLeft + x) * sx;
            y = bounds.y + (frame.clientTop + y) * sy;
            width *= sx; height *= sy;
            view = view.parent;
          }
          if (view !== view.top) return null;
          const viewport = view.visualViewport;
          return {x:x - (viewport?.offsetLeft || 0), y:y - (viewport?.offsetTop || 0), width, height,
            viewportWidth:viewport?.width || view.innerWidth, viewportHeight:viewport?.height || view.innerHeight};
        } catch { return null; }
      };
      const frameBounds = origin => {
        if (window !== window.top) return null;
        const frame = active();
        if (!(frame instanceof HTMLIFrameElement) || !frame.isConnected || !frame.offsetWidth || !frame.offsetHeight) return null;
        try { if (new URL(frame.src,location.href).origin !== origin) return null; } catch { return null; }
        for (let node = frame, depth = 0; node instanceof Element && depth < 100; depth++) {
          const css = getComputedStyle(node);
          if (node.hasAttribute('hidden') || node.hasAttribute('inert') || css.display === 'none' || css.visibility !== 'visible' || Number(css.opacity) === 0) return null;
          if (css.transform !== 'none') {
            const matrix = new DOMMatrixReadOnly(css.transform);
            if (!matrix.is2D || matrix.b || matrix.c) return null;
          }
          node = node.assignedSlot || node.parentElement || node.getRootNode()?.host;
        }
        const rect = geometry(frame);
        if (!rect) return null;
        const sx = rect.width / frame.offsetWidth, sy = rect.height / frame.offsetHeight;
        return {...rect,x:rect.x + frame.clientLeft*sx,y:rect.y + frame.clientTop*sy,
          width:frame.clientWidth*sx,height:frame.clientHeight*sy};
      };
      const track = (channel, state, accepts) => {
        const hide = () => { if (state.token) channel?.postMessage({action:'hide',token:state.token}); };
        const clear = () => {
          if (state.token) channel?.postMessage({action:'dismiss',token:state.token});
          state.token = null; state.target = null;
        };
        const rememberTarget = target => {
          if (!(target instanceof HTMLInputElement || target instanceof HTMLSelectElement || target instanceof HTMLTextAreaElement) ||
              target !== active() || !accepts(target)) { clear(); return; }
          const formID = forms.group(target)?.id;
          if (state.target !== target || state.url !== location.href || state.formID !== formID || !state.token) {
            clear();
            state.target = target;
            state.token = crypto.randomUUID();
            state.url = location.href;
            state.formID = formID;
            state.fieldID = forms.id(target);
          }
          channel?.postMessage({action:'select',token:state.token,url:state.url,rect:geometry(target),
            documentID:forms.documentID,formID:state.formID,fieldID:state.fieldID});
        };
        const remember = event => {
          if (event.isTrusted) rememberTarget(event.composedPath()[0]);
        };
        document.addEventListener('focusin', remember, true);
        document.addEventListener('click', remember, true);
        document.addEventListener('focusout', () => {
          queueMicrotask(() => { if (state.target && active() !== state.target) clear(); });
        }, true);
        document.addEventListener('input', event => { if (event.isTrusted) clear(); }, true);
        document.addEventListener('keydown', event => {
          if (event.isTrusted && event.key === 'Escape') clear();
        }, true);
        document.addEventListener('contextmenu', clear, true);
        document.addEventListener('scroll', clear, true);
        window.addEventListener('resize', clear);
        window.addEventListener('pagehide', clear);
        window.addEventListener('blur', hide);
        document.addEventListener('visibilitychange', () => { if (document.hidden) clear(); });
        window.visualViewport?.addEventListener('resize', clear);
        window.visualViewport?.addEventListener('scroll', clear);
        forms.subscribe(() => {
          if (state.target && (!state.target.isConnected || active() !== state.target)) clear();
        });
        return {clear,refresh:() => rememberTarget(active())};
      };
      const valid = (state,token,url) => !!token && state.token === token && state.url === url &&
        location.href === url && active() === state.target && forms.id(state.target) === state.fieldID &&
        forms.group(state.target)?.id === state.formID;
      globalThis.__linenAutofillSuggestions = {active,geometry,frameBounds,track,valid};
    })();
    """#
}
