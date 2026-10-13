// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

nonisolated enum AutofillSaveScript {
    static let source = AutofillFormScript.source + clientSource
    static let clientSource = #"""
    (() => {
      if (globalThis.__linenAutofillSave || location.protocol !== 'https:') return;
      const channel = window.webkit?.messageHandlers?.linenAutofillSave;
      const forms = globalThis.__linenAutofillForms;
      const documentID = forms.documentID;
      let policy = {password:false,card:false,contact:false};
      const records = new Map(), observedRoots = new WeakSet(), reported = new Set();
      let timer = null, abandoned = false, submitIntent = null;
      const post = body => channel?.postMessage({...body,documentID,url:location.href});
      const diagnose = event => {
        if (reported.has(event)) return;
        reported.add(event); post({action:'diagnostic',event});
      };
      const discard = record => {
        if (record.attemptID) post({action:'discard',attemptID:record.attemptID,formID:record.id});
        record.attemptID = null; record.submitted = false; record.snapshot = null;
        records.delete(record.id);
      };
      const clear = () => {
        submitIntent = null;
        for (const record of records.values()) discard(record);
        if (timer !== null) clearInterval(timer);
        timer = null;
      };
      const collect = (fields, category) => {
        const values = {};
        for (const field of fields) {
          if (field.category !== category || !field.element.value.trim()) continue;
          const value = field.element.value.trim(), kind = field.kind;
          if (value.length > (kind === 'cc-number' ? 32 : 500)) return null;
          if (Object.hasOwn(values,kind) && values[kind] !== value) return null;
          values[kind] = value;
        }
        return values;
      };
      const snapshot = (group, edited) => {
        if (!group?.safe) return null;
        const changed = group.fields.filter(field => edited.has(field.element));
        if (!changed.length) return null;
        const result = {}, fields = group.fields;
        const passwords = group.passwords, users = group.usernames;
        if (policy.password && users.length <= 1 && passwords.length <= 3) {
          if (passwords.length && changed.some(field => ['current-password','new-password'].includes(field.kind))) {
            let fresh = passwords.filter(field => field.kind === 'new-password');
            if (!fresh.length && passwords.length === 3) fresh = passwords.slice(1);
            const candidates = fresh.length ? fresh : passwords;
            const value = candidates[0]?.element.value;
            if (value && value.length <= 4096 && candidates.every(field => field.element.value === value)) {
              const username = users[0]?.element.value || '';
              if (username.length <= 500) result.password = {username,password:value};
            }
          } else if (!passwords.length && users.length === 1 && changed.includes(users[0])) {
            const value = users[0].element.value;
            if (value && value.length <= 500) result.username = value;
          }
        }
        if (policy.card) {
          const editedCard = changed.find(field => field.category === 'card');
          const number = editedCard && fields.find(field => field.kind === 'cc-number' && field.section === editedCard.section);
          if (number) {
            const card = collect(fields.filter(field => field.section === number.section),'card');
            if (card) {
              const expiry = card['cc-exp'] || '';
              let match = expiry.match(/^(\d{4})-(\d{2})$/);
              if (match) { card['cc-exp-year'] = match[1]; card['cc-exp-month'] = match[2]; }
              else if ((match = expiry.match(/^(\d{1,2})\s*[\/\-]\s*(\d{2}|\d{4})$/)) ||
                       (match = expiry.match(/^(\d{2})(\d{2})$/))) {
                card['cc-exp-month'] = match[1]; card['cc-exp-year'] = match[2];
              }
              if (/^\d{2}$/.test(card['cc-exp-year'] || '')) card['cc-exp-year'] = '20' + card['cc-exp-year'];
              delete card['cc-exp'];
              if (card['cc-number'] && card['cc-exp-month'] && card['cc-exp-year']) result.card = card;
            }
          }
        }
        if (policy.contact && !passwords.length) {
          const editedContact = changed.find(field => field.category === 'contact');
          const address = editedContact && fields.find(field => ['street-address','address-line1'].includes(field.kind) &&
            field.section === editedContact.section);
          if (address) {
            const contact = collect(fields.filter(field => field.section === address.section),'contact');
            if (contact) result.contact = contact;
          }
        }
        return Object.keys(result).length ? result : null;
      };
      const update = (record, group) => {
        if (!group?.safe || group.id !== record.id) return;
        record.snapshot = snapshot(group,record.edited);
        record.fields = group.fields;
      };
      const stage = (record, source) => {
        if (!record.snapshot || performance.now() - record.editedAt > 120000 || abandoned) return;
        if (!record.attemptID) {
          record.attemptID = crypto.randomUUID();
          record.attemptAt = performance.now();
          record.submitted = source === 'submit';
          post({action:'stage',attemptID:record.attemptID,formID:record.id,source,...record.snapshot});
          diagnose('submitCaptured');
        } else if (source === 'submit' && !record.submitted) {
          record.submitted = true;
          post({action:'stage',attemptID:record.attemptID,formID:record.id,source,...record.snapshot});
        }
      };
      const check = () => {
        if (document.hidden || abandoned) return;
        for (const record of records.values()) {
          const now = performance.now();
          if (now - record.editedAt > 120000) { discard(record); continue; }
          if (!record.snapshot) continue;
          const relevant = record.fields.filter(field => record.snapshot.password ?
            ['current-password','new-password'].includes(field.kind) :
            record.snapshot.card ? field.category === 'card' :
            record.snapshot.contact ? field.category === 'contact' : field.kind === 'username');
          if (relevant.some(field => forms.present(field.element))) {
            if (record.snapshot.username && !record.snapshot.password && record.attemptID && forms.summary().passwords > 0) {
              post({action:'complete',attemptID:record.attemptID,formID:record.id,source:'username-step'});
              record.attemptID = null; record.submitted = false; record.snapshot = null; records.delete(record.id);
            } else record.absentAt = null;
            continue;
          }
          const state = forms.summary();
          const replaced = record.snapshot.password ? state.passwords > 0 || state.challenges > 0 :
            record.snapshot.card ? state.cards > 0 : record.snapshot.contact ? state.addresses > 0 : state.usernames > 0;
          if (replaced) { record.absentAt = null; continue; }
          if (!record.attemptID && now - record.editedAt > 10000) continue;
          record.absentAt ??= now;
          if (now - record.absentAt < 800) continue;
          stage(record,'automatic');
          if (record.attemptID) post({action:'complete',attemptID:record.attemptID,formID:record.id,source:'disappearance'});
          record.attemptID = null; record.submitted = false; record.snapshot = null; records.delete(record.id);
        }
        if (!records.size && timer !== null) { clearInterval(timer); timer = null; }
      };
      const noteEdit = event => {
        if (!event.isTrusted) return;
        observeRoots(event);
        const element = event.composedPath()[0], field = forms.field(element), group = forms.group(element);
        if (!field?.category || !group?.safe || !policy[field.category]) return;
        abandoned = false;
        if (field.category === 'password') diagnose('editRecorded');
        element.setAttribute('data-linen-' + (field.category === 'card' ? 'payment-card' : field.category),'');
        let record = records.get(group.id);
        if (!record) {
          if (records.size >= 12) discard(records.values().next().value);
          record = {id:group.id,root:group.root,edited:new Set(),fields:[],snapshot:null,attemptID:null,absentAt:null};
          records.set(group.id,record);
        } else if (record.attemptID) {
          post({action:'discard',attemptID:record.attemptID,formID:record.id});
          record.attemptID = null; record.submitted = false; record.absentAt = null;
        }
        record.editedAt = performance.now();
        if (record.edited.size < 100) record.edited.add(element);
        update(record,group);
        queueMicrotask(() => {
          if (records.get(record.id) === record && forms.rendered(element)) update(record,forms.group(element));
        });
        if (timer === null) timer = setInterval(check,400);
      };
      const attempt = (target, source) => {
        const group = forms.group(target);
        let record = group && records.get(group.id);
        if (!record && forms.isAction(target)) {
          for (const root of forms.ancestors(target)) {
            if (root === document.body || root === document.documentElement) break;
            const candidates = Array.from(records.values()).filter(value => forms.contains(root,value.root));
            if (candidates.length > 1) break;
            if (candidates.length === 1) { record = candidates[0]; break; }
          }
        }
        if (source === 'submit' && group?.safe &&
            submitIntent?.root === group.root && performance.now() - submitIntent.at < 1500) {
          const populated = group.fields.filter(field => field.category && policy[field.category] &&
            forms.rendered(field.element) && field.element.value.trim());
          if (populated.length) {
            abandoned = false;
            if (!record) {
              if (records.size >= 12) discard(records.values().next().value);
              record = {id:group.id,root:group.root,edited:new Set(),fields:group.fields,
                snapshot:null,attemptID:null,absentAt:null};
              records.set(group.id,record);
            }
            record.editedAt = performance.now();
            record.submitted = false;
            for (const field of populated) {
              record.edited.add(field.element);
              field.element.setAttribute('data-linen-' +
                (field.category === 'card' ? 'payment-card' : field.category),'');
            }
            if (timer === null) timer = setInterval(check,400);
          }
        }
        if (source === 'submit') submitIntent = null;
        if (!record || !forms.safe(record.root)) return;
        if (record.fields.some(field => field.element.willValidate && !field.element.validity.valid)) {
          diagnose('submitInvalid'); return;
        }
        const seed = record.fields.find(field => forms.rendered(field.element))?.element;
        if (seed) update(record,forms.group(seed));
        stage(record,source);
      };
      const submitted = event => {
        if (event.isTrusted) attempt(event.composedPath()[0],'submit');
      };
      const observeRoots = event => {
        for (const root of event.composedPath()) {
          if (!(root instanceof ShadowRoot) || observedRoots.has(root)) continue;
          observedRoots.add(root);
          root.addEventListener('submit',submitted,true);
          root.addEventListener('change',noteEdit,true);
        }
      };
      document.addEventListener('focusin',observeRoots,true);
      document.addEventListener('input',noteEdit,true);
      document.addEventListener('change',noteEdit,true);
      document.addEventListener('submit',submitted,true);
      document.addEventListener('reset',event => {
        const record = records.get(forms.group(event.composedPath()[0])?.id);
        if (record) discard(record);
      },true);
      document.addEventListener('keydown',event => {
        if (!event.isTrusted || event.key !== 'Enter' || event.isComposing || event.repeat) return;
        const element = event.composedPath()[0];
        if (element instanceof HTMLInputElement && forms.field(element)?.category) {
          submitIntent = {root:forms.scope(element),at:performance.now()};
          attempt(element,'interaction');
        }
      },true);
      document.addEventListener('click',event => {
        if (!event.isTrusted) return;
        const path = event.composedPath();
        if (path.some(el => el instanceof HTMLAnchorElement && el.href)) {
          abandoned = true; clear(); return;
        }
        const action = path.find(forms.isAction);
        if (action) {
          submitIntent = (action instanceof HTMLButtonElement && action.type === 'submit' ||
            action instanceof HTMLInputElement && ['submit','image'].includes(action.type)) ?
            {root:forms.scope(action),at:performance.now()} : null;
          attempt(action,'interaction');
        }
      },true);
      window.addEventListener('pagehide',() => {
        if (!abandoned) for (const record of records.values()) stage(record,'pagehide');
        records.clear();
        if (timer !== null) clearInterval(timer);
        timer = null;
      });
      window.addEventListener('pageshow',event => {
        if (event.persisted) { clear(); abandoned = false; ready(); }
      });
      forms.subscribe(check);
      const ready = () => post({action:'ready'});
      globalThis.__linenAutofillSave = {
        check,
        setPolicy(value) {
          const next = {password:value?.password === true,card:value?.card === true,contact:value?.contact === true};
          if (Object.keys(next).some(key => next[key] !== policy[key])) clear();
          policy = next;
        }
      };
      ready();
      document.addEventListener('DOMContentLoaded',ready,{once:true});
    })();
    """#
}
