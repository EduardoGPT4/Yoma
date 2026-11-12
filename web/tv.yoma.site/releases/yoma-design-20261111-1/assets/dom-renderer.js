'use strict';
// Small keyed reconciler for page components; live video dialogs have their own lifecycle.
const SeasonUI = (() => {
  const dirty = new WeakSet();
  document.addEventListener('input', event => {if(event.target.form)dirty.add(event.target);});
  document.addEventListener('change', event => {if(event.target.form)dirty.add(event.target);});
  document.addEventListener('season-form-saved', event => {
    for (const control of event.detail?.elements || []) dirty.delete(control);
  });
  const key = node => node.nodeType === 1
    ? node.id || node.getAttribute('data-ui-key') || '' : '';
  function patch(current, fresh) {
    if (current.nodeType !== fresh.nodeType || current.nodeName !== fresh.nodeName ||
        (key(current) && key(current) !== key(fresh))) {
      current.replaceWith(fresh); return fresh;
    }
    if (current.nodeType !== 1) {
      if (current.nodeValue !== fresh.nodeValue) current.nodeValue = fresh.nodeValue;
      return current;
    }
    // Preserve an active/edited control, its selection and its server-independent draft.
    if (['INPUT', 'TEXTAREA', 'SELECT'].includes(current.nodeName) &&
        (current === document.activeElement || dirty.has(current))) return current;
    for (const attr of [...current.attributes]) if (!fresh.hasAttribute(attr.name)) current.removeAttribute(attr.name);
    for (const attr of fresh.attributes) if (current.getAttribute(attr.name) !== attr.value) current.setAttribute(attr.name, attr.value);
    if (current.nodeName === 'IFRAME' || current.nodeName === 'VIDEO') return current;
    const value=fresh.value, checked=fresh.checked;
    children(current, fresh);
    if (['INPUT','TEXTAREA','SELECT'].includes(current.nodeName)) {
      current.value = value;
      if ('checked' in current) current.checked = checked;
    }
    return current;
  }
  function children(current, fresh) {
    const available = new Map([...current.childNodes].filter(key).map(node => [key(node), node]));
    let cursor = current.firstChild;
    for (const next of [...fresh.childNodes]) {
      const id = key(next);
      let match = id ? available.get(id) : cursor && !key(cursor) ? cursor : null;
      if (match) {
        if (match !== cursor) current.insertBefore(match, cursor);
        match = patch(match, next);
      } else { match = next; current.insertBefore(match, cursor); }
      cursor = match.nextSibling;
    }
    while (cursor) { const next = cursor.nextSibling; cursor.remove(); cursor = next; }
  }
  function renderInto(target, html, scope) {
    if (target.dataset.renderScope !== scope) {
      target.innerHTML = html; target.dataset.renderScope = scope; return;
    }
    const template = document.createElement('template'); template.innerHTML = html;
    children(target, template.content);
  }
  return { renderInto };
})();
