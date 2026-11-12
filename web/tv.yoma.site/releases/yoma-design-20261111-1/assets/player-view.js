'use strict';
let playerRequestSequence=0,playerOpeningId=0,playerLoading=false,playerError='',playerReturnRoute='#discover',playerChapterPage=1,playerServerTimer=null;
const WATCH_PAGE_SIZE=60;
function watchRouteId(){const match=/^#watch\/([1-9][0-9]{0,9})$/.exec(location.hash);return match?Number(match[1]):0;}
function handleWatchRoute(){const id=watchRouteId();if(!id)return false;if(playerView?.episode.id!==id&&playerOpeningId!==id)openPlayer(id,{fromRoute:true}).catch(error=>toast(error.message,true));return true;}
function cancelPlayerServerRefresh(){if(playerServerTimer!==null)clearTimeout(playerServerTimer);playerServerTimer=null;}
function leavePlayerPage(){cancelPlayerServerRefresh();if(!playerView&&!playerLoading)return;playerRequestSequence++;playerOpeningId=0;playerLoading=false;playerController?.destroy();playerController=null;cancelNextEpisode();playerView=null;}
function watchPage(){
  if(!state.user)return empty('Tu sala de anime','Inicia sesión para ver capítulos y sincronizar tu progreso con MyAnimeList.',button('account','Iniciar sesión','play','','primary'),'play');
  return `<section class="watch-loading"><p class="eyebrow">TU SALA DE ANIME</p>${playerLoading?'<span class="spinner"></span><h1>Preparando tu capítulo…</h1>':`<h1>${e(playerError||'Elige un capítulo para empezar.')}</h1>${watchRouteId()?`<button class="button primary" data-play="${watchRouteId()}">Volver a intentar</button>`:''}`}<a class="button ghost" href="#discover">Volver al catálogo</a></section>`;
}
async function openPlayer(id,{fromRoute=false,autoplay=false}={}){
  if(!Number.isSafeInteger(id)||id<1)throw new Error('Capítulo no válido.');if(!requireUser())return;
  if(view!=='watch')playerReturnRoute=location.hash.startsWith('#watch/')?'#discover':location.hash||'#discover';
  cancelPlayerServerRefresh();playerController?.destroy();playerController=null;cancelNextEpisode();captureDetailDraft();
  if($('#dialog').open){$('#dialog-body').replaceChildren();$('#dialog').close();}
  radio.pause('En pausa mientras ves un capítulo.');
  playerView=null;playerLoading=true;playerOpeningId=id;playerError='';view='watch';
  if(!fromRoute||location.hash!==`#watch/${id}`)history[autoplay?'replaceState':'pushState'](null,'',`#watch/${id}`);
  const seq=++playerRequestSequence,user=state.user.id;if(!document.querySelector('.video-stage'))render();else showPlayerTransition();sidebarNavigation.closeMobile();
  try{
    const r=await api('player',{episode_id:id});
    if(seq!==playerRequestSequence||state.user?.id!==user||view!=='watch'||watchRouteId()!==id)return;
    playerView=r.player;playerView.autoplay=autoplay;playerLoading=false;playerOpeningId=0;
    selectPlayerServer(playerView);
    playerChapterPage=Math.floor(Math.max(0,playerView.chapters.findIndex(ep=>Number(ep.id)===id))/WATCH_PAGE_SIZE)+1;
    renderPlayer();if(pendingPlayerTask(playerView))pollPlayerTask(playerView);document.querySelector('#watch-heading')?.focus({preventScroll:true});window.scrollTo({top:0,behavior:'auto'});
    if(!playerView.servers.length&&playerView.server_refresh?.can_refresh&&playerView.server_refresh.state==='stale')refreshPlayerServers(playerView);
  }catch(error){if(seq!==playerRequestSequence||user!==state.user?.id)return;playerLoading=false;playerOpeningId=0;playerError=error.message;render();}
}
function watchServerNotice(p){
  const r=p.server_refresh||{},pending=['pending','running'].includes(p.update_task?.state),waiting=r.state==='waiting'&&Number(r.retry_at)>Date.now()/1000;
  const message=p.serverBusy?'Consultando servidores…':r.message||(!p.servers.length&&pending?'La actualización está solicitada. Vuelve a comprobarla después de que termine el mantenimiento.':'');
  return `<div class="watch-server-notice" data-watch-server-notice role="status">${message?`<p>${e(message)}${waiting?` Próximo intento: ${e(new Date(r.retry_at*1000).toLocaleTimeString([],{hour:'2-digit',minute:'2-digit'}))}.`:''}</p>`:''}<button class="button small ghost" type="button" data-watch="refresh" ${p.serverBusy||waiting||!r.can_refresh&&pending?'disabled':''}>${icon('refresh')}${r.can_refresh?'Actualizar servidores':'Solicitar servidores'}</button></div>`;
}
function updateServerNotice(p){const node=document.querySelector('[data-watch-server-notice]');if(node&&playerView===p)node.outerHTML=watchServerNotice(p);}
async function refreshPlayerServers(p=playerView){
  if(!p||p!==playerView||p.serverBusy)return;
  cancelPlayerServerRefresh();const user=state.user?.id;p.serverBusy=true;updateServerNotice(p);
  try{
    if(!p.server_refresh?.can_refresh){
      const r=await api('catalog_request',{slug:p.episode.slug,episode_id:Number(p.episode.id)},false,{assignDetail:false});
      if(playerView!==p||state.user?.id!==user)return;
      p.update_task=r.task;p.server_refresh={...p.server_refresh,message:r.message};if(r.task?.state==='done')await loadCachedPlayerServers(p);else pollPlayerTask(p);
    }else{
      const r=await api('player_servers',{episode_id:Number(p.episode.id)});
      if(playerView!==p||state.user?.id!==user)return;
      const current=p.servers[p.index],data=r.player_servers;
      Object.assign(p,data);
      selectPlayerServer(p,current);
      if(!current&&p.servers.length)renderPlayer();
      else if(current){const buttons=document.querySelector('.watch-server-groups');if(buttons)buttons.innerHTML=watchServerButtons(p);}
      if(data.server_refresh?.state==='waiting')playerServerTimer=setTimeout(()=>{playerServerTimer=null;if(playerView===p&&state.user?.id===user&&view==='watch')refreshPlayerServers(p);},Math.max(1000,Math.min(3600000,data.server_refresh.retry_at*1000-Date.now()+250)));
    }
  }catch(error){if(playerView===p&&state.user?.id===user)p.server_refresh={...p.server_refresh,state:'error',message:error.message};}
  finally{p.serverBusy=false;if(playerView===p&&state.user?.id===user)updateServerNotice(p);}
}
async function loadCachedPlayerServers(p){
  const user=state.user?.id,r=await api('player_cached_servers',{episode_id:Number(p.episode.id)});
  if(playerView!==p||state.user?.id!==user)return;
  const current=p.servers[p.index];Object.assign(p,r.player_servers);selectPlayerServer(p,current);
  if(!current&&p.servers.length)renderPlayer();
  else {const buttons=document.querySelector('.watch-server-groups');if(buttons)buttons.innerHTML=watchServerButtons(p);updateServerNotice(p);}
}
function selectPlayerServer(p,current=null){
  const pref=p.playback?.preferences||{},rank=s=>Number(s.language===(pref.language||state.settings.language))*2+Number(s.server===(pref.server||state.settings.server));
  p.servers.sort((a,b)=>rank(b)-rank(a));
  if(current&&!p.servers.some(s=>s.url===current.url))p.servers.unshift(current);
  p.index=current?Math.max(0,p.servers.findIndex(s=>s.url===current.url)):0;
}
function watchServerButtons(p){
  const groups=new Map(),languages=['SUB','LAT','DUB'];
  p.servers.forEach((server,index)=>{
    const language=String(server.language||'OTRO').trim().toUpperCase()||'OTRO';
    if(!groups.has(language))groups.set(language,[]);
    groups.get(language).push({server,index});
  });
  const order=language=>languages.includes(language)?languages.indexOf(language):languages.length;
  return [...groups].sort(([a],[b])=>order(a)-order(b)||a.localeCompare(b)).map(([language,servers])=>{
    const title={SUB:'Subtitulado',LAT:'Español latino',DUB:'Doblado'}[language]||language;
    const symbol=language==='SUB'?'<rect x="3" y="5" width="18" height="14" rx="2"/><path d="M7 10h2m3 0h5M7 14h6m3 0h1"/>':'<rect x="9" y="2" width="6" height="12" rx="3"/><path d="M5 10v2a7 7 0 0 0 14 0v-2M12 19v3m-4 0h8"/>';
    return `<section class="watch-server-group" aria-label="${e(title)}"><span class="watch-server-label" title="${e(title)}"><svg viewBox="0 0 24 24" aria-hidden="true">${symbol}</svg>${e(language)}</span><div class="watch-server-options">${servers.map(({server:s,index:i})=>`<button type="button" class="watch-server ${i===p.index?'selected':''}" data-watch-server="${i}" aria-label="${e(s.server)} · ${e(language)}" aria-pressed="${i===p.index}">${e(s.server)}</button>`).join('')}</div></section>`;
  }).join('')||'<span class="muted">Sin servidores guardados</span>';
}
function playerMalConfirmed(p){return Boolean(p.mal?.connected&&p.mal?.linked&&p.mal?.confirmed)&&Number(p.episode.number)>=1&&Number.isInteger(Number(p.episode.number))&&(Number(p.mal?.watched)>=Number(p.episode.number)||p.watch_sync?.state==='synced'&&Number(p.watch_sync.target)>=Number(p.episode.number));}
function updatePlayerWatchBadge(status){const badge=document.querySelector('[data-player-watch-badge]'),labels={saving:'Guardando visto…',synced:'Visto en MAL',pending:'MAL pendiente',blocked:'Revisar conexión MAL',error:'No se pudo guardar',rewatched:'Revisionado guardado'};if(badge&&labels[status]){badge.textContent=labels[status];badge.dataset.state=status;badge.hidden=false;}updateWatchPage();}
function updateWatchPage(){
  const p=playerView;if(!p||view!=='watch')return;
  const confirmed=playerMalConfirmed(p),eye=document.querySelector('[data-watch="mark"]');
  if(eye){eye.disabled=Boolean(p.manualBusy||confirmed);eye.classList.toggle('confirmed',confirmed);eye.setAttribute('aria-label',p.manualBusy?'Guardando en MyAnimeList':confirmed?'Capítulo visto en MyAnimeList':'Marcar capítulo como visto en MyAnimeList');eye.title=eye.getAttribute('aria-label');eye.setAttribute('aria-busy',String(Boolean(p.manualBusy)));}
  for(const ep of p.chapters){const node=document.querySelector(`[data-watch-episode="${Number(ep.id)}"]`);if(node&&(node.dataset.seen!==String(episodeSeen(ep,p.mal))||node.dataset.current!==String(Number(ep.id)===Number(p.episode.id)))){const focused=node.contains(document.activeElement);node.outerHTML=watchChapterRow(p,ep);if(focused)document.querySelector(`[data-watch-toggle="${Number(ep.id)}"]`)?.focus({preventScroll:true});}}
}
function acceptPlayerMark(p,result){
  p.watch_sync=result;
  if(['synced','pending','blocked'].includes(result?.state)){const chapter=p.chapters.find(ep=>Number(ep.id)===Number(p.episode.id));if(chapter){chapter.watched=true;chapter.watched_override=null;}}
  if(result?.state==='synced')p.mal.watched=Math.max(Number(p.mal.watched)||0,Number(result.target)||Number(p.episode.number));
  if(playerView===p){updatePlayerWatchBadge(result?.state);const node=document.querySelector('[data-player-watch-status]');if(node&&result?.message){node.textContent=result.message;node.dataset.state=result.state;}}
}
async function markPlayerManually(){
  const p=playerView,user=state.user?.id;if(!p||p.manualBusy||playerMalConfirmed(p))return;p.manualBusy=true;updateWatchPage();
  try{
    const r=await api('watch_manual',{episode_id:p.episode.id,mal_account_id:p.mal_account_id,progress_revision:p.playback?.revision});
    if(state.user?.id!==user||playerView!==p)return;
    acceptPlayerMark(p,r.watch_sync);if(r.watch_sync?.state==='blocked'&&!p.mal?.confirmed)confirmPlayerMal(p);statsPage=null;malLibraryPage=null;scheduleWatchPump();
    if(r.watch_sync?.state==='synced'){if(playerController)playerController.notifySynced();else toast(`Capítulo ${p.episode.number} actualizado en MyAnimeList`);}else toast(r.watch_sync?.message||'Sincronización pendiente.');
  }catch(error){if(playerView===p&&state.user?.id===user)toast(error.message,true);}
  finally{p.manualBusy=false;if(playerView===p)updateWatchPage();}
}
function renderPlayer(){
  playerController?.destroy();playerController=null;
  const p=playerView;if(!p||view!=='watch')return;
  const m=p.servers[p.index],current=p.chapters.findIndex(ep=>Number(ep.id)===Number(p.episode.id)),a=p.anime||{},previous=p.chapters[current-1],next=p.chapters[current+1];
  const markup=watchPageTemplate(p);
  mountWatchPage(markup);
  $('#main').dataset.renderScope=`${state.user.id}:watch`;document.title=`Capítulo ${p.episode.number} · ${p.episode.title} · YomaTV`;
  if(playerMalConfirmed(p))updatePlayerWatchBadge('synced');else if(Number(p.watch_sync?.target)===Number(p.episode.number))updatePlayerWatchBadge(p.watch_sync.state);updateWatchPage();if(p.mal?.linked&&!p.mal.confirmed)offerPlayerMalConfirmation(p);
  if(m?.server==='MP4Upload'&&!nativeOnlinePlayer(p)&&typeof YomaTVPlayerController==='function'){
    const user=state.user.id,node=document.querySelector('[data-player-watch-status]');
    const nativeControls=typeof SeasonMobilePlayback!=='undefined'&&SeasonMobilePlayback.isMobile();
    playerController=new YomaTVPlayerController({stage:document.querySelector('.video-stage'),iframe:document.querySelector('iframe[data-season-player]'),episodeNumber:p.episode.number,autoplay:p.autoplay,...playerExperience(p),nativeControls,
      onStatus:(message,status,kind)=>{if(node.isConnected&&playerView===p){node.textContent=message;node.dataset.state=status;playerDiagnostic(kind||(['saving','synced','pending','blocked','rewatched'].includes(status)?'mal':'video'),message);updatePlayerWatchBadge(status);}},
      onExtension:(status,info)=>{playerDiagnostic('extension',`${({ready:'Conectada',detected:'Detectada',missing:'No detectada',update:'Actualización necesaria'})[status]||status} ${info?.extensionVersion||''}`);const help=document.querySelector('.player-extension-help');if(help&&playerView===p){help.hidden=nativeControls||status==='ready';help.title=status==='update'?'Actualizar extensión de Brave':'Ayuda de la extensión de Brave';help.setAttribute('aria-label',help.title);}},
      onThreshold:async telemetry=>{if(state.user?.id!==user)throw new Error('La sesión cambió.');const r=await api('watch_scrobble',{episode_id:p.episode.id,mal_account_id:p.mal_account_id,progress_revision:p.playback?.revision,...telemetry});if(state.user?.id!==user)return null;if(playerView===p){acceptPlayerMark(p,r.watch_sync);if(r.watch_sync?.state==='blocked'&&!p.mal?.confirmed)offerPlayerMalConfirmation(p);}statsPage=null;malLibraryPage=null;scheduleWatchPump();return r.watch_sync;}
    });
    if(p.chapters.find(ep=>Number(ep.id)===Number(p.episode.id))?.watched_override===false)playerController.setManualUnseen();
  }
}
document.addEventListener('click',async event=>{
  const b=event.target.closest('[data-watch],[data-watch-server],button[data-watch-page],[data-watch-related],[data-watch-toggle]');if(!b||b.disabled)return;event.preventDefault();event.stopImmediatePropagation();
  try{
    if(b.dataset.watchToggle!==undefined)await togglePlayerEpisode(b);
    else if(b.dataset.watch==='mark')await markPlayerManually();
    else if(b.dataset.watch==='fullscreen'){
      if(!await SeasonMobilePlayback.enterFullscreen(document.querySelector('.video-stage')))toast('Usa el botón de pantalla completa de MP4Upload. Este navegador no permite ampliarlo desde la página.');
    }
    else if(b.dataset.watch==='refresh')await refreshPlayerServers();
    else if(b.dataset.watch==='download'&&playerView)await queueItems([playerView.episode.slug],'selected',[Number(playerView.episode.id)]);
    else if(b.dataset.watch==='back'){const target=playerReturnRoute;leavePlayerPage();view=TITLES[target.slice(1).split(/[/?]/)[0]]&&!target.startsWith('#watch')?target.slice(1).split(/[/?]/)[0]:'discover';location.hash=target;render();}
    else if(b.dataset.watchServer!==undefined&&playerView){const index=Number(b.dataset.watchServer);if(!playerView.servers[index]||index===playerView.index)return;rememberPlayerServer(playerView,index);playerView.index=index;renderPlayer();}
    else if(b.dataset.watchPage&&playerView){playerChapterPage=Number(b.dataset.watchPage);document.querySelector('#watch-chapters').innerHTML=watchChapters(playerView);}
    else if(b.dataset.watchRelated&&playerView){playerView.relatedTab=b.dataset.watchRelated;document.querySelector('#watch-related').outerHTML=watchRelated(playerView);document.querySelector(`#watch-related-${playerView.relatedTab==='genres'?'genres':'saga'}-tab`)?.focus({preventScroll:true});}
  }catch(error){toast(error.message,true);}
});
async function togglePlayerEpisode(button){
  if(button.disabled)return;
  const p=playerView,user=state.user?.id,id=Number(button.dataset.watchToggle),ep=p?.chapters.find(ep=>Number(ep.id)===id);
  if(!p||!ep)return;const value=!episodeSeen(ep,p.mal);button.disabled=true;
  try{
    const result=await api('watched',{episode_id:id,watched:value,progress_revision:p.playback?.revision},false,{assignDetail:false});
    if(playerView!==p||state.user?.id!==user)return;
    ep.watched=value;ep.watched_override=value;
    if(!value&&id===Number(p.episode.id))playerController?.setManualUnseen();
    updateWatchPage();statsPage=null;toast(value?'Capítulo marcado como visto en YomaTV.':'Marca de visto retirada en YomaTV.');
  }catch(error){if(playerView===p&&state.user?.id===user)toast(error.message,true);}
  finally{if(button.isConnected)button.disabled=false;}
}
window.addEventListener('popstate',()=>{if(state)handleWatchRoute();});
