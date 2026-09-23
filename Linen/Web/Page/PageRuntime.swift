// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

nonisolated enum PageRuntime {
    static let script = #"""
      const R = (window.__linen = window.__linen || (() => {
      const norm = s => (s || '').replace(/\s+/g, ' ').trim();
      const documentID = Array.from(crypto.getRandomValues(new Uint32Array(4)), n => n.toString(16)).join('-');
      const refIDs = new WeakMap();
      const refSignatures = new Map();
      const expectedValues = new WeakMap();
      let lastControlQuery = null;
      window.__linenRefs = [];
      const parentOf = el => el.parentElement || el.getRootNode()?.host || el.ownerDocument?.defaultView?.frameElement;

      function* walk(root) {
        for (const el of root.querySelectorAll('*')) {
          yield el;
          if (el.shadowRoot) yield* walk(el.shadowRoot);
          if (el.tagName === 'IFRAME') {
            try {
              if (el.contentDocument && el.contentDocument.body) yield* walk(el.contentDocument.body);
            } catch (e) {}
          }
        }
      }

      const visible = el => {
        const frame = el.ownerDocument.defaultView?.frameElement;
        if (frame && !visible(frame)) return false;
        try { if (el.checkVisibility && !el.checkVisibility()) return false; } catch (e) {}
        const style = realm(el).getComputedStyle(el);
        return style.visibility !== 'hidden' && style.visibility !== 'collapse' && el.getClientRects().length > 0;
      };

      const inViewport = el => {
        const rect = el.getBoundingClientRect(), view = realm(el);
        return rect.bottom > 0 && rect.top < view.innerHeight && rect.right > 0 && rect.left < view.innerWidth
          && (!view.frameElement || inViewport(view.frameElement));
      };
      const within = (root, el) => {
        for (let node = el; node; node = parentOf(node)) if (node === root) return true;
        return false;
      };

      const disabled = el => {
        for (let node = el; node; node = parentOf(node)) {
          if (node.getAttribute('aria-disabled') === 'true') return true;
        }
        return !!el.disabled || el.matches(':disabled');
      };
      const accessibleName = el => {
        const ids = norm(el.getAttribute('aria-labelledby')).split(' ').filter(Boolean);
        const root = el.getRootNode();
        const named = ids.map(id => root.getElementById?.(id)?.textContent || '').join(' ');
        return norm(named) || norm(el.getAttribute('aria-label'));
      };

      const kindOf = el => {
        const tag = el.tagName;
        if (tag === 'SELECT') return 'select';
        if (tag === 'TEXTAREA') return 'field';
        if (tag === 'INPUT') {
          const t = (el.type || 'text').toLowerCase();
          if (t === 'hidden') return null;
          if (t === 'submit' || t === 'button' || t === 'image') return 'button';
          if (t === 'checkbox') return 'checkbox';
          if (t === 'radio') return 'radio';
          return 'field';
        }
        if (tag === 'BUTTON' || tag === 'SUMMARY') return 'button';
        if (tag === 'A' && el.href) return 'link';
        const role = el.getAttribute && el.getAttribute('role');
        if (['checkbox', 'radio', 'switch'].includes(role)) return role === 'switch' ? 'checkbox' : role;
        if (['textbox', 'searchbox'].includes(role)) return 'field';
        if (role === 'combobox') return el.isContentEditable || tag === 'INPUT' ? 'field' : 'combobox';
        if (['button', 'tab', 'menuitem', 'menuitemcheckbox', 'menuitemradio', 'link', 'option'].includes(role)) return 'button';
        if (role === 'gridcell' && el.hasAttribute('tabindex')
          && !el.querySelector('button,a[href],input,select,textarea,[role=button]')) return 'button';
        if (el.hasAttribute && el.hasAttribute('onclick')) return 'button';
        if (el.isContentEditable && !(el.parentElement && el.parentElement.isContentEditable)) return 'field';
        if (role === 'region' || (el.scrollHeight > el.clientHeight + 1 && ['auto','scroll'].includes(realm(el).getComputedStyle(el).overflowY))) return 'scrollarea';
        return null;
      };

      const controlLabel = el => norm(
        accessibleName(el) || el.innerText || el.value || el.title || el.querySelector('img[alt]')?.alt || ''
      ).slice(0, 60);
      const fieldLabel = el => {
        const assoc = el.labels && el.labels.length ? el.labels[0].innerText : '';
        return norm(
          accessibleName(el) || assoc || el.placeholder || el.name || el.id || ''
        ).slice(0, 60);
      };
      const labelOf = (el, kind) => ['button', 'link', 'combobox', 'scrollarea'].includes(kind) ? controlLabel(el) : fieldLabel(el);

      const isSensitiveField = el => {
        if (el.hasAttribute('data-linen-payment-card') || el.hasAttribute('data-linen-contact') || el.hasAttribute('data-linen-password')) return true;
        const kind = ((el.type || '') + '').toLowerCase();
        if (kind === 'password') return true;
        const auto = norm(el.autocomplete).toLowerCase();
        const hint = (fieldLabel(el) + ' ' + auto + ' ' + norm(el.name) + ' ' + norm(el.id)).toLowerCase();
        if (/(?:^| )(?:current-password|new-password|one-time-code|cc-number|cc-exp|cc-exp-month|cc-exp-year|cc-csc|cc-name)(?: |$)/.test(auto)) return true;
        return /password|passcode|\bpin\b|cvv|cvc|cvn|card ?number|cardnumber|card verification|security code|iban|sort ?code|routing/.test(hint)
          || /account ?number|ssn|social security|national insurance|passport|tax ?id|one[- ]?time|\botp\b|2fa|verification code|seed phrase|recovery phrase|private key/.test(hint);
      };

      const signature = el => JSON.stringify([kindOf(el), labelOf(el, kindOf(el)), el.id, el.name,
        el.type, el.href, el.getAttribute('formaction'), el.form?.action, el.form?.method]);
      const matchesRef = ref => {
        const el = window.__linenRefs[ref - 1];
        return !!el?.isConnected && signature(el) === refSignatures.get(ref);
      };
      const expectValue = (el, value) => expectedValues.set(el, { value, signature: signature(el) });
      const valueState = ref => {
        const el = window.__linenRefs[ref - 1];
        const expected = el && expectedValues.get(el);
        if (!el?.isConnected || !expected || signature(el) !== expected.signature || isSensitiveField(el)) return 'unverified';
        return (el.isContentEditable ? el.textContent : el.value) === expected.value ? 'matched' : 'mismatch';
      };

      const collect = () => {
        window.__linenSnapshot = Date.now().toString(36) + Math.random().toString(36);
        const out = [];
        if (!document.body) return out;
        for (const el of walk(document.body)) {
          const kind = kindOf(el);
          if (!kind || !visible(el)) continue;
          const label = labelOf(el, kind);
          if (!label && !['field', 'select', 'scrollarea'].includes(kind)) continue;
          let dup = false;
          for (let a = el.parentElement, hops = 0; a && hops < 3; a = a.parentElement, hops++) {
            if (a.__linenRef && ['button', 'link'].includes(kindOf(a)) && ['button', 'link'].includes(kind) && labelOf(a, 'button') === label) { dup = true; break; }
          }
          if (dup) continue;

          let ref = refIDs.get(el);
          if (!ref) { ref = window.__linenRefs.push(el); refIDs.set(el, ref); }
          el.__linenRef = ref;
          refSignatures.set(ref, signature(el));
          const entry = { r: ref, k: kind, l: label };
          if (kind === 'link' && el.href.length <= 2048) entry.h = el.href;
          if (kind === 'field') {
            if (el.readOnly || el.getAttribute('aria-readonly') === 'true') entry.ro = 1;
            entry.t = ((el.type || (el.isContentEditable ? 'editable' : 'text')) + '').toLowerCase();
            const v = norm(el.value || (el.isContentEditable ? el.textContent : '') || '');
            if (isSensitiveField(el)) {
              entry.s = 1;
              entry.f = v ? 1 : 0;
            } else if (v) {
              entry.v = v.slice(0, 30);
            }
          }
          if (kind === 'select') {
            if (isSensitiveField(el)) {
              entry.s = 1;
              entry.f = el.value ? 1 : 0;
            } else {
              entry.v = el.selectedIndex >= 0 ? norm(el.options[el.selectedIndex].text).slice(0, 30) : '';
              entry.o = Array.from(el.options).slice(0, 3).map(o => norm(o.text).slice(0, 45));
              entry.oc = el.options.length;
            }
          }
          if (kind === 'checkbox' || kind === 'radio') entry.c = el.checked || el.getAttribute('aria-checked') === 'true' ? 1 : 0;
          if (disabled(el)) entry.d = 1;
          const rect = el.getBoundingClientRect();
          entry.vp = inViewport(el);
          const frame = el.ownerDocument.defaultView?.frameElement;
          if (frame) entry.frame = frame.title || frame.name || 'embedded frame';
          if (el.getAttribute('aria-expanded')) entry.expanded = el.getAttribute('aria-expanded');
          out.push(entry);
        }
        return out;
      };

      const pageText = (viewportOnly = false) => {
        const parts = [];
        const visit = root => {
          if (!root) return;
          const doc = root.ownerDocument || document;
          const walker = doc.createTreeWalker(root, NodeFilter.SHOW_TEXT);
          let node;
          while ((node = walker.nextNode())) {
            const el = node.parentElement;
            if (!el || el.closest('script,style,noscript,template') || !visible(el)) continue;
            const rect = el.getBoundingClientRect();
            if (viewportOnly && !inViewport(el)) continue;
            const field = el.closest('textarea,input,[contenteditable],[role=textbox],[role=searchbox]');
            if (field && isSensitiveField(field)) continue;
            const t = norm(node.textContent);
            if (t) parts.push(t);
          }
          for (const el of root.querySelectorAll('*')) {
            if (el.shadowRoot) visit(el.shadowRoot);
            if (el.tagName === 'IFRAME') { try { visit(el.contentDocument?.body); } catch (e) {} }
          }
        };
        visit(document.body);
        return norm(parts.join(' '));
      };

      const viewportText = limit => {
        const height = window.innerHeight;
        const parts = [];
        const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
        let node;
        while ((node = walker.nextNode())) {
          const t = norm(node.textContent);
          if (!t) continue;
          const parent = node.parentElement;
          if (!parent) continue;
          const r = parent.getBoundingClientRect();
          if (r.bottom <= 0 || r.top >= height || r.width === 0) continue;
          parts.push(t);
          if (parts.join(' ').length > limit) break;
        }
        const joined = norm(parts.join(' ')).slice(0, limit);
        return joined || pageText().slice(0, limit);
      };

      const resolve = (ref, label, kinds) => {
        if (ref > 0) {
          const el = window.__linenRefs[ref - 1];
          if (!el || !el.isConnected || !kinds.includes(kindOf(el))) return { stale: true };
          return { el };
        }
        const t = norm(label).toLowerCase();
        const candidates = [];
        for (const el of window.__linenRefs) {
          if (!el.isConnected) continue;
          const kind = kindOf(el);
          if (!kind || !kinds.includes(kind)) continue;
          candidates.push({ el, label: labelOf(el, kind).toLowerCase() });
        }
        let matches = candidates.filter(c => c.label === t);
        if (!matches.length) matches = candidates.filter(c => t && c.label.includes(t));
        if (matches.length > 1) return { ambiguous: true };
        if (matches.length === 1) return { el: matches[0].el };
        return { options: [...new Set(candidates.map(c => c.label).filter(l => l && l.length < 50))].slice(0, 25) };
      };

      const realm = el => (el.ownerDocument && el.ownerDocument.defaultView) || window;

      const setValue = (el, value) => {
        if (el.isContentEditable) {
          el.focus();
          el.textContent = value;
          el.dispatchEvent(new (realm(el).Event)('input', { bubbles: true }));
          return;
        }
        const view = realm(el);
        const proto = el.tagName === 'TEXTAREA' ? view.HTMLTextAreaElement.prototype : view.HTMLInputElement.prototype;
        Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, value);
        el.dispatchEvent(new (view.Event)('input', { bubbles: true }));
        el.dispatchEvent(new (view.Event)('change', { bubbles: true }));
      };

      const highlight = (el, ms) => {
        try {
          const doc = el.ownerDocument;
          const view = doc.defaultView;
          doc.__linenRing?.remove();
          const ring = doc.createElement('div');
          ring.className = '__linen-ring';
          ring.setAttribute('aria-hidden', 'true');
          doc.__linenRing = ring;
          const s = ring.style;
          const set = (key, value) => s.setProperty(key, value, 'important');
          set('all', 'initial');
          set('position', 'fixed');
          set('box-sizing', 'border-box');
          set('margin', '0');
          set('padding', '0');
          set('border', '2px solid #3478F6');
          set('box-shadow', '0 0 0 4px rgba(52, 120, 246, 0.25)');
          set('z-index', '2147483647');
          set('pointer-events', 'none');
          set('transition', 'opacity 0.2s');
          doc.documentElement.appendChild(ring);
          let changes, sizeChanges;
          const stop = () => {
            changes?.disconnect();
            sizeChanges?.disconnect();
            ring.remove();
          };
          const sync = () => {
            if (!el.isConnected || !ring.isConnected) { stop(); return; }
            const rect = el.getBoundingClientRect();
            set('left', (rect.left - 4) + 'px');
            set('top', (rect.top - 4) + 'px');
            set('width', (rect.width + 8) + 'px');
            set('height', (rect.height + 8) + 'px');
            const radius = parseFloat(view.getComputedStyle(el).borderTopLeftRadius) || 0;
            set('border-radius', (radius + 4) + 'px');
          };
          const track = () => {
            sync();
            if (ring.isConnected) view.requestAnimationFrame(track);
          };
          track();
          changes = new view.MutationObserver(records => {
            if (records.some(record => record.target !== ring)) sync();
          });
          changes.observe(doc.documentElement, { attributes: true, childList: true, subtree: true });
          if (view.ResizeObserver) {
            sizeChanges = new view.ResizeObserver(sync);
            sizeChanges.observe(el);
          }
          setTimeout(() => { set('opacity', '0'); setTimeout(stop, 250); }, ms);
        } catch (e) {}
      };

      const pressEnter = el => {
        const view = realm(el);
        const opts = { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true, cancelable: true, composed: true };
        let submitted = false;
        const mark = () => { submitted = true; };
        const form = el.form;
        form?.addEventListener('submit', mark, { capture: true });
        const accepted = el.dispatchEvent(new (view.KeyboardEvent)('keydown', opts));
        el.dispatchEvent(new (view.KeyboardEvent)('keyup', opts));
        form?.removeEventListener('submit', mark, { capture: true });
        if (accepted && !submitted && form?.isConnected) { try { form.requestSubmit(); } catch (e) {} }
      };

      const actionable = (el, checkEnabled = true) => {
        if (!el?.isConnected || !visible(el)) return 'The control is hidden or no longer available.';
        if (checkEnabled && disabled(el)) return 'The control is disabled.';
        el.scrollIntoView({ block: 'center', inline: 'nearest', behavior: 'instant' });
        const rect = el.getBoundingClientRect();
        const root = el.getRootNode();
        const view = realm(el);
        const left = Math.max(0, rect.left), right = Math.min(view.innerWidth, rect.right);
        const top = Math.max(0, rect.top), bottom = Math.min(view.innerHeight, rect.bottom);
        if (right <= left || bottom <= top) return 'The control is outside the viewport.';
        const hit = (root.elementFromPoint ? root : el.ownerDocument).elementFromPoint((left + right) / 2, (top + bottom) / 2);
        if (!hit || !(hit === el || el.contains(hit))) return 'The control is covered by another element.';
        const frame = el.ownerDocument.defaultView?.frameElement;
        return frame ? actionable(frame) : '';
      };

      const observe = (query, textLimit, controlLimit, textOffset, controlOffset, scope, viewportOnly) => {
        const all = collect();
        const text = pageText(viewportOnly);
        const terms = norm(query).toLowerCase().split(/\s+/).filter(Boolean);
        let start = Math.min(Math.max(0, textOffset), text.length);
        if (terms.length && !textOffset) {
          const lower = text.toLowerCase();
          const positions = terms.map(t => lower.indexOf(t)).filter(p => p >= 0);
          if (positions.length) start = Math.max(0, Math.min(...positions) - Math.min(60, Math.floor(textLimit / 10)));
        }
        if (start > 0 && /[\uDC00-\uDFFF]/.test(text[start] || '')) start++;
        let end = Math.min(text.length, start + textLimit);
        if (end < text.length && /[\uD800-\uDBFF]/.test(text[end - 1] || '')) end--;
        let root = null;
        if (scope) { try { root = document.querySelector(scope); } catch (e) {} }
        if (scope && !root) return { error: 'No element matches that scope.' };
        const candidates = all.filter(c => (!root || within(root, window.__linenRefs[c.r - 1])) && (!viewportOnly || c.vp));
        const availabilityOrder = (a, b) => Number(b.vp) - Number(a.vp) || Number(!!a.d) - Number(!!b.d);
        if (terms.length) candidates.sort((a, b) => {
          const score = c => terms.reduce((n, t) => n + (c.l.toLowerCase().includes(t) ? 10 : 0), 0);
          return score(b) - score(a) || availabilityOrder(a, b);
        });
        else candidates.sort(availabilityOrder);
        const controlQuery = JSON.stringify([norm(query).toLowerCase(), scope, viewportOnly]);
        let offset = Math.max(0, controlOffset), controlReset = '';
        if (offset > 0 && lastControlQuery !== null && lastControlQuery !== controlQuery) {
          offset = 0; controlReset = 'query_changed';
        } else if (offset > 0 && offset >= candidates.length) {
          offset = 0; controlReset = 'out_of_range';
        }
        lastControlQuery = controlQuery;
        return { text: text.slice(start, end), textTotal: text.length, textStart: start,
          controls: candidates.slice(offset, offset + controlLimit), controlTotal: candidates.length, controlStart: offset,
          controlReset,
          snapshot: window.__linenSnapshot, document: documentID, url: location.href };
      };

      return { matchesRef, expectValue, valueState, walk, documentID, norm, collect, pageText, viewportText, resolve, setValue, pressEnter,
        labelOf, kindOf, visible, highlight, isSensitiveField, disabled, actionable, observe };
    })());
    """#

}
