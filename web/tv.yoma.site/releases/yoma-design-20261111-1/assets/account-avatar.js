'use strict';
globalThis.YomaAvatar = (() => {
  let owner=0,status=null,epoch=0,busy=false,retryAt=0;
  const failed=new Set();
  const user=()=>Number(typeof state==='undefined'?0:state?.user?.id||0);
  function picture(value){
    if(typeof value!=='string'||value.length>2048||/[\s\\]/.test(value))return '';
    try{const u=new URL(value);return u.protocol==='https:'&&u.hostname==='cdn.myanimelist.net'&&!u.username&&!u.password&&!u.port&&!u.hash?u.href:'';}catch{return '';}
  }
  const current=()=>owner===user()&&owner>0?status:null;
  function url(){const mal=current();const value=mal?.connected?picture(mal.profile?.picture):'';return failed.has(value)?'':value;}
  function contents(name){
    const initial=e(String(name||'S').slice(0,1).toUpperCase()),src=url();
    return `<span class="avatar-initial" aria-hidden="true">${initial}</span>${src?`<img src="${e(src)}" alt="" decoding="async" referrerpolicy="no-referrer">`:''}`;
  }
  function html(name){return `<span class="avatar" data-account-avatar>${contents(name)}</span>`;}
  function update(){
    const name=typeof state==='undefined'?'':state?.user?.name||'';
    document.querySelectorAll('[data-account-avatar]').forEach(node=>{const markup=contents(name);if(node.innerHTML!==markup)node.innerHTML=markup;});
  }
  function reset(){owner=0;status=null;epoch++;busy=false;retryAt=0;failed.clear();update();}
  function accept(result,ticket,action){
    if(ticket!==epoch)return;
    const id=user();if(!id){reset();return;}
    const mal=result.mal||result.account?.mal||(Number(result.home?.user_id)===id?result.home.mal:null);
    if(!mal)return;
    if(action==='mal_disconnect'){epoch++;busy=false;retryAt=0;failed.clear();}
    if(status?.profile?.id===mal.profile?.id&&Number(status?.profile?.avatar_next_refresh)>Number(mal.profile?.avatar_next_refresh||0))
      mal.profile={...mal.profile,picture:status.profile.picture,avatar_next_refresh:status.profile.avatar_next_refresh};
    owner=id;status=mal;update();
    queueMicrotask(refresh);
  }
  async function refresh(){
    const mal=current(),id=user(),ticket=epoch;
    if(busy||!mal?.connected||!mal.profile||Number(mal.profile.avatar_next_refresh)>Date.now()/1000||retryAt>Date.now())return;
    busy=true;retryAt=Date.now()+600000;
    try{await api('mal_avatar',{},false,{timeout:20000});}
    catch{/* The initial or cached avatar remains usable when MAL is unavailable. */}
    finally{if(ticket===epoch&&id===user())busy=false;}
  }
  document.addEventListener('season-account-reset',reset);
  document.addEventListener('error',event=>{
    const image=event.target;
    if(image?.tagName==='IMG'&&image.parentElement?.hasAttribute('data-account-avatar')){
      failed.add(image.getAttribute('src'));image.remove();
    }
  },true);
  return {html,url,status:current,accept,reset,ticket:()=>epoch};
})();
