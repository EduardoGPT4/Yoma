'use strict';
let personalData=null,personalLoading=null,personalOwner=0,personalGeneration=0,syncInbox=null,radioSaveTimer=null,radioSaveBusy=false,radioSaveAgain=false,catalogPulseAt=0,catalogPollTimer=null;
const shortId=bytes=>Array.from(crypto.getRandomValues(new Uint8Array(bytes)),n=>n.toString(16).padStart(2,'0')).join('');
function positionText(value){const n=Math.max(0,Math.floor(Number(value)||0));return `${Math.floor(n/60)}:${String(n%60).padStart(2,'0')}`;}
function resetPersonalUI(){personalGeneration++;personalOwner=0;personalData=null;personalLoading=null;syncInbox=null;clearTimeout(radioSaveTimer);clearTimeout(catalogPollTimer);radioSaveBusy=false;radioSaveAgain=false;downloadEventStates.clear();downloadEventAt=0;}
async function loadPersonalUI(force=false){
  if(!state?.user)return;if(personalData&&personalOwner===state.user.id&&!force)return personalData;if(personalLoading)return personalLoading;
  const user=state.user.id,generation=personalGeneration;personalOwner=user;
  personalLoading=(async()=>{const r=await api('personal',{},true);if(state.user?.id!==user||generation!==personalGeneration)return;
    personalData=r.personal;
    if(radio.libraryScope===String(user)){
      const cloud=r.personal.radio;
      if(cloud?.revision){
        let dirty=false,base='';try{dirty=localStorage.getItem(`seasonav1.radio.library.${user}.dirty`)==='yes';base=localStorage.getItem(`seasonav1.radio.library.${user}.revision`)||'';}catch{}
        if(dirty||(!base&&(radio.library.favorites.length||radio.library.lists.length))){radio.cloudRevision=base;if(base===cloud.revision)syncRadioLibrary();else radio.cloudConflict=cloud;}
        else {radio.library={favorites:cloud.favorites,lists:cloud.lists};radio.cloudRevision=cloud.revision;try{localStorage.setItem(`seasonav1.radio.library.${user}`,JSON.stringify(radio.library));localStorage.setItem(`seasonav1.radio.library.${user}.revision`,cloud.revision);}catch{}}
      }
      else {radio.cloudRevision='';if(radio.library?.favorites.length||radio.library?.lists.length)syncRadioLibrary();}
    }
    runCatalogPulse();
    if(['collections','sync','settings','radio'].includes(view))render();
    if(!personalData.options?.onboarding_done&&view==='discover'&&!document.getElementById('dialog').open&&!document.querySelector('.personal-guide')){const guide=document.createElement('aside');guide.className='note-banner personal-guide';guide.innerHTML='<span>Web, app de PC y extensión de video: configura solo lo que necesitas.</span><button class="button small ghost" data-personal="onboarding">Guía de inicio</button>';document.querySelector('#main')?.prepend(guide);}
    return personalData;
  })().finally(()=>{if(generation===personalGeneration)personalLoading=null;});return personalLoading;
}
function syncRadioLibrary(){
  clearTimeout(radioSaveTimer);const user=state.user?.id;if(!user||radio.libraryScope!==String(user))return;
  radioSaveTimer=setTimeout(async()=>{
    if(user!==state.user?.id)return;if(radioSaveBusy){radioSaveAgain=true;return;}
    if(!personalData){try{await loadPersonalUI();}catch(error){toast('Tu música sigue guardada en este navegador. No se pudo sincronizar.',true);}return;}
    if(radio.cloudConflict){toast('La radio cambió en otro dispositivo. Revisa las opciones de sincronización en Radio.',true);return;}
    radioSaveBusy=true;const generation=personalGeneration,sent=structuredClone(radio.library);
    try{const r=await api('personal_save',{kind:'radio',key:'library',expected_revision:radio.cloudRevision||'',data:sent});
      if(generation===personalGeneration&&state.user?.id===user){radio.cloudRevision=r.saved.revision;personalData.radio=r.saved;try{if(JSON.stringify(radio.library)===JSON.stringify(sent))localStorage.removeItem(`seasonav1.radio.library.${user}.dirty`);else radioSaveAgain=true;localStorage.setItem(`seasonav1.radio.library.${user}.revision`,r.saved.revision);}catch{}}
    }catch(error){if(generation===personalGeneration)toast(`Música sin sincronizar: ${error.message} Abre Radio de nuevo para consultar la copia de tu cuenta.`,true);}
    finally{if(generation===personalGeneration){radioSaveBusy=false;if(radioSaveAgain){radioSaveAgain=false;syncRadioLibrary();}}}
  },600);
}
function personalOptionsPanel(){
  if(!state.user)return '';if(!personalData)queueMicrotask(()=>loadPersonalUI().catch(()=>{}));const o=personalData?.options||{};
  return `<section class="panel"><h2>Tu cuenta en este equipo</h2><form id="personal-options"><label class="check"><input type="checkbox" name="shared" ${o.shared?'checked':''}>Equipo compartido: borrar borradores y caché personal al salir</label><label class="check"><input type="checkbox" name="forget_pc" ${o.forget_pc?'checked':''}>Olvidar también el emparejamiento de la PC al salir</label><button class="button ghost" type="submit">Guardar privacidad</button></form><div class="toolbar"><button class="text-button" data-personal="onboarding">Web, PC y extensión: guía rápida</button>${state.user.is_admin?'<button class="text-button" data-personal="support">Descargar informe técnico sin secretos</button>':''}</div></section>`;
}
function clearSharedAccountData(){
  const user=state.user?.id,o=personalData?.options||{};if(!user)return;
  if(o.shared){for(const storage of [localStorage,sessionStorage]){const keys=[];for(let i=0;i<storage.length;i++){const k=storage.key(i);if(k?.startsWith(`seasonav1.draft.${user}:`)||(k===`seasonav1.radio.library.${user}`||k?.startsWith(`seasonav1.radio.library.${user}.`))||k?.startsWith('seasonav1.settings-sync.'))keys.push(k);}for(const k of keys)storage.removeItem(k);}detailDrafts.clear();document.dispatchEvent(new CustomEvent('season-account-reset'));}
  if(o.forget_pc){bridge.forget();invalidateSettingsSync();}
}
function collectionsView(){
  if(!state.user)return empty('Colecciones personales','Inicia sesión para guardar listas sin modificar MAL.',button('account','Iniciar sesión','','','primary'));
  if(!personalData){queueMicrotask(()=>loadPersonalUI().catch(error=>toast(error.message,true)));return empty('Cargando tus colecciones','Un momento…');}
  return title('TUS PROPIAS LISTAS','Colecciones.','Agrupa animes por ocasión. Tu estado en MAL se conserva.',`<button class="button primary" data-personal="new-collection">Crear colección</button>`)+`<div class="personal-collections">${personalData.collections.map(c=>`<section class="panel"><h2>${e(c.data.name)}</h2><p>${c.data.slugs.length} ${c.data.slugs.length===1?'anime':'animes'}</p><div class="toolbar"><button class="button ghost" data-personal="edit-collection" data-key="${c.key}">Editar colección</button><button class="button danger" data-personal="delete-collection" data-key="${c.key}">Eliminar</button></div><div class="collection-titles">${c.data.slugs.map(slug=>`<a href="#anime-${e(slug)}" data-open="${e(slug)}">${e(personalData.collection_titles?.[slug]||state.anime.find(a=>a.slug===slug)?.title||slug.replaceAll('-',' '))}</a>`).join('')}</div></section>`).join('')||empty('Crea tu primera colección','Por ejemplo, Ver con amigos o Películas del fin de semana.')}</div>`;
}
function collectionEditor(key,slug=''){
  const c=personalData?.collections.find(c=>c.key===key),slugs=new Set(c?.data.slugs||[]);if(slug)slugs.add(slug);
  const anime=new Map(state.anime.map(a=>[a.slug,a.title]));if(slug&&!anime.has(slug))anime.set(slug,detailState?.anime.title||slug);
  for(const s of slugs)if(!anime.has(s))anime.set(s,s.replaceAll('-',' '));
  modal(`<h2>${c?'Editar':'Nueva'} colección</h2><form id="collection-form" data-key="${e(key||shortId(8))}"><label>Nombre<input class="form-input" name="name" maxlength="60" value="${e(c?.data.name||'')}" required></label><input class="form-input" type="search" id="collection-search" placeholder="Filtrar animes de tu biblioteca"><div class="collection-picker">${[...anime].map(([s,title])=>`<label data-collection-title="${e(title.toLowerCase())}"><input type="checkbox" name="slug" value="${e(s)}" ${slugs.has(s)?'checked':''}>${e(title)}</label>`).join('')}</div><button class="button primary" type="submit">Guardar colección</button></form>`);
}
function syncInboxView(){
  if(!state.user)return empty('Sincronización MAL','Inicia sesión para consultar tus envíos.');
  if(syncInbox===null){queueMicrotask(async()=>{try{const user=state.user.id,r=await api('sync_inbox',{},true);if(user===state.user?.id){syncInbox=r.sync_inbox;if(view==='sync')render();}}catch(error){toast(error.message,true);}});return empty('Consultando sincronización','Un momento…');}
  return title('WEB ↔ MYANIMELIST','Tus envíos a MAL.','Los bloqueados conservan la marca local. Revisa la causa antes de reintentar.',`<button class="button ghost" data-personal="refresh-sync">Actualizar</button>`)+`<div class="history-list">${syncInbox.map(r=>`<article class="history-item"><div><strong>${e(r.title)} · capítulo ${Number(r.target)}</strong><p>${e(r.message)}</p><small>${e(dateText(Number(r.updated_at)))} · ${Number(r.attempts)} reintentos${Number(r.next_retry)>Date.now()/1000?' · próximo '+e(dateText(Number(r.next_retry))):''}</small></div><div class="toolbar"><span class="status-pill ${r.state==='synced'?'confirmed':r.state==='blocked'?'failed':'queued'}">${e(({synced:'Confirmado',blocked:'Revisar',pending:'Pendiente'})[r.state]||r.state)}</span><button class="button small ghost" data-open="${e(r.slug)}">Revisar ficha</button>${r.error_kind==='unconfirmed'?`<button class="button small primary" data-personal="confirm-link" data-slug="${e(r.slug)}" data-id="${Number(r.mal_id)}">Confirmar vínculo</button>`:''}</div></article>`).join('')||empty('Sin envíos todavía','Los vistos aparecen aquí cuando usas el ojo o alcanzas el 80 % del capítulo.')}</div>`;
}
function playerBookmarks(p){return `<details class="watch-bookmarks"><summary>Escenas guardadas (${p.personal?.bookmarks?.length||0})</summary>${(p.personal?.bookmarks||[]).map(b=>`<div><button class="text-button" data-scene-seek="${Number(b.data.position)}">${positionText(b.data.position)} · ${e(b.data.note||'Escena guardada')}</button><button class="icon-button" data-personal="delete-bookmark" data-key="${b.key}" aria-label="Eliminar marcador">×</button></div>`).join('')||'<p class="muted">Pulsa ☆ debajo del video para guardar un minuto y una nota.</p>'}</details>`;}
function offerPlayerMalConfirmation(p){
  if(p!==playerView||!p.mal?.linked||p.mal.confirmed)return;
  const node=document.querySelector('.watch-manual-hint');if(node)node.innerHTML=`${p.watch_sync?.state==='blocked'?'Tu visto se guardó en la web.':'Antes del primer envío a MAL, confirma la coincidencia.'} <button class="text-button" data-personal="confirm-player">Confirma una vez la ficha MAL para sincronizar →</button>`;
}
async function confirmPlayerMal(p=playerView){
  if(!p?.mal?.linked){toast('Vincula el anime desde su ficha antes de sincronizar.',true);return;}await confirmMalLink(p.episode.slug,p.mal.id,p);
}
async function confirmMalLink(slug,id,p=null){
  const user=state.user?.id;
  let account=Number(featureHome?.mal?.profile?.id||p?.mal_account_id||0);
  const ticket=dialogTicket(),r=await api('mal_entry',{mal_id:Number(id)},true);if(user!==state.user?.id||!dialogCurrent(ticket)||(p&&p!==playerView))return;const m=r.entry||r.mal_entry||{};account=Number(m.mal_account_id||account);
  // The confirmation is about this fixed ID. Choosing another title remains a separate operation.
  modal(`<p class="eyebrow">CONFIRMACIÓN ÚNICA</p><h2>¿Es la misma temporada?</h2><p><strong>${e(p?.episode.title||state.anime.find(a=>a.slug===slug)?.title||slug)}</strong></p><p>MyAnimeList #${Number(id)} · ${e(m.title||m.anime?.title||'Consulta la ficha de MAL')} · ${e(m.media_type||m.anime?.media_type||'formato por comprobar')} · ${e(m.start_date||m.anime?.start_date||'fecha por comprobar')} · ${Number(m.num_episodes||m.anime?.num_episodes)||'?'} capítulos</p><a class="text-button" href="https://myanimelist.net/anime/${Number(id)}" target="_blank" rel="noopener noreferrer">Abrir ficha MAL ↗</a><p>Al confirmar se permitirán los envíos pendientes y el marcado automático de esta ficha. Si no coincide, elige otro vínculo desde la ficha del anime.</p><button class="button primary" data-personal="confirm-link-save" data-slug="${e(slug)}" data-id="${Number(id)}" data-account="${account}">Confirmar esta ficha</button>`);
}
function maybePrefetchNext(p,s){
  if(p.prefetchStarted||s.duration<=0||s.position/s.duration<0.85)return;p.prefetchStarted=true;const user=state.user?.id;
  api('player_prefetch',{episode_id:Number(p.episode.id)}).then(r=>{if(user===state.user?.id&&playerView===p&&r.prefetch)runCatalogPulse();}).catch(()=>{});
}
async function runCatalogPulse(){
  if(!state?.user||document.hidden||Date.now()-catalogPulseAt<300000)return;catalogPulseAt=Date.now();
  try{await api('catalog_pulse');}catch(error){/* The central queue keeps its retry time and last good data. */}
}
function pollPlayerTask(p){
  clearTimeout(catalogPollTimer);if(!p||p!==playerView||!['pending','running'].includes(p.update_task?.state))return;const user=state.user?.id;
  if(document.hidden){catalogPollTimer=setTimeout(()=>pollPlayerTask(p),60000);return;}
  runCatalogPulse();catalogPollTimer=setTimeout(async()=>{if(playerView!==p||state.user?.id!==user)return;
    try{const r=await api('catalog_task',{slug:p.episode.slug,episode_id:p.episode.id},true);if(playerView!==p||state.user?.id!==user)return;p.update_task=r.task;p.server_refresh.message=r.message;
      if(r.task?.state==='done')await loadCachedPlayerServers(p);
      else{updateServerNotice(p);pollPlayerTask(p);}
    }catch(error){if(playerView===p){p.server_refresh.message=error.message;updateServerNotice(p);}}
  },10000);
}
function onboarding(){
  modal(`<p class="eyebrow">TRES PIEZAS, UNA BIBLIOTECA</p><h2>Empieza a tu ritmo</h2><ol class="onboarding-steps"><li><strong>La web</strong><p>Explora, organiza y reproduce capítulos. Conecta MAL para guardar tu progreso.</p><button class="button ghost" data-action="account">Conectar MyAnimeList</button></li><li><strong>YomaTV en tu PC</strong><p>Necesaria solo para descargar y mantener tu cola en segundo plano.</p>${exeDownload('ghost','Descargar app para Windows')}<button class="text-button" data-action="connect">Emparejar mi PC</button></li><li><strong>Extensión de video en Brave</strong><p>Permite reanudar, usar los controles y detectar el 80 % dentro de MP4Upload.</p><button class="button ghost" data-action="player_extension">Instalar extensión</button></li></ol><button class="button primary" data-personal="onboarding-done">Entendido</button>`);
}
function jsonDownload(data,name){const url=URL.createObjectURL(new Blob([JSON.stringify(data,null,2)],{type:'application/json'})),a=document.createElement('a');a.href=url;a.download=name;a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);}
document.addEventListener('input',event=>{
  if(event.target.id==='watch-chapter-search'&&playerView){playerView.chapterQuery=event.target.value.trim();playerChapterPage=1;document.querySelector('#watch-chapters').innerHTML=watchChapters(playerView);}
  if(event.target.id==='collection-search'){const q=event.target.value.toLowerCase();document.querySelectorAll('[data-collection-title]').forEach(n=>n.hidden=!n.dataset.collectionTitle.includes(q));}
});
document.addEventListener('click',async event=>{
  const seek=event.target.closest('[data-scene-seek]');if(seek){event.preventDefault();playerController?.post('seek',Number(seek.dataset.sceneSeek));playerController?.post('play');return;}
  const report=event.target.closest('[data-radio-report]');if(report){if(!requireUser())return;modal(`<h2>Reportar canción</h2><p>El reporte se revisa en administración.</p><form id="radio-report-form" data-track="${e(report.dataset.radioReport)}"><label>Motivo<select class="select-input" name="reason"><option value="association">Anime, canción o artista incorrecto</option><option value="unavailable">Video no disponible</option><option value="other">Otro dato incorrecto</option></select></label><button class="button primary">Enviar reporte</button></form>`);return;}
  const b=event.target.closest('[data-personal]');if(!b||b.disabled)return;event.preventDefault();event.stopImmediatePropagation();const user=state.user?.id,action=b.dataset.personal;b.disabled=true;
  try{
    if(action==='onboarding')onboarding();
    if(action==='onboarding-done'){await api('personal_save',{kind:'options',key:'account',data:{...personalData?.options,onboarding_done:true}});if(user===state.user?.id){if(personalData)personalData.options.onboarding_done=true;document.getElementById('dialog').close();}}
    if(action==='support'){const r=await api('support_report');if(user===state.user?.id)jsonDownload(r.report,'YomaTV-diagnostico.json');}
    if(action==='radio-refresh'){await loadPersonalUI(true);if(user===state.user?.id)toast(radio.cloudConflict?'Hay cambios distintos: puedes combinar ambas copias.':'Copia de la cuenta consultada.');}
    if(action==='radio-merge'&&radio.cloudConflict){const cloud=radio.cloudConflict,lists=new Map(cloud.lists.map(l=>[l.id,structuredClone(l)]));for(const l of radio.library.lists){const old=lists.get(l.id);lists.set(l.id,old?{...old,ids:[...new Set([...old.ids,...l.ids])].slice(0,300)}:l);}if(lists.size>20)throw new Error('Las copias suman más de veinte listas. Exporta tu cuenta y elimina alguna antes de combinar.');radio.library={favorites:[...new Set([...cloud.favorites,...radio.library.favorites])].slice(0,300),lists:[...lists.values()]};radio.cloudRevision=cloud.revision;radio.cloudConflict=null;radio.storeLibrary();render();}
    if(action==='refresh-sync'){syncInbox=null;render();}
    if(action==='confirm-player')await confirmPlayerMal();
    if(action==='confirm-link')await confirmMalLink(b.dataset.slug,Number(b.dataset.id));
    if(action==='confirm-link-save'){
      await api('mal_confirm',{slug:b.dataset.slug,mal_id:Number(b.dataset.id),mal_account_id:Number(b.dataset.account),confirmation:'CONFIRMAR'});
      if(user!==state.user?.id)return;if(playerView?.episode.slug===b.dataset.slug){playerView.mal.confirmed=true;const hint=document.querySelector('.watch-manual-hint');if(hint)hint.textContent='Ficha MAL confirmada. La detección automática del 80 % sigue activa en MP4Upload.';updateWatchPage();}syncInbox=null;document.getElementById('dialog').close();toast('Vínculo confirmado. Tus vistos pendientes se sincronizarán.');if(view==='sync')render();scheduleWatchPump();
    }
    if(action==='next-unwatched'&&playerView){const p=playerView,next=p.chapters.find(ep=>!ep.watched&&!(p.mal?.linked&&Number(ep.number)<=Number(p.mal.watched)));if(next)await openPlayer(Number(next.id));else toast('Todos los capítulos disponibles están vistos.');}
    if(action==='intro'&&playerView){const p=playerView,range=p.personal?.intro||{},position=Math.floor(playerController?.latest.position||0);modal(`<h2>Intro de ${e(p.episode.title)}</h2><p>Indica inicio y final en segundos. Se aplicará a tus capítulos de este anime.</p><form id="intro-form" data-slug="${e(p.episode.slug)}"><div class="field-pair"><label>Inicio (s)<input class="form-input" type="number" name="start" min="0" max="3600" value="${range.start??Math.max(0,position-85)}" required></label><label>Final (s)<input class="form-input" type="number" name="end" min="1" max="3600" value="${range.end??(position||85)}" required></label></div><button class="button primary">Guardar tramo</button><button type="button" class="button ghost" data-personal="delete-intro" data-key="${e(p.episode.slug)}">Usar salto de 85 s</button></form>`);}
    if(action==='bookmark'&&playerView){const p=playerView,position=playerController?.latest.position;if(!Number.isFinite(position))throw new Error('Conecta la extensión y reproduce el video para guardar una escena.');modal(`<h2>Guardar escena · ${positionText(position)}</h2><form id="bookmark-form" data-slug="${e(p.episode.slug)}" data-number="${e(p.episode.number)}" data-position="${position}"><label>Nota privada<input class="form-input" name="note" maxlength="500" placeholder="Una escena para volver a ver"></label><button class="button primary">Guardar marcador</button></form>`);}
    if(action==='delete-bookmark'||action==='delete-intro'){await api('personal_delete',{kind:action==='delete-intro'?'intro':'bookmark',key:b.dataset.key});if(user!==state.user?.id)return;if(action==='delete-bookmark'&&playerView){playerView.personal.bookmarks=playerView.personal.bookmarks.filter(r=>r.key!==b.dataset.key);document.querySelector('.watch-bookmarks').outerHTML=playerBookmarks(playerView);}else{if(playerView){playerView.personal.intro={};if(playerController)playerController.intro=null;}document.getElementById('dialog').close();}}
    if(action==='new-collection'||action==='edit-collection'){await loadPersonalUI();if(user===state.user?.id)collectionEditor(action==='edit-collection'?b.dataset.key:null);}
    if(action==='add-collection'){await loadPersonalUI();if(user!==state.user?.id)return;modal(`<h2>Añadir a una colección</h2>${personalData.collections.map(c=>`<button class="button ghost" data-personal="collection-add-save" data-key="${c.key}" data-slug="${e(b.dataset.slug)}">${e(c.data.name)}</button>`).join('')}<button class="button primary" data-personal="collection-new-anime" data-slug="${e(b.dataset.slug)}">Nueva colección</button>`);}
    if(action==='collection-new-anime')collectionEditor(null,b.dataset.slug);
    if(action==='collection-add-save'){const c=personalData.collections.find(c=>c.key===b.dataset.key);await api('personal_save',{kind:'collection',key:c.key,data:{name:c.data.name,slugs:[...new Set([...c.data.slugs,b.dataset.slug])]}});if(user===state.user?.id){await loadPersonalUI(true);document.getElementById('dialog').close();toast('Anime añadido a tu colección.');}}
    if(action==='delete-collection'&&await experienceConfirm('¿Eliminar esta colección? Se conservarán tus animes y tu progreso.')){await api('personal_delete',{kind:'collection',key:b.dataset.key});await loadPersonalUI(true);}
    if(action==='update-app')activateWebUpdate();
  }catch(error){if(!error.cancelled)toast(error.message,true);}finally{b.disabled=false;}
});
document.addEventListener('submit',async event=>{
  const f=event.target;if(!['collection-form','intro-form','bookmark-form','personal-options','radio-report-form'].includes(f.id))return;
  event.preventDefault();event.stopImmediatePropagation();const user=state.user?.id,submit=f.querySelector('button[type="submit"],button:not([type])');if(submit)submit.disabled=true;
  try{
    let r;
    if(f.id==='radio-report-form')r=await api('radio_report',{track:f.dataset.track,reason:f.elements.reason.value});
    if(f.id==='collection-form')r=await api('personal_save',{kind:'collection',key:f.dataset.key,data:{name:f.elements.name.value.trim(),slugs:new FormData(f).getAll('slug')}});
    if(f.id==='personal-options')r=await api('personal_save',{kind:'options',key:'account',data:{...personalData?.options,shared:f.elements.shared.checked,forget_pc:f.elements.forget_pc.checked}});
    if(f.id==='intro-form')r=await api('personal_save',{kind:'intro',key:f.dataset.slug,data:{start:Number(f.elements.start.value),end:Number(f.elements.end.value)}});
    if(f.id==='bookmark-form')r=await api('personal_save',{kind:'bookmark',key:shortId(16),data:{slug:f.dataset.slug,number:f.dataset.number,position:Number(f.dataset.position),note:f.elements.note.value.trim()}});
    if(user!==state.user?.id)return;
    if(f.id==='intro-form'&&playerView?.episode.slug===f.dataset.slug){playerView.personal.intro=r.saved;if(playerController)playerController.intro=r.saved;}
    if(f.id==='bookmark-form'&&playerView?.episode.slug===f.dataset.slug){/* Reload only metadata: opening a player here would invalidate its session. */const current=playerView,data=await api('player_notes',{episode_id:current.episode.id});if(user===state.user?.id&&playerView===current){playerView.personal=data.personal;document.querySelector('.watch-bookmarks').outerHTML=playerBookmarks(playerView);}}
    if(['personal-options','collection-form'].includes(f.id))await loadPersonalUI(true);
    document.getElementById('dialog').close();toast(r.message||'Guardado.');
  }catch(error){if(!error.cancelled)toast(error.message,true);}finally{if(submit)submit.disabled=false;}
});
// Add collection actions to the existing detail view without duplicating its template.
new MutationObserver(()=>{const body=document.getElementById('dialog-body');if(!state?.user||!detailState||!body.querySelector('#detail-form')||body.querySelector('[data-personal="add-collection"]'))return;const b=document.createElement('button');b.className='button ghost';b.dataset.personal='add-collection';b.dataset.slug=detailState.anime.slug;b.textContent='Añadir a colección';body.querySelector('#detail-form').before(b);}).observe(document.getElementById('dialog-body'),{childList:true});
document.addEventListener('visibilitychange',()=>{if(!document.hidden&&state?.user){loadPersonalUI(true).catch(()=>{});runCatalogPulse();}});

