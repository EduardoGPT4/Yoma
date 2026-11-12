'use strict';
// Keep the real select (and its form/change handlers); replace only its popup.
(() => {
  let source=null,signature='',sheet=null,list=null,query=null,heading=null,options=[];
  const valid=node=>node?.matches?.('select:not([multiple]):not(:disabled)')&&node.size<=1;
  const stamp=node=>JSON.stringify([node.value,[...node.options].map(o=>[o.value,o.text,o.disabled,o.hidden,o.parentElement?.disabled])]);
  const normalize=value=>value.normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLocaleLowerCase();
  function close(){if(sheet?.open)sheet.close();}
  function init(){
    if(sheet)return;
    sheet=document.createElement('dialog');sheet.className='choice-sheet';sheet.setAttribute('aria-labelledby','choice-title');
    const header=document.createElement('header');heading=document.createElement('h2');heading.id='choice-title';
    const dismiss=document.createElement('button');dismiss.type='button';dismiss.className='choice-dismiss';dismiss.textContent='×';dismiss.setAttribute('aria-label','Cerrar opciones');dismiss.addEventListener('click',close);
    header.append(heading,dismiss);query=document.createElement('input');query.type='search';query.className='form-input';query.placeholder='Buscar una opción…';query.setAttribute('aria-label','Buscar entre las opciones');query.addEventListener('input',render);
    list=document.createElement('div');list.className='choice-options';list.setAttribute('role','listbox');list.setAttribute('aria-labelledby','choice-title');
    sheet.append(header,query,list);document.body.append(sheet);
    sheet.addEventListener('click',event=>{if(event.target!==sheet)return;const r=sheet.getBoundingClientRect();if(event.clientX<r.left||event.clientX>r.right||event.clientY<r.top||event.clientY>r.bottom)close();});
    sheet.addEventListener('close',()=>{const previous=source;source=null;options=[];typed='';list.replaceChildren();previous?.removeAttribute('aria-expanded');if(previous?.isConnected&&!previous.disabled)previous.focus({preventScroll:true});});
    new MutationObserver(()=>{if(source&&(!source.isConnected||!valid(source)||stamp(source)!==signature||source.closest('dialog:not([open])')))close();}).observe(document.body,{childList:true,subtree:true,attributes:true,attributeFilter:['disabled','open']});
  }
  function render(){
    const text=normalize(query.value);list.replaceChildren();let group='';
    for(const option of options){
      if(option.hidden||option.parentElement?.hidden||!normalize(option.text).includes(text))continue;
      const parent=option.parentElement,label=parent?.tagName==='OPTGROUP'?parent.label:'';
      if(label&&label!==group){const title=document.createElement('p');title.className='choice-group';title.textContent=label;list.append(title);}group=label;
      const button=document.createElement('button');button.type='button';button.className='choice-option';button.setAttribute('role','option');button.setAttribute('aria-selected',String(option.selected));button.tabIndex=option.selected?0:-1;button.disabled=option.disabled||Boolean(parent?.disabled);
      const caption=document.createElement('span');caption.textContent=option.text;const mark=document.createElement('span');mark.className='choice-mark';mark.setAttribute('aria-hidden','true');mark.textContent=option.selected?'✓':'';button.append(caption,mark);
      button.addEventListener('click',()=>{
        const target=source;if(!target?.isConnected||!valid(target)||stamp(target)!==signature){close();return;}
        const changed=target.value!==option.value;target.value=option.value;close();
        if(changed){target.dispatchEvent(new Event('input',{bubbles:true}));target.dispatchEvent(new Event('change',{bubbles:true}));}
      });list.append(button);
    }
    if(!list.children.length){const empty=document.createElement('p');empty.className='choice-empty';empty.textContent='No hay coincidencias.';list.append(empty);}
  }
  function open(node){
    if(!valid(node)||source===node&&sheet?.open)return;
    init();close();source=node;signature=stamp(node);options=[...node.options];
    const label=node.labels?.[0];heading.textContent=node.getAttribute('aria-label')||[...(label?.childNodes||[])].filter(n=>n.nodeType===3||n.nodeType===1&&n.tagName==='SPAN').map(n=>n.textContent).join(' ').trim()||'Elige una opción';
    query.value='';query.hidden=options.length<9;render();node.setAttribute('aria-expanded','true');sheet.showModal();
    const selected=list.querySelector('[aria-selected="true"]:not(:disabled)')||list.querySelector('button:not(:disabled)')||query;selected.tabIndex=0;selected.focus();
  }
  document.addEventListener('pointerdown',event=>{if(valid(event.target)&&event.button===0)event.preventDefault();},true);
  document.addEventListener('click',event=>{if(!valid(event.target))return;event.preventDefault();event.stopImmediatePropagation();open(event.target);},true);
  let typed='',typeTimer;
  document.addEventListener('keydown',event=>{
    if(sheet?.open){
      if(event.key==='Escape'){event.preventDefault();event.stopImmediatePropagation();close();return;}
      if(!sheet.contains(event.target)||event.target===query)return;
      const buttons=[...list.querySelectorAll('button:not(:disabled)')];let index=buttons.indexOf(document.activeElement);
      if(['ArrowDown','ArrowUp','Home','End'].includes(event.key)){event.preventDefault();event.stopPropagation();index=event.key==='Home'?0:event.key==='End'?buttons.length-1:(index+(event.key==='ArrowDown'?1:-1)+buttons.length)%buttons.length;buttons.forEach((b,i)=>b.tabIndex=i===index?0:-1);buttons[index]?.focus();}
      else if(event.key.length===1&&!event.ctrlKey&&!event.metaKey&&event.key!==' '){clearTimeout(typeTimer);typed+=normalize(event.key);typeTimer=setTimeout(()=>typed='',700);buttons.find(b=>normalize(b.textContent).startsWith(typed))?.focus();}
    }else if(valid(event.target)&&['Enter',' ','ArrowDown','ArrowUp','F4'].includes(event.key)){event.preventDefault();event.stopImmediatePropagation();open(event.target);}
  },true);
  document.addEventListener('season-account-reset',close);
  window.addEventListener('hashchange',close);window.addEventListener('pagehide',close);window.addEventListener('season-native-suspend',close);
})();
