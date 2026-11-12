'use strict';
// Keep the fullscreen element connected while changing episodes or servers.
function mountWatchPage(markup){
  const main=document.getElementById('main'),old=main.querySelector('.watch-page'),stage=old?.querySelector('.video-stage');
  if(!old||!stage){main.innerHTML=markup;return;}
  const template=document.createElement('template');template.innerHTML=markup;
  const next=template.content.querySelector('.watch-page'),nextStage=next.querySelector('.video-stage');
  old.dataset.episode=next.dataset.episode;
  old.querySelector('.watch-heading').replaceWith(next.querySelector('.watch-heading'));
  const content=old.querySelector('.watch-content'),nextContent=next.querySelector('.watch-content');
  for(const node of [...content.children])if(node!==stage)node.remove();
  stage.replaceChildren(...nextStage.childNodes);
  for(const node of [...nextContent.children])if(node!==nextStage)content.append(node);
  old.querySelector('.watch-playlist').replaceWith(next.querySelector('.watch-playlist'));
}
function showPlayerTransition(){
  const stage=document.querySelector('.video-stage');if(!stage)return;
  stage.querySelector('.player-transition')?.remove();const node=document.createElement('div');node.className='player-transition';node.setAttribute('role','status');node.textContent='Preparando el siguiente capítulo…';stage.append(node);
}