function pendingPlayerTask(p){return ['pending','running'].includes(p?.update_task?.state);}
function sagaWatchOrder(p){const rows=p.related?.watch_order||[];return rows.length?`<details class="watch-saga-order" open><summary>Recorrido de la saga</summary><p class="muted">Precuelas → actual → secuelas. Películas, especiales y otras temporadas por estreno; relaciones revisadas.</p><ol>${rows.map(r=>`<li><a href="#anime-${e(r.slug)}" data-open="${e(r.slug)}">${e(r.title)}</a><small>${Number(r.watched)} / ${Number(r.total)||'?'} vistos · ${e(({prequel:'Precuela',current:'Este anime',sequel:'Secuela',season:'Otra temporada',movie:'Película',special:'Especial'})[r.relation])}</small></li>`).join('')}</ol></details>`:'';}
const downloadEventStates=new Map();let downloadEventAt=0;
async function persistDownloadEvents(statuses,user){
  const device=bridge.info?.device?.id;if(!device||state.user?.id!==user)return;
  const key=id=>`${user}:${device}:${id}`;
  const items=statuses.map(s=>({id:Number(s.web_id),state:s.status==='pending'?'queued':s.status,attempts:Number.isInteger(s.attempts)?s.attempts:0,error_kind:s.status==='failed'?(/conex|dns|network|timeout/i.test(s.reason||'')?'connection':/disco|disk|espacio/i.test(s.reason||'')?'disk':/integr|verific|corrupt/i.test(s.reason||'')?'verification':/servidor|server/i.test(s.reason||'')?'server':'unknown'):''})).filter(item=>downloadEventStates.get(key(item.id))!==JSON.stringify(item));
  if(!items.length||Date.now()-downloadEventAt<30000)return;downloadEventAt=Date.now();
  for(let i=0;i<items.length;i+=200){if(state.user?.id!==user||bridge.info?.device?.id!==device)return;const batch=items.slice(i,i+200);await api('download_events',{installation:state.installation,device_id:device,items:batch});if(state.user?.id!==user)return;for(const row of batch)downloadEventStates.set(key(row.id),JSON.stringify(row));}
  if(state.user?.id===user&&view==='queue'&&queueAnime)loadQueuePage(queueAnime,queuePage,queueFilter,true);
}
