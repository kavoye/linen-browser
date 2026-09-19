// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

nonisolated enum PaymentCardScript {
    static let source = AutofillFormScript.source + AutofillSuggestionScript.source + clientSource
    static let clientSource = #"""
    (() => {
      if (globalThis.__linenCardAutofill) return;
      const channel = window.webkit?.messageHandlers?.linenCardAutofill;
      const state = { target: null, token: null, url: null };
      const forms = globalThis.__linenAutofillForms;
      const suggestions = globalThis.__linenAutofillSuggestions;
      const kind = element => {
        const field = forms.field(element);
        return field?.category === 'card' ? field.kind : null;
      };
      const visible = forms.visible;
      const section = forms.section;
      suggestions.track(channel, state, target => !!kind(target) && visible(target) && forms.group(target)?.safe);
      const eligible = (token, url) => suggestions.valid(state,token,url) && !!kind(state.target) && visible(state.target) && forms.group(state.target)?.safe;

      const valueFor = (element, card) => {
        const field = kind(element);
        const month = card.month ? String(card.month).padStart(2, '0') : '';
        const year = card.year ? String(card.year) : '';
        const shortYear = year.slice(-2);
        switch (field) {
          case 'cc-number': return card.number;
          case 'cc-csc': return card.securityCode || '';
          case 'cc-name': return card.cardholder;
          case 'cc-given-name': case 'cc-family-name': return '';
          case 'cc-exp-month': return month;
          case 'cc-exp-year':
            return element.maxLength === 2 || /^\s*yy\s*$/i.test(element.placeholder || '') ? shortYear : year;
          case 'cc-exp':
            if (!month || !year) return '';
            if (element.type === 'month') return `${year}-${month}`;
            if (element.maxLength === 4) return `${month}${shortYear}`;
            return `${month}/${/yyyy/i.test(element.placeholder || '') || element.maxLength === 7 ? year : shortYear}`;
          default: return '';
        }
      };
      const setValue = (element, value) => {
        if (!value) return false;
        element.setAttribute('data-linen-payment-card', '');
        if (element instanceof HTMLSelectElement) {
          const field = kind(element);
          const option = Array.from(element.options).find(option => {
            if (option.disabled || option.value === '') return false;
            if (option.value === value || option.textContent.trim() === value) return true;
            const numeric = Number(option.value);
            if (Number.isFinite(numeric) && numeric === Number(value)) return true;
            return field === 'cc-exp-year' && /^\d{2}$/.test(option.value) && option.value === value.slice(-2);
          });
          if (!option) return false;
          Object.getOwnPropertyDescriptor(HTMLSelectElement.prototype, 'value').set.call(element, option.value);
        } else {
          if (element.maxLength > 0 && value.length > element.maxLength) return false;
          Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(element, value);
        }
        element.dispatchEvent(new Event('input', { bubbles: true, composed: true }));
        element.dispatchEvent(new Event('change', { bubbles: true }));
        return true;
      };
      globalThis.__linenCardAutofill = {
        eligible,
        bounds(token,url) { return eligible(token,url) ? suggestions.geometry(state.target) : null; },
        fill(token, url, card) {
          if (!eligible(token, url)) return 0;
          const target = state.target;
          const group = forms.group(target);
          const candidates = group.fields.map(field => field.element);
          state.token = null;
          let filled = 0;
          for (const element of candidates) {
            if (location.href !== url || !target.isConnected || !forms.safe(group.root)) break;
            if (forms.scope(target) !== group.root || forms.scope(element) !== group.root || section(element) !== section(target) || !forms.rendered(element)) continue;
            if (setValue(element, valueFor(element, card))) filled++;
          }
          state.target = null;
          return filled;
        }
      };
    })();
    """#
}
