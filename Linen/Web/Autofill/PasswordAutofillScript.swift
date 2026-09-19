// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

nonisolated enum PasswordAutofillScript {
    static let source = AutofillFormScript.source + AutofillSuggestionScript.source + clientSource
    static let clientSource = #"""
    (() => {
      if (globalThis.__linenPasswords) return;
      const channel = window.webkit?.messageHandlers?.linenPasswords;
      const state = {target:null, token:null, url:null};
      const forms = globalThis.__linenAutofillForms;
      let enabled = false;
      const visible = forms.visible;
      const tokens = forms.tokens;
      const fields = target => {
        if (!visible(target)) return null;
        const group = forms.group(target);
        if (!group?.safe || group.passwords.length > 3 || group.usernames.length > 1 ||
            forms.field(target)?.category !== 'password') return null;
        const current = group.passwords.filter(field => field.kind === 'current-password');
        if (current.length > 1 || (!current.length && group.passwords.length)) return null;
        if (group.passwords.length > 1 && !current[0]?.tokens.includes('current-password')) return null;
        if (forms.field(target)?.kind === 'new-password') return null;
        return {form:group.root,passwords:current.map(field => field.element),username:group.usernames[0]?.element};
      };
      const suggestions = globalThis.__linenAutofillSuggestions;
      const tracker = suggestions.track(channel, state, target => {
        return enabled && !!fields(target);
      });
      const eligible = (token,url) => enabled && suggestions.valid(state,token,url) && !!fields(state.target);
      globalThis.__linenPasswords = {
        setEnabled(value) {
          const changed = enabled !== (value === true);
          enabled = value === true;
          if (!enabled) tracker.clear();
          else if (changed) tracker.refresh();
        },
        eligible,
        bounds(token,url) { return eligible(token,url) ? suggestions.geometry(state.target) : null; },
        fill(token,url,login) {
          if (!eligible(token,url)) return 0;
          const target = state.target;
          const found = fields(target);
          if (found.username && !forms.rendered(found.username) && found.username.value && found.username.value !== login.username) return 0;
          if (found.passwords.length > 1 || found.passwords.some(el => tokens(el).includes('new-password'))) return 0;
          state.token = null;
          const set = (el,value) => {
            if (!el || !forms.rendered(el) || location.href !== url || !target.isConnected) return 0;
            el.setAttribute('data-linen-password','');
            Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').set.call(el,value);
            el.dispatchEvent(new Event('input',{bubbles:true,composed:true}));
            el.dispatchEvent(new Event('change',{bubbles:true}));
            return 1;
          };
          let count = 0;
          if (found.username) count += set(found.username,login.username);
          if (!found.passwords.length || !forms.safe(found.form) || forms.scope(found.passwords[0]) !== found.form) return count;
          count += set(found.passwords[0],login.password);
          return count;
        }
      };
      const ready = () => channel?.postMessage({action:'ready',documentID:forms.documentID});
      ready();
      window.addEventListener('pageshow',ready);
    })();
    """#
}
