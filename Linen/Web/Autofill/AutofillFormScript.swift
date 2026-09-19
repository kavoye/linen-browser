// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import WebKit

enum AutofillPage {
    static let world = WKContentWorld.world(name: "LinenAutofill")
    private static let controllers = NSHashTable<WKUserContentController>.weakObjects()

    static func install(in controller: WKUserContentController) {
        guard !controllers.contains(controller) else { return }
        controllers.add(controller)
        controller.addUserScript(WKUserScript(source: AutofillFormScript.source + AutofillSuggestionScript.source,
                                             injectionTime: .atDocumentStart, forMainFrameOnly: false, in: world))
    }
}

nonisolated enum AutofillFormScript {
    static let source = #"""
    (() => {
      if (globalThis.__linenAutofillForms) return;
      const documentID = crypto.randomUUID();
      const identities = new WeakMap();
      const secretFields = new WeakSet();
      let nextID = 0, scopes = new WeakMap(), groups = new WeakMap(), types = new WeakMap(), scopeReady = false;
      const listeners = new Set(), roots = new WeakSet();
      const observers = [];
      let notification = null;
      const id = element => {
        if (!identities.has(element)) identities.set(element, String(++nextID));
        return identities.get(element);
      };
      const parent = el => el?.assignedSlot || el?.parentElement || el?.getRootNode()?.host || null;
      const ancestors = function* (el) {
        for (let count = 0; el instanceof Element && count < 100; count++, el = parent(el)) yield el;
      };
      const contains = (root, el) => root === el || Array.from(ancestors(el)).includes(root);
      const invalidate = () => {
        scopes = new WeakMap(); groups = new WeakMap(); types = new WeakMap(); scopeReady = false;
        if (notification !== null) return;
        notification = setTimeout(() => {
          notification = null;
          for (const listener of listeners) listener();
        }, 80);
      };
      const observe = root => {
        if (roots.has(root)) return;
        roots.add(root);
        const observer = new MutationObserver(invalidate);
        observer.observe(root, {subtree:true,childList:true,attributes:true,characterData:true,
          attributeFilter:['type','name','id','autocomplete','form','role','disabled','readonly','hidden',
            'inert','style','class','placeholder','aria-label','aria-labelledby','aria-invalid','for','slot']});
        observers.push(observer);
      };
      const elements = root => {
        if (!root) return [];
        const found = new Set(), pending = [root], seen = new WeakSet();
        let visited = 0;
        if (root instanceof HTMLFormElement) {
          for (const el of Array.from(root.elements).slice(0, 400)) found.add(el);
        }
        while (pending.length && visited++ < 6000 && found.size < 400) {
          const node = pending.pop();
          if (seen.has(node)) continue;
          seen.add(node);
          if (node instanceof Element) {
            if (node.matches('input,select,textarea,button,[role="button"]')) found.add(node);
            if (node.shadowRoot) { observe(node.shadowRoot); pending.push(node.shadowRoot); }
            if (node instanceof HTMLSlotElement) pending.push(...node.assignedElements());
          }
          pending.push(...Array.from(node.children || []).reverse());
        }
        return Array.from(found);
      };
      const metadata = (el, name) => el.getAttribute(name) || el.getRootNode()?.host?.getAttribute(name) || '';
      const tokens = el => metadata(el,'autocomplete').toLowerCase().trim().split(/\s+/).filter(Boolean);
      const section = el => tokens(el).filter(t => t.startsWith('section-') || t === 'shipping' || t === 'billing').join(' ');
      const hint = el => {
        const host = el.getRootNode()?.host;
        const labelled = (el.getAttribute('aria-labelledby') || '').split(/\s+/).slice(0, 8)
          .map(value => el.getRootNode().getElementById?.(value)?.textContent?.slice(0, 500) || '');
        return [el.name,el.id,el.placeholder,el.getAttribute('aria-label'),...labelled,
          ...['name','id','placeholder','aria-label','label'].map(name => host?.getAttribute(name) || ''),
          ...Array.from(el.labels || [], label => label.textContent?.slice(0, 500))]
          .join(' ').replace(/([a-z])([A-Z])/g,'$1 $2').toLowerCase().replace(/[_-]/g,' ').slice(0, 4000);
      };
      const present = el => {
        if (!(el instanceof HTMLInputElement || el instanceof HTMLSelectElement || el instanceof HTMLTextAreaElement) ||
            !el.isConnected || el.type === 'hidden') return false;
        const rect = el.getBoundingClientRect();
        if (rect.width < 2 || rect.height < 2) return false;
        for (const node of ancestors(el)) {
          if (node.hasAttribute('hidden')) return false;
          const css = getComputedStyle(node);
          if (css.display === 'none' || css.visibility !== 'visible' || Number(css.opacity) === 0) return false;
        }
        return true;
      };
      const rendered = el => present(el) && !el.disabled && !el.readOnly && !el.matches(':disabled') &&
        !Array.from(ancestors(el)).some(node => node.hasAttribute('inert') || node.hasAttribute('disabled'));
      const visible = el => {
        if (!rendered(el)) return false;
        const rect = el.getBoundingClientRect();
        return rect.bottom > 0 && rect.right > 0 && rect.top < innerHeight && rect.left < innerWidth;
      };
      const contactKinds = new Set(['name','given-name','family-name','organization','email','tel',
        'street-address','address-line1','address-line2','address-line3','address-level1','address-level2',
        'postal-code','country','country-name']);
      const cardKinds = new Set(['cc-number','cc-name','cc-given-name','cc-family-name','cc-exp','cc-exp-month','cc-exp-year','cc-csc']);
      const passwordKinds = new Set(['username','current-password','new-password']);
      const classifyField = el => {
        if (!(el instanceof HTMLInputElement || el instanceof HTMLSelectElement || el instanceof HTMLTextAreaElement)) return null;
        const declared = tokens(el), words = hint(el);
        if (declared.includes('one-time-code') || /\b(otp|one time code|verification code|authenticator code)\b/.test(words)) return 'one-time-code';
        if (declared.includes('cc-csc') || /\b(cvv|cvc|csc|cid|card security code|card verification)\b/.test(words)) return 'cc-csc';
        if (/\bsecurity code\b/.test(words)) return null;
        const exact = declared.find(t => passwordKinds.has(t) || contactKinds.has(t) || cardKinds.has(t));
        if (passwordKinds.has(exact) && !(el instanceof HTMLInputElement)) return null;
        if (exact === 'username' && el.type === 'hidden') return exact;
        if (el instanceof HTMLInputElement && (el.type === 'password' || secretFields.has(el) && el.type === 'text')) {
          secretFields.add(el);
          return exact === 'new-password' ? exact : 'current-password';
        }
        if (el instanceof HTMLInputElement && !['text','email','tel','number','month'].includes(el.type)) return null;
        if (exact) return exact;
        if (declared.some(t => !/^(section-|shipping$|billing$|home$|work$|mobile$|on$|off$|webauthn$)/.test(t))) return null;
        if (/\b(search|coupon|promo|captcha)\b/.test(words)) return null;
        if (/\b(card\s*(number|no)|cc\s*(number|num)|cardnumber|ccnumber)\b/.test(words)) return 'cc-number';
        if (/\b(cardholder|card holder|name on card|cc name)\b/.test(words)) return 'cc-name';
        if (/\bmm\s*\/\s*yy(?:yy)?\b/.test(words)) return 'cc-exp';
        if (/\b(expiry|expiration|exp)\s*(month|mm)\b/.test(words)) return 'cc-exp-month';
        if (/\b(expiry|expiration|exp)\s*(year|yy|yyyy)\b/.test(words)) return 'cc-exp-year';
        if (/\b(expiry|expiration|exp date|cc exp|mm\s*\/\s*yy(?:yy)?)\b/.test(words)) return 'cc-exp';
        if (/\b(card|cc|security)\b/.test(words)) return null;
        if (/\b(user\s*name|username|login|account name|account id)\b/.test(words)) return 'username';
        if (/\b(first name|given name|firstname|givenname)\b/.test(words)) return 'given-name';
        if (/\b(last name|family name|surname|lastname)\b/.test(words)) return 'family-name';
        if (/\b(full name|fullname)\b/.test(words)) return 'name';
        if (el.type === 'email' || /\b(e mail|email)\b/.test(words)) return 'email';
        if (el.type === 'tel' || /\b(phone|telephone|mobile)\b/.test(words)) return 'tel';
        if (/\b(zip|postal code|postcode)\b/.test(words)) return 'postal-code';
        if (/\b(address line 3|address3)\b/.test(words)) return 'address-line3';
        if (/\b(address line 2|address2|apartment|suite)\b/.test(words)) return 'address-line2';
        if (/\b(street|address line 1|address1)\b/.test(words)) return 'address-line1';
        if (/\b(city|town)\b/.test(words)) return 'address-level2';
        if (/\b(state|province|region)\b/.test(words)) return 'address-level1';
        if (/\bcountry\b/.test(words)) return 'country';
        if (/\b(company|organization)\b/.test(words)) return 'organization';
        return null;
      };
      const classify = el => {
        if (!types.has(el)) types.set(el,classifyField(el));
        return types.get(el);
      };
      const isAction = el => el instanceof Element && el.matches('button,input[type="submit"],input[type="image"],[role="button"]') &&
        !el.disabled && el.type !== 'reset' && !el.hasAttribute('aria-pressed') && !el.hasAttribute('aria-expanded');
      const nativeScope = el => {
        if (el?.form instanceof HTMLFormElement) return el.form;
        for (const node of ancestors(el)) {
          if (node instanceof HTMLFormElement) return node;
          const formID = node.getAttribute('form');
          const associated = formID && node.getRootNode().getElementById?.(formID);
          if (associated instanceof HTMLFormElement) return associated;
        }
        return null;
      };
      const candidateRoot = el => {
        let fallback = null, result = null, depth = 0;
        for (const node of ancestors(el)) {
          if (node === document.body || node === document.documentElement || depth++ >= 16) break;
          const controls = elements(node);
          if (controls.some(control => nativeScope(control))) break;
          const inputs = controls.filter(present);
          if (inputs.length > 40) break;
          if (!inputs.length) continue;
          if (node.getAttribute('role') === 'form' || node instanceof HTMLFieldSetElement || node.localName.endsWith('-form')) {
            result = node; break;
          }
          const actions = controls.filter(isAction);
          if (actions.some(control => ['submit','image'].includes(control.type))) { result = node; break; }
          if (!fallback && actions.length) fallback = node;
          if (inputs.length >= 2) {
            const kinds = inputs.map(classify);
            const related = kinds.some(k => passwordKinds.has(k)) || kinds.filter(k => cardKinds.has(k)).length >= 2 ||
              kinds.filter(k => contactKinds.has(k)).length >= 2;
            if (related) { result = node; break; }
          }
        }
        return result || fallback || el;
      };
      const discoverScopes = () => {
        if (scopeReady) return;
        scopeReady = true;
        const unowned = new Map();
        for (const element of elements(document).filter(present)) {
          const native = nativeScope(element);
          if (native) scopes.set(element,native);
          else unowned.set(element,candidateRoot(element));
        }
        const candidates = new Set(unowned.values());
        for (const [element, candidate] of unowned) {
          let root = candidate;
          for (const ancestor of ancestors(candidate)) if (candidates.has(ancestor)) root = ancestor;
          scopes.set(element,root);
        }
      };
      const scope = el => {
        if (!(el instanceof Element)) return null;
        const native = nativeScope(el);
        if (native) return native;
        discoverScopes();
        if (scopes.has(el)) return scopes.get(el);
        for (const node of ancestors(el)) {
          const member = elements(node).find(control => scopes.get(control) === node);
          if (member) return node;
          if (node === document.body || node === document.documentElement) break;
        }
        return el;
      };
      const safe = root => {
        if (!root) return false;
        const action = root instanceof HTMLFormElement ? root.action : root.getAttribute('action');
        try { return new URL(action || location.href, location.href).origin === location.origin; } catch { return false; }
      };
      const group = target => {
        const root = scope(target);
        if (!root) return null;
        if (groups.has(root)) return groups.get(root);
        const usernameMetadata = el => el instanceof HTMLInputElement && el.type === 'hidden' &&
          tokens(el).includes('username') && nativeScope(el) === root;
        const fields = elements(root).filter(el => (present(el) || usernameMetadata(el)) && scope(el) === root).map(element => ({
          element,id:id(element),kind:classify(element),section:section(element),tokens:tokens(element)
        }));
        const passwords = fields.filter(field => ['current-password','new-password'].includes(field.kind));
        let usernames = fields.filter(field => field.kind === 'username');
        if (!usernames.length && passwords.length) {
          const accounts = fields.filter(field => field.kind === 'email');
          if (accounts.length === 1) usernames = accounts;
          else if (!accounts.length) {
            const firstPassword = fields.indexOf(passwords[0]);
            const preceding = fields.slice(0,firstPassword).filter(field => !field.kind &&
              field.element instanceof HTMLInputElement && field.element.type === 'text' &&
              field.tokens.every(token => token === 'on' || token === 'off') &&
              !/\b(cvv|cvc|csc|card|security|verification|otp|coupon|promo|search|captcha)\b/.test(hint(field.element)));
            if (preceding.length === 1) usernames = preceding;
          }
        }
        for (const field of usernames) field.kind = 'username';
        const off = (root.getAttribute('autocomplete') || '').toLowerCase() === 'off';
        for (const field of fields) {
          field.category = passwordKinds.has(field.kind) ? 'password' :
            off || field.tokens.includes('off') ? null : cardKinds.has(field.kind) ? 'card' : contactKinds.has(field.kind) ? 'contact' : null;
        }
        const result = {id:id(root),root,fields,passwords,usernames,safe:safe(root)};
        groups.set(root,result);
        return result;
      };
      const field = el => group(el)?.fields.find(field => field.element === el) || null;
      const summary = () => {
        const controls = elements(document).filter(present);
        return {documentID,url:location.href,ready:document.readyState === 'complete',
          passwords:controls.filter(el => ['current-password','new-password'].includes(classify(el))).length,
          challenges:controls.filter(el => classify(el) === 'one-time-code').length,
          usernames:controls.filter(el => classify(el) === 'username').length,
          cards:controls.filter(el => cardKinds.has(classify(el))).length,
          addresses:controls.filter(el => ['street-address','address-line1'].includes(classify(el))).length};
      };
      const refresh = event => {
        for (const root of event.composedPath()) if (root instanceof ShadowRoot) observe(root);
        scopes = new WeakMap(); groups = new WeakMap(); types = new WeakMap(); scopeReady = false;
      };
      document.addEventListener('focusin',refresh,true);
      document.addEventListener('input',refresh,true);
      document.addEventListener('change',refresh,true);
      document.addEventListener('slotchange',invalidate,true);
      window.addEventListener('pageshow',invalidate);
      window.addEventListener('resize',invalidate);
      observe(document);
      globalThis.__linenAutofillForms = {documentID,id,parent,ancestors,contains,elements,metadata,tokens,section,hint,
        present,rendered,visible,scope,safe,group,field,summary,isAction,contactKinds,cardKinds,passwordKinds,invalidate,
        subscribe(listener) { listeners.add(listener); return () => listeners.delete(listener); }};
    })();
    """#
}
