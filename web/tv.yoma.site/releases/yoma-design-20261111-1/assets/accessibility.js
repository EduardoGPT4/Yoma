'use strict';
(() => {
  const dialog=document.getElementById('dialog'),body=document.getElementById('dialog-body');
  let opener=null,wasOpen=false;
  const allowed=new Set(['detail-form','settings-form','mal-edit-form']);
  const drafts=new Map();
  document.addEventListener('season-account-reset',()=>drafts.clear());
  const key=form=>`${state?.user?.id||0}:${form.id}:${form.dataset.slug||form.dataset.id||''}:${form.dataset.account||''}`;
  const snapshot=form=>Object.fromEntries([...form.elements].filter(t=>t.name&&!['password','file','hidden'].includes(t.type)).map(t=>[t.name,t.type==='checkbox'?t.checked:t.value]));
  function save(form){
    if(!allowed.has(form.id)||!state?.user)return;
    const values=snapshot(form),changed=JSON.stringify(values)!==form.dataset.draftBaseline;
    const k=key(form);form.dataset.draftDirty=changed?'true':'false';
    if(changed)drafts.set(k,values);else drafts.delete(k);
    try{changed?sessionStorage.setItem(`seasonav1.draft.${k}`,JSON.stringify(values)):sessionStorage.removeItem(`seasonav1.draft.${k}`);}catch{}
    const notice=form.querySelector('[data-draft-notice]');if(notice)notice.hidden=!changed;
  }
  function enhance(){
    document.querySelectorAll('.nav-item[data-view]').forEach(node=>{node.classList.contains('active')?node.setAttribute('aria-current','page'):node.removeAttribute('aria-current');});
    const title=body.querySelector('h2,h1');
    if(title){title.id=title.id||'dialog-heading';dialog.setAttribute('aria-labelledby',title.id);dialog.removeAttribute('aria-label');}
    else {dialog.removeAttribute('aria-labelledby');dialog.setAttribute('aria-label','YomaTV · diálogo');}
    for(const form of document.querySelectorAll('form')){
      if(!form.hasAttribute('aria-label')&&!form.hasAttribute('aria-labelledby'))form.setAttribute('aria-label',title&&body.contains(form)?title.textContent:'Preferencias de YomaTV');
      if(!allowed.has(form.id)||form.dataset.draftReady||!state?.user)continue;
      form.dataset.draftReady='true';form.dataset.draftBaseline=form.dataset.originalDraftBaseline||JSON.stringify(snapshot(form));
      let values=drafts.get(key(form));try{values=values||JSON.parse(sessionStorage.getItem(`seasonav1.draft.${key(form)}`)||'null');}catch{}
      if(values){for(const [name,value] of Object.entries(values)){const t=form.elements.namedItem(name);if(t&&t.type!=='password')t.type==='checkbox'?t.checked=Boolean(value):t.value=String(value);}drafts.set(key(form),values);}
      const notice=document.createElement('div');notice.dataset.draftNotice='';notice.className='draft-notice';notice.innerHTML='<span>Borrador conservado en esta pestaña.</span><button type="button" class="text-button" data-discard-draft>Descartar borrador</button>';form.append(notice);save(form);
    }
    if(dialog.open&&!wasOpen){opener=typeof dialogReturnFocus==='undefined'?document.activeElement:dialogReturnFocus;wasOpen=true;}
  }
  let scheduled=false;
  new MutationObserver(()=>{if(scheduled)return;scheduled=true;queueMicrotask(()=>{scheduled=false;enhance();});}).observe(document.querySelector('.app-shell'),{childList:true,subtree:true});
  new MutationObserver(enhance).observe(body,{childList:true});
  dialog.addEventListener('close',()=>{wasOpen=false;const target=opener?.isConnected&&opener.getClientRects().length&&!opener.closest('[inert]')?opener:document.getElementById('main');target?.focus({preventScroll:true});});
  document.addEventListener('input',event=>{const form=event.target.closest('form');if(form)save(form);});
  document.addEventListener('change',event=>{const form=event.target.closest('form');if(form)save(form);if(event.target.id==='appearance-density')setAppearance('density',event.target.value);});
  document.addEventListener('click',async event=>{
    if(event.target.closest('.skip-content')){event.preventDefault();document.getElementById('main').focus();return;}
    if(event.target.closest('[data-discard-draft]')){
      event.preventDefault();const form=event.target.closest('form');if(!await experienceConfirm('¿Descartar los cambios de este borrador?'))return;
      const values=JSON.parse(form.dataset.draftBaseline);for(const [name,value] of Object.entries(values)){const t=form.elements.namedItem(name);if(t)t.type==='checkbox'?t.checked=value:t.value=value;}
      if(form.id==='detail-form')detailDrafts.delete(`${state.user.id}:${form.dataset.slug}`);save(form);
    }
  });
  document.addEventListener('season-form-saved',event=>{const form=event.detail;if(!form)return;form.dataset.draftBaseline=JSON.stringify(snapshot(form));save(form);if(form.id==='detail-form')detailDrafts.delete(`${state.user.id}:${form.dataset.slug}`);});
  window.addEventListener('beforeunload',event=>{if(document.querySelector('form[data-draft-dirty="true"]')){event.preventDefault();event.returnValue='';}});
})();
