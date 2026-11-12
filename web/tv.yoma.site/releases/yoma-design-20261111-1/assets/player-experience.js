'use strict';
let nextEpisodeTimer=null, playerPreferenceTimer=null;
function cancelNextEpisode(){clearInterval(nextEpisodeTimer);nextEpisodeTimer=null;document.querySelector('.player-next')?.remove();}
function playerDiagnostic(kind,message){const el=document.querySelector(`[data-diagnostic="${kind}"]`);if(el)el.textContent=message;}
function savePlayerPreferences(p,values){
  if(playerView!==p)return;
  p.playback.preferences={...p.playback.preferences,...values,autoplay_next:true,anime_override:false};
  clearTimeout(playerPreferenceTimer);
  const user=state.user?.id;
  playerPreferenceTimer=setTimeout(async()=>{
    if(state.user?.id!==user)return;
    try{await api('player_settings',{slug:p.episode.slug,settings:Object.fromEntries(Object.entries(p.playback.preferences).filter(([key])=>['volume','muted','rate','server','language'].includes(key)))});}
    catch(error){if(playerView===p)toast(`Preferencias sin guardar: ${error.message}`,true);}
  },350);
}
function rememberPlayerServer(p,index){const m=p.servers[index];if(m)savePlayerPreferences(p,{server:m.server,language:m.language});}
function playerExperience(p){
  p.saveSequence=p.saveSequence||0;let lastAt=0,lastPosition=null,lastPaused=true;
  const user=state.user?.id;
  return {
    intro:p.personal?.intro||null,resumePosition:p.playback?.duration>0&&p.playback.position>=p.playback.duration-5?0:p.playback?.position||0,preferences:p.playback?.preferences||{},
    onPreference:values=>savePlayerPreferences(p,values),
    onPosition:(s,force=false)=>{
      if(state.user?.id!==user||!p.playback)return;
      maybePrefetchNext(p,s);
      const now=Date.now();
      const due=force||now-lastAt>=10000||(lastPosition!==null&&Math.abs(s.position-lastPosition)>12)||(!lastPaused&&s.paused)||s.ended;
      lastPaused=s.paused;if(!due)return;lastAt=now;lastPosition=s.position;
      p.playback.position=s.position;p.playback.duration=s.duration;
      api('player_save',{episode_id:p.episode.id,position:s.position,duration:s.duration,mode:p.playback.mode,revision:p.playback.revision,session_key:p.playback.session_key,sequence:++p.saveSequence})
        .then(r=>{if(state.user?.id===user&&typeof loadFeatureHome==='function'&&view==='discover'&&r.position_saved)loadFeatureHome(false).catch(()=>{});if(playerView===p){p.positionErrorShown=false;if(!r.position_saved&&!p.positionConflictShown){p.positionConflictShown=true;toast('Este capítulo se abrió en otra sesión. Reábrelo aquí para seguir guardando tu posición.',true);}}})
        .catch(error=>{if(playerView===p&&!p.positionErrorShown){p.positionErrorShown=true;toast(`No se pudo guardar tu posición: ${error.message}`,true);}});
    },
    onEnded:()=>{
      cancelNextEpisode();if(state.user?.id!==user||playerView!==p||document.getElementById('dialog').open)return;
      const index=p.chapters.findIndex(ep=>Number(ep.id)===Number(p.episode.id)),next=p.chapters[index+1];if(!next)return;
      const deadline=Date.now()+8000;let seconds=8;const node=document.createElement('div');node.className='player-next';node.setAttribute('role','status');
      node.innerHTML='<span></span><button type="button">Cancelar</button>';node.querySelector('button').onclick=cancelNextEpisode;document.querySelector('.video-stage')?.append(node);
      const update=()=>{node.querySelector('span').textContent=`Capítulo ${next.number} en ${seconds} s`;};update();
      nextEpisodeTimer=setInterval(()=>{if(state.user?.id!==user||playerView!==p||document.getElementById('dialog').open||!node.isConnected){cancelNextEpisode();return;}seconds=Math.max(0,Math.ceil((deadline-Date.now())/1000));update();if(seconds<=0){cancelNextEpisode();openPlayer(Number(next.id),{autoplay:true}).catch(err=>toast(err.message,true));}},1000);
    }
  };
}
document.getElementById('dialog').addEventListener('close',cancelNextEpisode);
