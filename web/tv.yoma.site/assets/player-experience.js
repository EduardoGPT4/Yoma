'use strict';
let nextEpisodeTimer=null, playerPreferenceTimer=null;
function cancelNextEpisode(){clearInterval(nextEpisodeTimer);nextEpisodeTimer=null;document.querySelector('.player-next')?.remove();}
function playerDiagnostic(kind,message){const el=document.querySelector(`[data-diagnostic="${kind}"]`);if(el)el.textContent=message;}
function playerExtraControls(p){
  cancelNextEpisode();const pref=p.playback?.preferences||{},mode=p.playback?.mode||'first';
  return `<div class="player-options"><label><input id="player-autonext" type="checkbox" ${pref.autoplay_next?'checked':''}> Siguiente automático (8 s)</label><label><input id="player-anime-prefs" type="checkbox" ${pref.anime_override?'checked':''}> Preferencias para este anime</label><button class="button small ghost" data-exp="watch-mode" data-slug="${e(p.episode.slug)}" data-mode="${mode==='rewatch'?'first':'rewatch'}">${mode==='rewatch'?'Revisionado · volver al original':'Iniciar revisionado'}</button></div><details class="player-diagnostics"><summary>Diagnóstico · ${mode==='rewatch'?'Revisionado sin modificar MAL':'Primer visionado'}</summary><dl><dt>Web</dt><dd>2026.10.18 · Reproducción 3</dd><dt>Servidor</dt><dd data-diagnostic="server">${e(p.servers[p.index]?.server||'No disponible')} · ${e(p.servers[p.index]?.language||'—')}</dd><dt>Extensión</dt><dd data-diagnostic="extension">Esperando conexión</dd><dt>Video</dt><dd data-diagnostic="video">Esperando información del video</dd><dt>MAL</dt><dd data-diagnostic="mal">${mode==='rewatch'?'Se conserva el progreso original':'Se enviará al alcanzar el 80 % de la posición'}</dd><dt>Posición</dt><dd data-diagnostic="position">Se guarda cada 10 s, al saltar, pausar y cerrar</dd></dl><p>La reanudación, el volumen y la velocidad requieren MP4Upload y la extensión. Otros servidores conservan sus controles propios.</p></details>`;
}
function savePlayerPreferences(p,values){
  if(playerView!==p)return;
  p.playback.preferences={...p.playback.preferences,...values};
  clearTimeout(playerPreferenceTimer);
  const user=state.user?.id;
  playerPreferenceTimer=setTimeout(async()=>{
    if(state.user?.id!==user)return;
    try{await api('player_settings',{slug:p.episode.slug,settings:Object.fromEntries(Object.entries(p.playback.preferences).filter(([key])=>['volume','muted','rate','autoplay_next','server','language'].includes(key))),anime_override:p.playback.preferences.anime_override===true});}
    catch(error){if(playerView===p)playerDiagnostic('position',`Preferencias sin guardar: ${error.message}`);}
  },350);
}
function rememberPlayerServer(p,index){const m=p.servers[index];if(m)savePlayerPreferences(p,{server:m.server,language:m.language});}
function playerExperience(p){
  p.saveSequence=p.saveSequence||0;let lastAt=0,lastPosition=null,lastPaused=true;
  const user=state.user?.id;
  return {
    resumePosition:p.playback?.position||0,preferences:p.playback?.preferences||{},
    onPreference:values=>savePlayerPreferences(p,values),
    onPosition:(s,force=false)=>{
      if(state.user?.id!==user||!p.playback)return;
      const now=Date.now();
      const due=force||now-lastAt>=10000||(lastPosition!==null&&Math.abs(s.position-lastPosition)>12)||(!lastPaused&&s.paused)||s.ended;
      lastPaused=s.paused;if(!due)return;lastAt=now;lastPosition=s.position;
      p.playback.position=s.position;p.playback.duration=s.duration;
      api('player_save',{episode_id:p.episode.id,position:s.position,duration:s.duration,mode:p.playback.mode,revision:p.playback.revision,session_key:p.playback.session_key,sequence:++p.saveSequence})
        .then(r=>{if(playerView===p)playerDiagnostic('position',r.position_saved?'Posición guardada':'Hay otra sesión más reciente; esta posición no la sobrescribe');})
        .catch(error=>{if(playerView===p)playerDiagnostic('position',`No guardada: ${error.message}`);});
    },
    onEnded:()=>{
      cancelNextEpisode();if(!p.playback?.preferences?.autoplay_next||document.hidden||playerView!==p)return;
      const index=p.chapters.findIndex(ep=>Number(ep.id)===Number(p.episode.id)),next=p.chapters[index+1];if(!next)return;
      let seconds=8;const node=document.createElement('div');node.className='player-next';node.setAttribute('role','status');
      node.innerHTML='<span></span><button type="button">Cancelar</button>';node.querySelector('button').onclick=cancelNextEpisode;document.querySelector('.video-stage')?.append(node);
      const update=()=>{node.querySelector('span').textContent=`Capítulo ${next.number} en ${seconds} s`;};update();
      nextEpisodeTimer=setInterval(()=>{if(document.hidden||playerView!==p||!node.isConnected){cancelNextEpisode();return;}seconds--;update();if(seconds<=0){cancelNextEpisode();openPlayer(Number(next.id)).catch(err=>toast(err.message,true));}},1000);
    }
  };
}
document.addEventListener('change',event=>{
  const p=playerView;if(!p)return;
  if(event.target.id==='player-autonext'){savePlayerPreferences(p,{autoplay_next:event.target.checked});if(!event.target.checked)cancelNextEpisode();}
  if(event.target.id==='player-anime-prefs')savePlayerPreferences(p,{anime_override:event.target.checked});
});
document.addEventListener('visibilitychange',()=>{if(document.hidden)cancelNextEpisode();});
document.getElementById('dialog').addEventListener('close',cancelNextEpisode);
