// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

nonisolated enum ContactAutofillScript {
    static let source = AutofillFormScript.source + AutofillSuggestionScript.source + clientSource
    static let clientSource = #"""
    (() => {
      if (globalThis.__linenContactAutofill) return;
      const channel = window.webkit?.messageHandlers?.linenContactAutofill;
      const state = { target: null, token: null, url: null };
      const forms = globalThis.__linenAutofillForms;
      const suggestions = globalThis.__linenAutofillSuggestions;
      const kind = element => {
        const field = forms.field(element);
        return field?.category === 'contact' ? field.kind : null;
      };
      const visible = forms.visible;
      const section = forms.section;
      suggestions.track(channel, state, target => !!kind(target) && visible(target) && forms.group(target)?.safe);
      const eligible = (token, url) => suggestions.valid(state,token,url) && !!kind(state.target) && visible(state.target) && forms.group(state.target)?.safe;

      const valueFor = (element, contact) => contact[kind(element)] || '';
      const setValue = (element, value, contact) => {
        if (!value) return false;
        element.setAttribute('data-linen-contact', '');
        if (element instanceof HTMLSelectElement) {
          const normalize = value => value.trim().toLocaleLowerCase();
          const alternatives = [value];
          if (['country', 'country-name'].includes(kind(element))) {
            alternatives.push(contact.country || '', contact['country-name'] || '');
          }
          const option = Array.from(element.options).find(option => !option.disabled && option.value !== '' &&
            alternatives.some(candidate => candidate && [option.value, option.textContent].some(text =>
              normalize(text) === normalize(candidate))));
          if (!option) return false;
          Object.getOwnPropertyDescriptor(HTMLSelectElement.prototype, 'value').set.call(element, option.value);
        } else {
          if (element.maxLength > 0 && value.length > element.maxLength) return false;
          const prototype = element instanceof HTMLTextAreaElement ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
          Object.getOwnPropertyDescriptor(prototype, 'value').set.call(element, value);
        }
        element.dispatchEvent(new Event('input', { bubbles: true, composed: true }));
        element.dispatchEvent(new Event('change', { bubbles: true }));
        return true;
      };
      globalThis.__linenContactAutofill = {
        eligible,
        bounds(token,url) { return eligible(token,url) ? suggestions.geometry(state.target) : null; },
        fill(token, url, contact) {
          if (!eligible(token, url)) return 0;
          const target = state.target;
          const group = forms.group(target);
          const candidates = group.fields.map(field => field.element);
          state.token = null;
          let filled = 0;
          for (const element of candidates) {
            if (location.href !== url || !target.isConnected || !forms.safe(group.root)) break;
            if (forms.scope(target) !== group.root || forms.scope(element) !== group.root || section(element) !== section(target) || !forms.rendered(element)) continue;
            if (element !== target && element.value.trim() && !(element instanceof HTMLSelectElement)) continue;
            if (setValue(element, valueFor(element, contact), contact)) filled++;
          }
          state.target = null;
          return filled;
        }
      };
    })();
    """#
}
