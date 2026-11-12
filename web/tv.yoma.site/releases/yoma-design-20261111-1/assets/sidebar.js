'use strict';
// Preserve the navigation API used by routes; the old sidebar is now a menu.
const sidebarNavigation = (() => {
  const menu = document.getElementById('sidebar');
  const toggle = document.getElementById('sidebar-toggle');
  const backdrop = document.getElementById('sidebar-backdrop');
  let returnFocus = null;
  function closeMobile() {
    if (menu.hidden) return;
    menu.hidden = backdrop.hidden = true;
    toggle.setAttribute('aria-expanded', 'false');
    document.documentElement.classList.remove('navigation-open');
    if (menu.contains(document.activeElement))
      (returnFocus?.isConnected ? returnFocus : toggle).focus();
  }
  function toggleMenu() {
    if (!menu.hidden) return closeMobile();
    returnFocus = document.activeElement;
    menu.hidden = backdrop.hidden = false;
    toggle.setAttribute('aria-expanded', 'true');
    document.documentElement.classList.add('navigation-open');
    menu.querySelector('button,a')?.focus();
  }
  document.addEventListener('click', event => {
    if (menu.contains(event.target) && event.target.closest('button,a') && !event.target.closest('[data-action="menu"]')) closeMobile();
  }, true);
  document.addEventListener('keydown', event => {
    if (menu.hidden) return;
    if (event.key === 'Escape') { event.preventDefault(); closeMobile(); }
    if (event.key !== 'Tab') return;
    const items = [...menu.querySelectorAll('button:not(:disabled),a[href]')]
      .filter(node => !node.hidden && node.getClientRects().length);
    if (!items.length) return;
    if (event.shiftKey ? document.activeElement === items[0] : document.activeElement === items.at(-1)) {
      event.preventDefault();
      (event.shiftKey ? items.at(-1) : items[0]).focus();
    }
  });
  document.addEventListener('focusin',event=>{
    if(!menu.hidden && !menu.contains(event.target)) menu.querySelector('button,a')?.focus();
  });
  return { toggle: toggleMenu, closeMobile };
})();
