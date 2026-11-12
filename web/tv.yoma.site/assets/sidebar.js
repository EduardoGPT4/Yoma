'use strict';

const sidebarNavigation = (() => {
  const root = document.documentElement;
  const sidebar = document.getElementById('sidebar');
  const toggle = document.getElementById('sidebar-toggle');
  const backdrop = document.getElementById('sidebar-backdrop');
  const mobile = matchMedia('(max-width: 680px)');
  let returnFocus=null;
  const workspace=document.querySelector('.workspace');
  let collapsed = root.dataset.sidebarCollapsed === 'true';

  function update() {
    const visible = mobile.matches
      ? sidebar.classList.contains('open')
      : !collapsed;
    if (!visible && sidebar.contains(document.activeElement)) toggle.focus();
    sidebar.inert = !visible;
    sidebar.setAttribute('aria-hidden', String(!visible));
    toggle.setAttribute('aria-expanded', String(visible));
    const label = visible ? 'Ocultar barra lateral' : 'Mostrar barra lateral';
    toggle.setAttribute('aria-label', label);
    toggle.title = label;
    toggle.querySelector('use').setAttribute(
      'href',
      mobile.matches ? '#i-menu' : visible ? '#i-sidebar-hide' : '#i-sidebar-show'
    );
    backdrop.hidden = !mobile.matches || !visible;
    if(workspace)workspace.inert=mobile.matches&&visible;
    if(mobile.matches&&visible){sidebar.setAttribute('role','dialog');sidebar.setAttribute('aria-modal','true');sidebar.setAttribute('aria-label','Navegación principal');}
    else{sidebar.removeAttribute('role');sidebar.removeAttribute('aria-modal');}
  }

  function closeMobile() {
    const was=sidebar.classList.contains('open');sidebar.classList.remove('open');
    update();if(was&&mobile.matches)(returnFocus?.isConnected?returnFocus:toggle).focus();
  }

  function toggleSidebar() {
    if (mobile.matches) {const opening=!sidebar.classList.contains('open');if(opening)returnFocus=document.activeElement;sidebar.classList.toggle('open');update();if(opening)sidebar.querySelector('button,a')?.focus();else(returnFocus?.isConnected?returnFocus:toggle).focus();}
    else {
      collapsed = !collapsed;
      root.dataset.sidebarCollapsed = String(collapsed);
      try {
        localStorage.setItem('seasonav1.sidebarCollapsed', String(collapsed));
      } catch {}
    }
    update();
  }

  mobile.addEventListener('change', closeMobile);
  document.addEventListener('keydown', (event) => {
    if(event.key==='Tab'&&mobile.matches&&sidebar.classList.contains('open')){
      const items=[...sidebar.querySelectorAll('button:not(:disabled),a[href]')].filter(t=>!t.hidden&&t.getClientRects().length);
      if(items.length&&(event.shiftKey?document.activeElement===items[0]:document.activeElement===items.at(-1))){event.preventDefault();(event.shiftKey?items.at(-1):items[0]).focus();}
    }
    if (
      event.key === 'Escape' &&
      mobile.matches &&
      sidebar.classList.contains('open') &&
      !document.querySelector('dialog[open]')
    ) closeMobile();
  });
  update();
  return { toggle: toggleSidebar, closeMobile };
})();
