'use strict';
const episodeSelections=new Map(),episodePages=new Map(),filePresence=new Map();
let experienceRequest=0;
function experienceConfirm(message){
  const user=state.user?.id||0,dialog=document.createElement('dialog');dialog.className='dialog confirm-dialog';dialog.setAttribute('aria-labelledby','experience-confirm-heading');
  dialog.innerHTML=`<h2 id="experience-confirm-heading">Confirmar cambio</h2><p>${e(message)}</p><div class="toolbar"><button type="button" class="button ghost" data-confirm-value="no">Cancelar</button><button type="button" class="button primary" data-confirm-value="yes">Confirmar</button></div>`;
  document.body.append(dialog);let yes=false;
  return new Promise(resolve=>{dialog.addEventListener('click',event=>{const value=event.target.closest('[data-confirm-value]')?.dataset.confirmValue;if(value){yes=value==='yes';dialog.close();}});dialog.addEventListener('close',()=>{dialog.remove();resolve(yes&&user===(state.user?.id||0));},{once:true});dialog.showModal();});
}
function episodeSelection(){const key=`${state.user?.id||0}:${detailState?.anime.slug||''}`;if(!episodeSelections.has(key))episodeSelections.set(key,new Set());return episodeSelections.get(key);}
function episodeSelectionIds(){const selected=episodeSelection();return (detailState?.episodes||[]).filter(ep=>selected.has(Number(ep.id))&&episodeCanPrepare(ep)).map(ep=>Number(ep.id));}
function detailEpisodesView(eps){
  const mode=detailState.watch_mode?.mode;
  const slug=detailState.anime.slug,key=`${state.user?.id||0}:${slug}`,pages=Math.max(1,Math.ceil(eps.length/36)),page=Math.min(pages,episodePages.get(key)||1);
  episodePages.set(key,page);return `<section id="detail-episodes">${mode==='rewatch'?'<p class="note-banner">Revisionado activo. Sus marcas están separadas del progreso original y no cambian MAL.</p>':''}<div class="episode-selection"><label>Rango de capítulos<input id="episode-range" class="form-input" placeholder="1-12, 14, 20.5" aria-describedby="range-help"></label><button class="button small ghost" data-exp="select-range">Elegir rango</button><button class="button small ghost" data-exp="select-unwatched">Sin ver</button><button class="button small ghost" data-exp="select-available">No descargados</button><button class="button small ghost" data-exp="select-clear">Limpiar selección</button></div><p class="muted" id="range-help">Solo se seleccionan capítulos disponibles para preparar. La selección se conserva entre páginas.</p><p data-selection-count role="status">${episodeSelectionIds().length} seleccionados</p><div class="episodes-grid">${episodeTiles(eps.slice((page-1)*36,page*36))}</div><nav class="queue-pagination" aria-label="Páginas de capítulos"><button class="button ghost" data-exp="episodes-page" data-page="${page-1}" ${page===1?'disabled':''}>Anterior</button><span>${page} / ${pages} · ${eps.length} capítulos</span><button class="button ghost" data-exp="episodes-page" data-page="${page+1}" ${page===pages?'disabled':''}>Siguiente</button></nav></section>`;
}
function refreshEpisodePage(){const node=document.getElementById('detail-episodes');if(node&&detailState){node.outerHTML=detailEpisodesView(detailState.episodes);updateDownloadUI();}}
async function previewQueue(slugs,mode,ids){
  const user=state.user?.id,ticket=dialogTicket(),request=++experienceRequest;
  const r=await api('queue_preview',{slugs,mode,episode_ids:ids});if(state.user?.id!==user||request!==experienceRequest||!dialogCurrent(ticket))return [];
  const p=r.preview;modal(`<p class="eyebrow">REVISAR SELECCIÓN</p><h2>Preparar ${p.eligible} capítulos</h2><p>${p.requested} solicitados · ${p.queued} ya preparados · ${p.downloaded} descargados · ${p.excluded} excluidos.</p><p>${e(p.server)} · ${e(p.language)} · ${p.height}p preferido. Se aplican tus alternativas de calidad, idioma y servidor.</p><ul>${p.sample.map(s=>`<li>${e(s.title)} · capítulo ${e(s.number)}</li>`).join('')}</ul>${p.eligible>p.sample.length?'<p>Y el resto de la selección.</p>':''}<div class="toolbar"><button class="button primary" data-exp="preview-confirm" ${!p.eligible?'disabled':''}>Confirmar y enviar a la PC</button><button class="button ghost" data-action="close">Cancelar</button></div>`);
  return new Promise(resolve=>{
    const dialog=document.getElementById('dialog');let done=false;
    const finish=value=>{if(done)return;done=true;dialog.removeEventListener('close',closed);dialog.removeEventListener('click',clicked);resolve(state.user?.id===user?value:[]);};
    const closed=()=>finish([]),clicked=event=>{if(event.target.closest('[data-exp="preview-confirm"]')){finish(p.episode_ids);dialog.close();}};
    dialog.addEventListener('close',closed,{once:true});dialog.addEventListener('click',clicked);
  });
}
function acceptExperienceResult(result,user){if(user!==(state.user?.id||0)||Number(result.presence_user_id)!==Number(user))return;for(const row of result.file_presence||[])filePresence.set(`${user}:${row.device_id}:${row.job_id}`,row);}
function presenceFor(job){return filePresence.get(`${state.user?.id}:${bridge.info?.device?.id}:${job.id}`);}
function filePresenceMarkup(job){
  if(job.status!=='confirmed')return '';const p=presenceFor(job),label=!p?'Historial · archivo sin comprobar':Number(p.present)===1?'Archivo presente en esta PC':Number(p.present)===0?'Archivo ausente o con tamaño distinto':'Sin registro en esta PC';
  return `<p class="file-presence">${e(label)}${p?` · ${e(dateText(Number(p.checked_at)))}`:''}</p>${p&&Number(p.present)!==1?`<button class="button small ghost" data-exp="redownload" data-id="${job.id}">Descargar expresamente</button>`:''}`;
}
function queueGroupControls(group){const supported=bridge.connected&&bridge.supports('group_control');return `<section class="panel queue-group-controls"><h2 class="panel-title">Control en tu PC</h2><p>${e(bridge.info?.device?.name||'Equipo sin identificar')} · App ${e(bridge.info?.version||'sin comprobar')} · Web 2026.10.18</p><p data-group-compat class="form-error" ${supported?'hidden':''}>Actualiza AnimeAV1 Plus a 2026.10.18.1 o posterior y conecta la app para usar controles por anime.</p><div class="toolbar">${['pause','resume','retry'].map((a,i)=>`<button class="button ghost" data-exp="group-control" data-command="${a}" data-slug="${e(group.slug)}" ${supported?'':'disabled'}>${['Pausar anime','Continuar anime','Reintentar fallidos'][i]}</button>`).join('')}<label>Prioridad<select id="group-priority" class="select-input" data-slug="${e(group.slug)}" ${supported?'':'disabled'}>${[[-10,'Baja'],[0,'Normal'],[10,'Alta']].map(([v,t])=>`<option value="${v}">${t}</option>`).join('')}</select></label><button class="button ghost" data-exp="check-files" data-slug="${e(group.slug)}" ${bridge.connected&&bridge.supports('file_presence')?'':'disabled'}>Comprobar archivos en esta PC</button></div><p class="muted">La prioridad se aplica al elegir el siguiente anime. Pausar conserva los parciales. Una pausa global de la app se mantiene. El historial de descarga no garantiza que el archivo siga presente.</p></section>`;}
async function groupCommand(slug,action,extra={}){
  if(!bridge.supports('group_control'))throw new Error('Actualiza la app de escritorio.');
  const ids=state.jobs.filter(j=>j.slug===slug&&liveJobs.has(Number(j.id))).map(j=>Number(j.id));if(!ids.length)throw new Error('Primero envía este anime a la PC y espera su estado.');
  await bridge.control(state.installation,ids,action,extra);scheduleResults(100);toast('Control aplicado en la PC.');
}
async function loadFilePresence(slug){const user=state.user?.id;await api('presence',{slug},true);if(user===state.user?.id)updateDownloadUI();}
async function checkFiles(slug){
  if(queueHistoryLoads.get(`${state.user?.id}:${slug}`)?.busy)throw new Error('Espera a que termine de cargar el historial.');
  await ensureQueueHistory(slug);const user=state.user?.id,ids=state.jobs.filter(j=>j.slug===slug&&j.status==='confirmed').map(j=>Number(j.id));
  for(let start=0;start<ids.length;start+=500){const r=await bridge.files(state.installation,ids.slice(start,start+500));if(state.user?.id!==user)return;await api('file_presence',{device_id:r.device.id,items:r.items});}
  if(state.user?.id===user){render();toast('Comprobación terminada. No se han descargado archivos.');}
}
async function batchMatches(page=1){const user=state.user?.id,ticket=dialogTicket(),request=++experienceRequest,r=await api('mal_match_batch',{page});if(user!==state.user?.id||request!==experienceRequest||!dialogCurrent(ticket))return;const b=r.match_batch;
  modal(`<p class="eyebrow">COINCIDENCIAS MAL</p><h2>Revisar vínculos por lotes</h2><p>Comprueba temporada, formato y total. No se vincula nada automáticamente. Las coincidencias aproximadas requieren revisión.</p><form id="batch-matches" data-account="${b.mal_account_id}">${b.items.map(m=>`<label class="batch-match"><strong>${e(m.title)}</strong><span>MAL · ${e(m.media_type)} · ${e(m.start_date||'sin fecha')} · ${Number(m.num_episodes)||'?'} capítulos</span><select class="select-input" name="${m.mal_id}"><option value="">Sin vincular</option>${m.candidates.map(a=>`<option value="${e(a.slug)}">${e(a.title)} · ${e(a.category)} · ${e(a.season||a.start_date||'sin temporada')} · ${a.catalog_complete?a.episodes:'?'} cap. · ${a.match_score}%${a.compatible?'':' · revisar formato/fecha'}</option>`).join('')}</select></label>`).join('')||'<p>No quedan coincidencias pendientes.</p>'}<div class="toolbar"><button class="button primary" type="submit" ${b.items.length?'':'disabled'}>Guardar vínculos elegidos</button><button type="button" class="button ghost" data-exp="batch-page" data-page="${b.page+1}" ${b.page>=b.pages?'disabled':''}>Omitir página</button><span>${b.page} / ${b.pages}</span></div></form>`);
}
document.addEventListener('click',async event=>{
  const b=event.target.closest('[data-exp]');if(!b)return;const action=b.dataset.exp;if(action==='preview-confirm')return;
  event.preventDefault();event.stopImmediatePropagation();const user=state.user?.id;b.disabled=true;
  try{
    if(action==='episodes-page'){episodePages.set(`${user||0}:${detailState.anime.slug}`,Number(b.dataset.page));refreshEpisodePage();}
    if(action.startsWith('select-')){const eps=detailState.episodes,set=episodeSelection();if(action==='select-clear')set.clear();else{let matches=eps;
      if(action==='select-range'){const text=document.getElementById('episode-range').value;if(!/^\s*\d+(?:\.\d+)?(?:\s*-\s*\d+(?:\.\d+)?)?(?:\s*,\s*\d+(?:\.\d+)?(?:\s*-\s*\d+(?:\.\d+)?)?)*\s*$/.test(text))throw new Error('Usa un rango como 1-12, 14, 20.5.');const ranges=text.split(',').map(part=>part.split('-').map(Number));if(ranges.some(([a,z=a])=>z<a))throw new Error('El final del rango debe ser mayor que el inicio.');matches=eps.filter(ep=>ranges.some(([a,z=a])=>Number(ep.number)>=a&&Number(ep.number)<=z));}
      if(action==='select-unwatched')matches=eps.filter(ep=>!(detailState.watch_mode?.mode==='rewatch'?ep.rewatched:ep.watched));for(const ep of matches)if(episodeCanPrepare(ep))set.add(Number(ep.id));}refreshEpisodePage();}
    if(action==='watch-mode'){if(!await experienceConfirm(b.dataset.mode==='rewatch'?'¿Iniciar un revisionado separado? Se cancelarán envíos pendientes de este anime y se conservará el progreso original de MAL.':'¿Volver al seguimiento original?'))return;await api('watch_mode',{slug:b.dataset.slug,mode:b.dataset.mode});if(user===state.user?.id)await openPlayer(playerView.episode.id);}
    if(action==='reconcile'){const a=detailState?.anime;if(!a?.mal)return;modal(`<h2>Reconciliar progreso</h2><p>Último dato consultado de MAL: ${a.mal.watched} capítulos. Consulta de nuevo tu lista MAL antes de continuar si cambió allí. Web → MAL usa el capítulo entero más avanzado marcado en la web, incluso si existen huecos.</p><p>Una corrección cancela envíos pendientes y exige reabrir reproductores antiguos. Las descargas se conservan.</p><div class="toolbar"><button class="button ghost" data-exp="reconcile-confirm" data-direction="mal_to_web" data-slug="${e(a.slug)}">MAL → web</button><button class="button danger" data-exp="reconcile-confirm" data-direction="web_to_mal" data-slug="${e(a.slug)}">Web → MAL</button></div>`);}
    if(action==='reconcile-confirm'){if(!await experienceConfirm('¿Aplicar esta corrección de progreso?'))return;await api('progress_reconcile',{slug:b.dataset.slug,direction:b.dataset.direction,confirmation:'CORREGIR',mal_account_id:Number(featureHome?.mal?.profile?.id)||undefined});if(user===state.user?.id)await showDetail(b.dataset.slug);}
    if(action==='batch'||action==='batch-page')await batchMatches(Number(b.dataset.page)||1);
    if(action==='group-control')await groupCommand(b.dataset.slug,b.dataset.command);
    if(action==='check-files')await checkFiles(b.dataset.slug);
    if(action==='redownload'){const job=state.jobs.find(j=>Number(j.id)===Number(b.dataset.id)),p=job&&presenceFor(job);if(!p||Date.now()/1000-Number(p.checked_at)>600)throw new Error('Comprueba primero el archivo en esta PC.');const other=Number(p.present)===-1;
      if(!await experienceConfirm(other?'Esta PC no tiene registro de la descarga. ¿Descargar aquí aunque exista en otro equipo?':'El archivo falta en su ubicación o su tamaño cambió. ¿Autorizar su redescarga?'))return;
      await api('queue_redownload',{job_id:Number(job.id),device_id:bridge.info.device.id,confirmation:other?'OTRO_EQUIPO':'REDESCARGAR'});
      if(!other)await bridge.control(state.installation,[Number(job.id)],'redownload',{confirmation:'REDESCARGAR'});
      if(user===state.user?.id)await sendToPC([Number(job.id)]);
    }
  }catch(error){toast(error.message,true);}finally{b.disabled=false;}
});
document.addEventListener('change',event=>{
  const t=event.target;if(t.matches('.episode-select')){const set=episodeSelection();t.checked?set.add(Number(t.value)):set.delete(Number(t.value));updateDownloadUI();}
  if(t.id==='group-priority')groupCommand(t.dataset.slug,'priority',{priority:Number(t.value)}).catch(error=>toast(error.message,true));
});
document.addEventListener('submit',async event=>{const f=event.target;if(f.id!=='batch-matches')return;event.preventDefault();event.stopImmediatePropagation();const user=state.user?.id;const pairs=[...new FormData(f)].filter(([,slug])=>slug).map(([id,slug])=>({mal_id:Number(id),slug}));try{await api('mal_link_batch',{mal_account_id:Number(f.dataset.account),pairs});if(user===state.user?.id)await batchMatches();}catch(error){toast(error.message,true);}});

function updateGroupControls(){
  const root=document.querySelector('.queue-group-controls');if(!root)return;
  const warning=root.querySelector('[data-group-compat]');if(warning)warning.hidden=bridge.connected&&bridge.supports('group_control');
  root.querySelectorAll('[data-exp="group-control"],#group-priority').forEach(el=>el.disabled=!bridge.connected||!bridge.supports('group_control'));
  const check=root.querySelector('[data-exp="check-files"]');if(check)check.disabled=!bridge.connected||!bridge.supports('file_presence');
  const select=root.querySelector('#group-priority');if(select&&select!==document.activeElement){const job=state.jobs.find(j=>j.slug===select.dataset.slug&&liveJobs.has(Number(j.id)));if(job)select.value=String(liveJobs.get(Number(job.id)).priority||0);}
  for(const job of state.jobs.filter(j=>j.status==='confirmed')){const tile=document.querySelector(`[data-queue-chapter="${Number(job.id)}"]`);if(tile){let holder=tile.querySelector('.file-presence-wrapper');if(!holder){holder=document.createElement('div');holder.className='file-presence-wrapper';tile.append(holder);}const html=filePresenceMarkup(job);if(holder.innerHTML!==html)holder.innerHTML=html;}}
}
