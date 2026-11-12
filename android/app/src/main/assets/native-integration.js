((nativeLayout) => {
  'use strict';
  // Dominios de YomaTV y la ruta en la que vive en cada uno (lib/config/yoma_web.dart).
  const yomaRoot = {'https://tv.yoma.site': '/'}[location.origin];
  if (window.__seasonNative || !window.YomaAndroid || !yomaRoot || !location.pathname.startsWith(yomaRoot)) return;
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
    // Reproducir y descargar los hace la app (reproductor y cola local de
    // Flutter): no hace falta la cuenta web, solo saber qué anime y episodio.
    const fail=message=>{if(typeof toast==='function')toast(message,true);};
    // «Ver capítulo» en la ficha: el reproductor de la app, sin pedir la cuenta web.
    const watch=event.target.closest('#dialog [data-play]');
    const slug=detailState?.anime?.slug;
    if(watch&&!watch.disabled&&slug&&Number(watch.dataset.play)>0){
      event.preventDefault();event.stopImmediatePropagation();
      post({type:'open',action:'play',slug:String(slug),episode_id:Number(watch.dataset.play)});
      return;
    }
    const play=event.target.closest('[data-native-online]');
    if(play){
      event.preventDefault();event.stopImmediatePropagation();
      const episode=playerView?.episode;
      if(!episode?.slug||!Number(episode.id))return fail('Actualiza el episodio antes de reproducirlo.');
      post({type:'open',action:'play',slug:String(episode.slug),episode_id:Number(episode.id)});
      return;
    }
    const b = event.target.closest('[data-native-offline]'); if (!b || b.disabled) return;
    event.preventDefault(); event.stopImmediatePropagation();
    if (b.dataset.nativeOffline === 'episode') {
      const episode=playerView?.episode,selected=playerView?.servers?.[playerView.index];
      if(!episode?.slug||!Number(episode.id))return fail('Actualiza el episodio antes de descargarlo.');
      const language=String(selected?.language||state?.settings?.language||'SUB').toUpperCase();
      post({type:'open',action:'download',slug:String(episode.slug),episode_id:Number(episode.id),language});
    } else {
      const slug=detailState?.anime?.slug||detailState?.episodes?.[0]?.slug;
      if(!slug)return fail('Actualiza el listado del anime antes de descargar.');
      post({type:'open',action:'episodes',slug:String(slug)});
    }
  }, true);
  update();
})(/*YOMA_NATIVE_LAYOUT*/);
