'use strict';
(() => {
  const bell=document.getElementById('notifications-toggle');
  const panel=document.getElementById('notification-panel');
  if(!bell||!panel)return;
  const content=panel.querySelector('[data-notice-content]');
  const readButton=panel.querySelector('[data-notice-action="read"]');
  let owner=0,sequence=0,rows=null,upTo=0,loadedKey='',loading=false,reading=false,error='';
  const userId=()=>Number(state?.user?.id)||0;
  const key=()=>`${userId()}:${featureHome?.notifications_revision||0}:${featureHome?.notifications||0}`;
  function position(){
    if(panel.hidden)return;
    const anchor=bell.getBoundingClientRect(),width=Math.min(420,window.innerWidth-24);
    panel.style.width=`${width}px`;
    panel.style.left=`${Math.max(12,Math.min(window.innerWidth-width-12,anchor.right-width))}px`;
    panel.style.top=`${Math.max(12,anchor.bottom+10)}px`;
    panel.style.maxHeight=`${Math.max(80,Math.min(600,window.innerHeight-anchor.bottom-22))}px`;
  }
  function close(restoreFocus=false){
    if(panel.hidden)return;
    panel.hidden=true;bell.setAttribute('aria-expanded','false');
    if(restoreFocus)bell.focus({preventScroll:true});
  }
  function reset(){
    sequence++;owner=userId();rows=null;upTo=0;loadedKey='';loading=false;reading=false;error='';
    content.replaceChildren();close();
  }
  function renderPanel(){
    if(panel.hidden)return;
    readButton.disabled=loading||reading||!rows?.some(n=>Number(n.unread)>0);
    readButton.setAttribute('aria-busy',String(reading));
    readButton.textContent=reading?'Marcando…':'Marcar todas leídas';
    content.setAttribute('aria-busy',String(loading));
    if(!userId())content.innerHTML='<div class="notice-empty"><strong>Tus estrenos, a mano.</strong><p>Inicia sesión para ver los capítulos nuevos de tus animes seguidos.</p><button class="button small primary" data-action="account">Iniciar sesión</button></div>';
    else if(error)content.innerHTML=`<div class="notice-empty"><strong>No se pudieron cargar los avisos.</strong><p>${e(error)}</p><button class="button small ghost" data-notice-action="retry">Volver a intentar</button></div>`;
    else if(loading&&!rows)content.innerHTML='<p class="notice-empty" role="status">Cargando notificaciones…</p>';
    else content.innerHTML=rows?.length?`<ul class="notice-items">${rows.slice(0,20).map(n=>`<li><button class="notice-item ${Number(n.unread)>0?'is-unread':''}" data-open="${e(n.slug)}"><img src="${e(n.cover)}" alt="" width="42" height="60" loading="lazy"><span class="notice-copy"><strong>${e(n.title)}</strong><span>${Number(n.episode_count)>1?`Capítulos ${Number(n.first_number)}–${Number(n.number)}`:`Capítulo ${Number(n.number)}`} disponible${Number(n.episode_count)>1?'s':''}</span><time datetime="${e(new Date(Number(n.created_at)*1000).toISOString())}">${e(dateText(Number(n.created_at)))}</time></span><span class="notice-indicator" aria-label="${Number(n.unread)>0?'Sin leer':'Leída'}">${Number(n.unread)>0?'●':'✓'}</span></button></li>`).join('')}</ul>`:'<div class="notice-empty"><strong>Estás al día.</strong><p>Aquí aparecerán los capítulos nuevos de los animes que sigues.</p></div>';
    position();
  }
  async function load(force=false){
    if(!userId()||loading||reading||(!force&&loadedKey===key()))return;
    const user=userId(),request=++sequence,signature=key();
    owner=user;loading=true;error='';renderPanel();
    try{
      const result=await api('notifications',{},true);
      if(request!==sequence||user!==userId())return;
      rows=result.notifications;upTo=Number(result.notifications_up_to)||0;loadedKey=signature;
    }catch(err){if(request===sequence&&user===userId()){error=err.message||'Revisa tu conexión.';loadedKey=signature;}}
    finally{if(request===sequence&&user===userId()){loading=false;renderPanel();if(!panel.hidden&&loadedKey!==key())load();}}
  }
  function sync(){
    if(owner!==userId())reset();
    if(!panel.hidden){if(loadedKey!==key())load();else renderPanel();}
  }
  function toggle(){
    if(!panel.hidden){close(true);return;}
    if(owner!==userId())reset();
    sidebarNavigation.closeMobile();
    panel.hidden=false;bell.setAttribute('aria-expanded','true');renderPanel();panel.focus({preventScroll:true});
    load();
  }
  async function markRead(){
    if(reading||loading||!userId()||!upTo||!rows?.some(n=>Number(n.unread)>0))return;
    const user=userId(),request=sequence,snapshot=upTo;reading=true;renderPanel();
    try{
      await api('notifications_read',{up_to:snapshot});
      if(request!==sequence||user!==userId())return;
      noticesPage=null;
      rows=rows.map(n=>({...n,unread:0}));loadedKey='';
    }catch(err){if(request===sequence&&user===userId())toast(err.message,true);}
    finally{if(request===sequence&&user===userId()){reading=false;renderPanel();if(!panel.hidden)load(true);}}
  }
  document.addEventListener('click',event=>{
    const toggleButton=event.target.closest('[data-action="notifications_toggle"]');
    if(toggleButton){event.preventDefault();event.stopImmediatePropagation();toggle();return;}
    if(!panel.contains(event.target))return;
    const action=event.target.closest('[data-notice-action]')?.dataset.noticeAction;
    if(action){event.preventDefault();event.stopImmediatePropagation();if(action==='close')close(true);if(action==='retry')load(true);if(action==='read')markRead();return;}
    if(event.target.closest('[data-open],[data-view],[data-action]'))close();
  });
  document.addEventListener('pointerdown',event=>{if(!panel.hidden&&!panel.contains(event.target)&&!bell.contains(event.target))close();});
  document.addEventListener('focusin',event=>{if(!panel.hidden&&!panel.contains(event.target)&&!bell.contains(event.target))close();});
  document.addEventListener('keydown',event=>{if(!panel.hidden&&event.key==='Escape'){event.preventDefault();close(true);}});
  window.addEventListener('resize',position,{passive:true});
  window.addEventListener('scroll',position,{passive:true});
  window.addEventListener('hashchange',()=>close());
  globalThis.SeasonNotifications={toggle,close,reset,sync};
})();
