((nativeLayout) => {
  'use strict';
  if (window.__seasonNative || !window.YomaAndroid || location.origin !== 'https://hk-br035.gt.tc' || !location.pathname.startsWith('/seasonav1/')) return;
  window.__seasonNative = true;window.YomaNativeOnline = true;document.documentElement.classList.add('yoma-native');
  const animeBrand = /*YOMA_ANIME_BRAND*/;
  const post = data => YomaAndroid.postMessage(JSON.stringify(data));
  let previousAuth = '', previousRoute = '', timer;
  if(document.head){
    const style=document.createElement('style');style.id='season-android-navigation';
    // Older shared styles use a flex row here; long server actions must fit phones.
    style.textContent=`.mobile-navigation{display:none!important}.footer{padding-bottom:24px!important}
      .yoma-native .watch-servers{display:grid;grid-template-columns:minmax(0,1fr);min-width:0;width:100%;box-sizing:border-box}
      .yoma-native .watch-servers>div{min-width:0;width:auto;max-width:100%;flex-wrap:wrap}
      .yoma-native .watch-servers .watch-server-notice{display:flex;flex-wrap:wrap;min-width:0;width:100%;margin:0}
      .yoma-native .watch-servers .watch-server-notice .button{min-width:0;max-width:100%;white-space:normal;flex:1;justify-content:center}
      .yoma-native .watch-servers .watch-external{justify-self:start;min-height:44px;display:inline-flex;align-items:center}
      .yoma-native .watch-servers .watch-server-notice p{width:100%;overflow-wrap:anywhere}` + (nativeLayout || '');
    document.head.append(style);
  }
  let suspended = false, nativeRendered=false;
  const hidden=Object.getOwnPropertyDescriptor(Document.prototype,'hidden');
  if(hidden?.get)Object.defineProperty(document,'hidden',{configurable:true,get:()=>suspended||hidden.get.call(document)});

  window.addEventListener('season-native-suspend', () => {
    if (suspended) return;
    suspended = true;
    if (typeof radio !== 'undefined') radio.pause();
    if(typeof playerController!=='undefined'&&playerController)playerController.post('pause');
    document.dispatchEvent(new Event('visibilitychange'));
  });
  window.addEventListener('season-native-resume', () => {
    if (!suspended) return;
    suspended = false;
    previousAuth='';document.dispatchEvent(new Event('visibilitychange'));update();
  });
  function update() {
    document.querySelectorAll('.brand > img').forEach(image => { if (image.src !== animeBrand) image.src = animeBrand; });
    if (suspended || typeof state === 'undefined' || !state) return;
    if(!nativeRendered&&typeof render==='function'){nativeRendered=true;render();}
    const mal=typeof YomaAvatar==='undefined'?state.mal:YomaAvatar.status();
    const auth = JSON.stringify({type:'auth',owner:Number(state.user?.id)||0,name:String(state.user?.name||''),mal:Boolean(mal?.connected),avatar:typeof YomaAvatar==='undefined'?'':YomaAvatar.url()});
    if (auth !== previousAuth) { previousAuth = auth; YomaAndroid.postMessage(auth); }
    const route=location.hash||'#discover';if(route!==previousRoute){previousRoute=route;post({type:'navigation',route});}
    const transport = document.querySelector('.watch-actions')||document.querySelector('.watch-transport');
    if (transport && !transport.querySelector('[data-native-offline]')) {
      const b = document.createElement('button'); b.type='button'; b.className='button primary'; b.dataset.nativeOffline='episode'; b.textContent='↓ Descargar'; transport.append(b);
    }
    const episodes = document.querySelector('#dialog .episodes-header');
    if (episodes && !episodes.querySelector('[data-native-offline]')) {
      const b = document.createElement('button'); b.type='button'; b.className='button small primary'; b.dataset.nativeOffline='anime'; b.textContent='↓ Capítulos para llevar'; episodes.append(b);
    }
  }
  new MutationObserver(() => { clearTimeout(timer); timer = setTimeout(update, 300); }).observe(document.documentElement, {childList:true,subtree:true});
  window.addEventListener('pageshow', () => { previousAuth=''; update(); });
  window.addEventListener('hashchange',update);
  document.addEventListener('visibilitychange', () => { if (!document.hidden) { previousAuth=''; update(); } });
  window.addEventListener('yoma-native-playback-return',event=>{
    if(Number(state?.user?.id)!==Number(event.detail?.owner))return;
    const id=Number(event.detail?.episode_id);
    if(id>0 && location.hash.startsWith('#watch/') && typeof openPlayer==='function')openPlayer(id,{fromRoute:true}).catch(error=>toast(error.message,true));
    if(typeof scheduleWatchPump==='function')scheduleWatchPump();
  });
  document.addEventListener('click', async event => {
    const account=event.target.closest('#account[data-action="account"]');
    if(account&&location.hash!=='#account'){
      event.preventDefault();event.stopImmediatePropagation();post({type:'account'});return;
    }
    const play=event.target.closest('[data-native-online]');
    if(play){
      event.preventDefault();event.stopImmediatePropagation();if(play.disabled)return;
      play.disabled=true;const owner=Number(state?.user?.id)||0,id=Number(playerView?.episode?.id),selected=playerView?.servers?.[playerView.index];
      try{
        if(!owner || !id || selected?.server!=='MP4Upload')throw new Error('Elige MP4Upload para abrir el reproductor de la app.');
        const result=await api('offline_plan',{episode_id:id,language:selected.language}),plan=result.offline_plan;
        if(Number(state?.user?.id)!==owner || Number(plan.owner)!==owner || Number(playerView?.episode?.id)!==id || playerView.servers[playerView.index]!==selected)throw new Error('La selección cambió. Vuelve a pulsar reproducir.');
        plan.episodes=plan.episodes.filter(ep=>Number(ep.episode_id)===id);
        post({...plan,type:'play_online',episode_id:id,server:'MP4Upload'});
      }catch(error){if(typeof toast==='function')toast(error.message,true);}
      finally{play.disabled=false;}
      return;
    }
    const b = event.target.closest('[data-native-offline]'); if (!b || b.disabled) return;
    event.preventDefault(); event.stopImmediatePropagation(); b.disabled = true;
    const owner = Number(state?.user?.id)||0;
    try {
      if (!owner) throw new Error('Inicia sesión antes de guardar capítulos en el celular.');
      let id;
      if (b.dataset.nativeOffline === 'episode') id = playerView?.episode?.id;
      else id = detailState?.episodes?.[0]?.id;
      if (!id && b.dataset.nativeOffline === 'anime') id = detailState?.anime?.episodes?.[0]?.id;
      if (!id) {
        const node = document.querySelector('#dialog [data-play]'); id = Number(node?.dataset.play);
      }
      if (!id) throw new Error('Actualiza el listado del anime antes de descargar.');
      const selectedLanguage = b.dataset.nativeOffline === 'episode' ? playerView?.servers?.[playerView.index]?.language : null;
      const language = String(selectedLanguage || state.settings?.language || 'SUB').toUpperCase();
      const result = await api('offline_plan', {episode_id:Number(id),language}), plan = result.offline_plan;
      if (Number(state?.user?.id) !== owner || Number(plan.owner) !== owner) throw new Error('La cuenta cambió; vuelve a elegir los capítulos.');
      if (b.dataset.nativeOffline === 'episode') plan.episodes = plan.episodes.filter(ep=>Number(ep.episode_id)===Number(id));
      post({...plan,type:'plan'});
    } catch (error) { if (typeof toast === 'function') toast(error.message,true); }
    finally { b.disabled = false; }
  }, true);
  update();
})(/*YOMA_NATIVE_LAYOUT*/);
