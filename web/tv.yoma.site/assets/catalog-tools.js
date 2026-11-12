'use strict';
let savedFilterOwner = -1, savedFilterRows = [], savedFilterLoading = false, savedFilterError = '';
function savedFilterView() {
  const user = state.user?.id || 0;
  if (user !== savedFilterOwner) { savedFilterOwner=user; savedFilterRows=[]; savedFilterLoading=false; savedFilterError=''; }
  if (!user) return '';
  if (!savedFilterLoading && !savedFilterRows.length && !savedFilterError) {
    savedFilterLoading=true;
    api('saved_filters',{},true).then(r=>{
      if (state.user?.id!==user) return;
      savedFilterRows=r.saved_filters; savedFilterError=savedFilterRows.length?'':'empty';
    }).catch(error=>{if(state.user?.id===user) savedFilterError=error.message;}).finally(()=>{
      if(state.user?.id===user) {savedFilterLoading=false;if(view==='discover') renderFeaturePage();}
    });
  }
  return `<div class="saved-searches"><button class="button small ghost" data-action="filters_save">${icon('star')}Guardar búsqueda</button>${savedFilterRows.map(r=>`<span class="saved-search"><button class="text-button" data-action="filters_apply" data-id="${r.id}">${e(r.name)}</button><button class="icon-button" data-action="filters_delete" data-id="${r.id}" title="Eliminar búsqueda ${e(r.name)}" aria-label="Eliminar búsqueda ${e(r.name)}">${icon('close')}</button></span>`).join('')}${savedFilterError && savedFilterError!=='empty'?`<button class="text-button" data-action="filters_retry">Reintentar búsquedas guardadas</button>`:''}</div>`;
}
function catalogCoverageView(c) {
  if (!c?.freshness) return '';
  const f=c.freshness;
  return `<dl class="data-coverage">${[['episodes','Capítulos'],['servers','Servidores'],['genres','Géneros'],['airing','Emisión'],['directory','Directorio']].map(([key,label])=>{
    const row=f[key]; return `<div><dt>${label}</dt><dd>${row.checked||0} / ${key==='servers'?row.total:f.total}<small>Última comprobación: ${e(dateText(row.newest))}${row.oldest?` · Más antigua: ${e(dateText(row.oldest))}`:''}</small></dd></div>`;
  }).join('')}</dl><p class="muted">La cobertura cuenta fichas comprobadas; servidores cuenta capítulos. Las fechas son independientes y la renovación avanza por lotes.</p>`;
}
function detailDataView(d) {
  const f=d.freshness;if(!f) return '';
  const a=d.anime, task=d.update_task, pending=['pending','running'].includes(task?.state);
  return `<details class="detail-data"><summary>Estado de los datos${pending?' · actualización solicitada':''}</summary><dl class="data-coverage">${[['episodes_at','Listado completo'],['genres_at','Géneros'],['airing_at','Emisión']].map(([key,label])=>`<div><dt>${label}</dt><dd>${f[key]?e(dateText(f[key])):'Sin comprobar'}</dd></div>`).join('')}<div><dt>Servidores</dt><dd>${f.servers_checked} / ${f.episodes_known} capítulos<small>${f.servers_newest?e(dateText(f.servers_newest)):'Sin comprobar'}</small></dd></div></dl><p class="muted">Las solicitudes se procesan durante el mantenimiento autorizado del sitio. No se ejecutan desde tu cuenta.</p>${task?.state==='failed'?'<p class="form-error">La actualización falló varias veces. El administrador debe revisar y reintentar.</p>':''}${state.user?`<button class="button small ghost" data-action="data_request" data-slug="${e(a.slug)}" ${pending||task?.state==='failed'?'disabled':''}>${icon('refresh')}${pending?'En espera de actualización':'Solicitar actualización'}</button>`:'<p>Inicia sesión para solicitar una ficha actualizada.</p>'}</details>`;
}
const RELATION_LABELS={prequel:'Precuela',sequel:'Secuela',season:'Otra temporada',movie:'Película',special:'Especial',side_story:'Historia paralela',other:'Relacionado'};
function detailRelationsView(d) {
  const rows=d.relations||[],admin=state.user?.is_admin;
  if(!rows.length&&!admin) return '';
  return `<section class="related-section"><div class="section-heading"><h3>Historias relacionadas</h3>${admin?`<button class="button small ghost" data-action="relation_add" data-slug="${e(d.anime.slug)}">Añadir relación</button>`:''}</div>${admin?'<p class="muted">Las propuestas del origen requieren tu revisión. Comprueba temporada, formato y ficha antes de aprobarlas.</p>':''}<div class="related-grid">${rows.map(r=>`<article class="related-card"><button class="related-open" data-open="${e(r.target)}"><img src="${e(r.cover)}" alt="" loading="lazy"><span><strong>${e(r.title)}</strong><small>${e(RELATION_LABELS[r.relation]||'Relacionado')} · ${e(r.category)}</small></span></button>${admin?`<div class="relation-review"><select class="select-input" aria-label="Tipo de relación con ${e(r.title)}">${Object.entries(RELATION_LABELS).map(([k,v])=>`<option value="${k}" ${r.relation===k?'selected':''}>${v}</option>`).join('')}</select><span class="muted">${e({pending:'Pendiente de revisión',approved:'Aprobada',rejected:'Descartada'}[r.state])}</span><button class="button small ghost" data-action="relation_approve" data-slug="${e(d.anime.slug)}" data-target="${e(r.target)}">Aprobar</button><button class="text-button" data-action="relation_reject" data-slug="${e(d.anime.slug)}" data-target="${e(r.target)}">Descartar</button>${r.evidence.startsWith('https://animeav1.com/media/')?`<a class="text-button" href="${e(r.evidence)}" target="_blank" rel="noopener noreferrer">Comprobar origen ↗</a>`:''}</div>`:''}</article>`).join('')}</div></section>`;
}
function calendarDialog(feed, enabled=true) {
  if(!enabled) {
    modal(`<p class="eyebrow">EXPORTAR HORARIO</p><h2>Tu calendario de anime</h2><p>InfinityFree exige una verificación JavaScript que los calendarios externos no pueden realizar. Las suscripciones automáticas necesitan un alojamiento compatible.</p><p>Puedes importar una copia del horario en tu calendario. Vuelve a exportarlo cuando cambie.</p><div class="toolbar"><a class="button primary" href="calendar.php?scope=followed">Exportar mis seguidos y favoritos</a><a class="button ghost" href="calendar.php">Exportar todo el horario</a></div>`);return;
  }
  const url=feed?new URL(feed.url,location.href).href:'';
  modal(`<p class="eyebrow">HORARIO ACTUALIZABLE</p><h2>Tu calendario de anime</h2><p>La suscripción usa un enlace privado que se actualiza con el horario. Los estrenos son estimaciones semanales; tu calendario decide cada cuánto revisa el enlace.</p><label class="catalog-field"><span>Incluir en la suscripción</span><select id="calendar-scope" class="select-input"><option value="followed" ${feed?.scope!=='all'?'selected':''}>Mis animes seguidos y favoritos</option><option value="all" ${feed?.scope==='all'?'selected':''}>Todo el horario</option></select></label>${feed?`<p class="muted">Enlace privado · actualizado ${e(dateText(feed.updated_at))}. No lo compartas.</p><input class="form-input" aria-label="Enlace de suscripción" value="${e(url)}" readonly><div class="toolbar"><a class="button small primary" href="${e(url.replace(/^https?:/,'webcal:'))}">Suscribirse</a><button class="button small ghost" data-action="calendar_copy" data-url="${e(url)}">Copiar enlace</button><a class="button small ghost" href="${e(url)}" download>Descargar .ics</a></div>`:''}<div class="toolbar"><button class="button ghost" data-action="calendar_create">${feed?'Reemplazar enlace con este filtro':'Crear enlace privado'}</button>${feed?'<button class="button danger" data-action="calendar_revoke">Revocar enlace</button>':''}</div><p class="muted">Reemplazar o revocar invalida el enlace anterior. También puedes <a href="calendar.php?scope=followed">exportar mis seguidos</a> o <a href="calendar.php">exportar todo</a> sin crear una suscripción.</p>`);
}
document.addEventListener('click',event=>{
  const b=event.target.closest('[data-action]');if(!b) return;
  const action=b.dataset.action;
  if(!['filters_save','filters_apply','filters_delete','filters_retry','data_request','data_servers','relation_add','relation_approve','relation_reject','calendar_open','calendar_create','calendar_revoke','calendar_copy','data_retry','notices_more'].includes(action)) return;
  event.preventDefault();event.stopImmediatePropagation();
  (async()=>{
    if(!requireUser()) return;
    const user=state.user.id,ticket=dialogTicket();
    if(action==='notices_more') {b.disabled=true;try {const r=await api('notifications',{before:Math.min(...noticesPage.map(n=>Number(n.id)))},true);if(user===state.user?.id){noticesPage.push(...r.notifications);noticesHasMore=r.notifications.length===50;render();}}finally{b.disabled=false;}return;}
    if(action==='filters_retry') {savedFilterError='';render();return;}
    if(action==='filters_save') {modal(`<h2>Guardar esta búsqueda</h2><form id="saved-filter-form"><label class="catalog-field"><span>Nombre</span><input class="form-input" name="name" maxlength="60" required placeholder="Comedias pendientes"></label><button class="button primary" type="submit">Guardar búsqueda</button></form>`);return;}
    if(action==='filters_apply') {
      const row=savedFilterRows.find(r=>r.id===Number(b.dataset.id));if(!row) return;
      Object.assign(catalogFilters,CATALOG_DEFAULTS,row.filters,{page:1});catalogWriteRoute();await loadCatalog();return;
    }
    if(action==='filters_delete') {const r=await api('delete_filter',{id:Number(b.dataset.id)});if(state.user?.id===user) {savedFilterRows=r.saved_filters;savedFilterError='empty';render();}return;}
    if(action==='data_request'||action==='data_servers') {
      const r=await api('catalog_request',{slug:b.dataset.slug,...(action==='data_servers'?{episode_id:Number(b.dataset.episode)}:{})});
      if(dialogCurrent(ticket)&&user===state.user?.id) {renderDetail();toast(r.message);}return;
    }
    if(action==='relation_add') {
      modal(`<h2>Añadir relación revisada</h2><p>Usa el identificador del anime que aparece al final de su enlace de AnimeAV1. Solo se aceptan fichas del catálogo.</p><form id="relation-form" data-slug="${e(b.dataset.slug)}"><label class="catalog-field"><span>Identificador del anime relacionado</span><input class="form-input" name="target" required maxlength="240" placeholder="naruto-shippuuden"></label><label class="catalog-field"><span>Relación</span><select class="select-input" name="relation">${Object.entries(RELATION_LABELS).map(([k,v])=>`<option value="${k}">${v}</option>`).join('')}</select></label><button class="button primary" type="submit">Guardar relación revisada</button></form>`);return;
    }
    if(action==='relation_approve'||action==='relation_reject') {
      await api('relation_review',{slug:b.dataset.slug,target:b.dataset.target,relation:b.closest('.relation-review').querySelector('select').value,state:action==='relation_approve'?'approved':'rejected'});
      if(dialogCurrent(ticket)&&user===state.user?.id) renderDetail();return;
    }
    if(action==='calendar_open') {const r=await api('calendar_feed',{},true);if(dialogCurrent(ticket)&&user===state.user?.id) calendarDialog(r.calendar_feed,r.calendar_subscriptions_enabled);return;}
    if(action==='calendar_copy') {await navigator.clipboard.writeText(b.dataset.url);toast('Enlace copiado.');return;}
    if(action==='calendar_create'||action==='calendar_revoke') {const r=await api(action,{scope:document.getElementById('calendar-scope').value});if(dialogCurrent(ticket)&&user===state.user?.id) {calendarDialog(r.calendar_feed);toast(r.message);}return;}
    if(action==='data_retry') {const r=await api('catalog_retry');if(user===state.user?.id){renderFeaturePage();toast(r.message);}return;}
  })().catch(error=>toast(error.message,true));
});
document.addEventListener('submit',event=>{
  const form=event.target;if(!['saved-filter-form','relation-form'].includes(form.id)) return;
  event.preventDefault();event.stopImmediatePropagation();
  const user=state.user?.id,ticket=dialogTicket(),data=Object.fromEntries(new FormData(form));
  const saving=form.id==='saved-filter-form';
  const payload=saving?{name:data.name,filters:{...catalogFilters,include_genres:[...catalogFilters.include_genres],exclude_genres:[...catalogFilters.exclude_genres]}}:{...data,slug:form.dataset.slug};
  form.querySelector('button').disabled=true;
  api(saving?'save_filter':'relation_review',payload).then(r=>{
    if(user!==state.user?.id||!dialogCurrent(ticket))return;
    if(saving){savedFilterRows=r.saved_filters;savedFilterError='';$('#dialog').close();render();}
    else renderDetail();toast(r.message);
  }).catch(error=>{if(dialogCurrent(ticket)){form.querySelector('button').disabled=false;toast(error.message,true);}});
});
