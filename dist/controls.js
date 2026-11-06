/* Progressive Mac controls: keep native form values and validation as the source of truth. */
(() => {
  if (document.documentElement.dataset.platform !== 'mac') return;
  const choices = new Map(), steppers = new Map();
  let active = null, serial = 0, scheduled = false;
  const chevron = '<svg viewBox="0 0 20 20" aria-hidden="true"><path d="m6 8 4 4 4-4"/></svg>';
  const labelFor = control => control.getAttribute('aria-label') || control.labels?.[0]?.querySelector('span')?.textContent.trim() || control.labels?.[0]?.textContent.trim() || 'Choose an option';
  function close(returnFocus = false) {
    if (!active) return;
    const item = active; active = null;
    item.button.setAttribute('aria-expanded','false');
    item.button.removeAttribute('aria-activedescendant');
    if (typeof item.menu.hidePopover === 'function') { try { item.menu.hidePopover(); } catch {} }
    item.menu.remove();
    item.menu = null;
    item.buffer = ''; item.typedAt = 0;
    if (returnFocus && item.button.isConnected && !item.button.disabled) item.button.focus({preventScroll:true});
  }
  function syncChoice(item) {
    const {source,button,text} = item;
    if (!source.isConnected) { if (active === item) close(); choices.delete(source); return; }
    const option = source.selectedOptions[0];
    const value = option?.textContent.trim() || 'Choose…';
    if (text.textContent !== value) text.textContent = value;
    if (button.disabled !== source.disabled) button.disabled = source.disabled;
    button.setAttribute('aria-label',`${item.label}: ${value}`);
    button.setAttribute('aria-required',String(source.required));
    if (source.validity.valid) button.removeAttribute('aria-invalid');
    item.shell.classList.toggle('is-disabled',source.disabled);
    if (source.disabled && active === item) close();
    if (active === item) drawMenu(item);
  }
  function position(item) {
    const rect = item.button.getBoundingClientRect(), gap = 7, padding = 12;
    const below = innerHeight - rect.bottom - padding - gap, above = rect.top - padding - gap;
    const height = Math.min(292, Math.max(80,below >= 150 || below >= above ? below : above));
    const width = Math.min(Math.max(rect.width,190),innerWidth-padding*2);
    item.menu.style.width = `${width}px`;
    item.menu.style.maxHeight = `${height}px`;
    item.menu.style.left = `${Math.max(padding,Math.min(rect.left,innerWidth-width-padding))}px`;
    const actualHeight = Math.min(item.menu.scrollHeight,height);
    item.menu.style.top = `${below >= 150 || below >= above ? rect.bottom+gap : Math.max(padding,rect.top-gap-actualHeight)}px`;
  }
  function highlight(item) {
    item.options.forEach((option,index) => option.node.classList.toggle('is-highlighted',index === item.cursor));
    const option = item.options[item.cursor];
    if (option) {
      item.button.setAttribute('aria-activedescendant',option.node.id);
      option.node.scrollIntoView({block:'nearest'});
    }
  }
  function choose(item,index) {
    const option = item.options[index];
    if (!option || option.source.disabled || option.source.parentElement?.disabled) return;
    const changed = item.source.selectedIndex !== option.index;
    item.source.selectedIndex = option.index;
    close(true); syncChoice(item);
    if (changed) {
      item.source.dispatchEvent(new Event('input',{bubbles:true}));
      item.source.dispatchEvent(new Event('change',{bubbles:true}));
    }
  }
  function drawMenu(item) {
    const prior = item.options?.[item.cursor]?.source;
    item.menu.replaceChildren(); item.options = [];
    let group = '';
    [...item.source.options].forEach((option,index) => {
      if (option.hidden) return;
      const parent = option.parentElement;
      if (parent?.tagName === 'OPTGROUP' && parent.label !== group) {
        group = parent.label;
        const title = document.createElement('div'); title.className = 'select-group-label'; title.textContent = group; item.menu.append(title);
      }
      const node = document.createElement('div');
      node.className = 'select-option'; node.id = `${item.id}-option-${index}`;
      node.setAttribute('role','option'); node.setAttribute('aria-selected',String(option.selected));
      node.setAttribute('aria-disabled',String(option.disabled || !!parent?.disabled));
      const label = document.createElement('span'); label.textContent = option.textContent.trim(); node.append(label);
      const mark = document.createElement('span'); mark.className = 'select-check'; mark.innerHTML = '<svg viewBox="0 0 20 20" aria-hidden="true"><path d="m5 10 3 3 7-7"/></svg>'; node.append(mark);
      const cursor = item.options.length;
      item.options.push({source:option,index,node});
      node.addEventListener('pointerdown',event=>event.preventDefault());
      node.addEventListener('pointermove',()=>{ if (node.getAttribute('aria-disabled') !== 'true') { item.cursor = cursor; highlight(item); } });
      node.addEventListener('click',()=>choose(item,cursor));
      item.menu.append(node);
    });
    item.cursor = item.options.findIndex(o=>o.source === prior);
    if (item.cursor < 0) item.cursor = item.options.findIndex(o=>o.source.selected && !o.source.disabled && !o.source.parentElement?.disabled);
    if (item.cursor < 0) item.cursor = item.options.findIndex(o=>!o.source.disabled && !o.source.parentElement?.disabled);
    if (!item.options.length) { const empty = document.createElement('p'); empty.className='select-empty'; empty.textContent='No options available'; item.menu.append(empty); }
    position(item); highlight(item);
  }
  function open(item) {
    if (item.source.disabled) return;
    if (active === item) return;
    close(); active = item;
    item.options = []; item.cursor = -1;
    const menu = document.createElement('div'); item.menu = menu;
    menu.id = item.id; menu.className = 'select-menu'; menu.setAttribute('role','listbox'); menu.setAttribute('aria-label',item.label);
    if (typeof menu.showPopover === 'function') menu.setAttribute('popover','manual');
    (item.source.closest('dialog[open]') || document.body).append(menu);
    item.button.setAttribute('aria-expanded','true');
    drawMenu(item);
    if (menu.hasAttribute('popover')) menu.showPopover();
    position(item); highlight(item);
  }
  function move(item,delta) {
    if (!item.options.length) return;
    let index = item.cursor;
    for (let n=0;n<item.options.length;n++) {
      index = (index+delta+item.options.length)%item.options.length;
      const option = item.options[index].source;
      if (!option.disabled && !option.parentElement?.disabled) { item.cursor=index; highlight(item); return; }
    }
  }
  function enhanceChoice(source) {
    if (source.multiple || source.size > 1) return;
    const shell = document.createElement('span'); shell.className='select-shell';
    source.before(shell); shell.append(source); source.classList.add('custom-select-source');
    source.tabIndex = -1; source.setAttribute('aria-hidden','true');
    const button=document.createElement('button'); button.type='button'; button.className='select-trigger';
    button.setAttribute('role','combobox'); button.setAttribute('aria-haspopup','listbox'); button.setAttribute('aria-expanded','false');
    const id=`select-list-${++serial}`; button.setAttribute('aria-controls',id);
    const text=document.createElement('span'); text.className='select-value'; button.append(text);
    const arrow=document.createElement('span'); arrow.className='select-chevron'; arrow.innerHTML=chevron; button.append(arrow); shell.append(button);
    const item={source,shell,button,text,id,label:labelFor(source),options:[],cursor:0,buffer:'',typedAt:0}; choices.set(source,item);
    button.addEventListener('click',()=>active===item?close(true):open(item));
    button.addEventListener('keydown',event=>{
      if (event.key==='Escape' && active===item) { event.preventDefault(); event.stopPropagation(); close(true); return; }
      if (event.key==='Tab') { close(); return; }
      if (event.key==='Enter' || (event.key===' ' && (!item.buffer || Date.now()-item.typedAt>700))) { event.preventDefault(); if(active===item)choose(item,item.cursor);else open(item); return; }
      if (['ArrowDown','ArrowUp','Home','End'].includes(event.key)) {
        event.preventDefault(); const wasOpen=active===item; open(item);
        if(event.key==='Home'){item.cursor=-1;move(item,1);}else if(event.key==='End'){item.cursor=0;move(item,-1);}else if(wasOpen)move(item,event.key==='ArrowDown'?1:-1);
        return;
      }
      if (event.key.length===1 && !event.metaKey && !event.ctrlKey && !event.altKey) {
        event.preventDefault(); const now=Date.now(); item.buffer=now-item.typedAt>700?event.key:item.buffer+event.key;item.typedAt=now;open(item);
        const index=item.options.findIndex(o=>!o.source.disabled&&!o.source.parentElement?.disabled&&o.source.textContent.trim().toLocaleLowerCase().startsWith(item.buffer.toLocaleLowerCase()));
        if(index>=0){item.cursor=index;highlight(item);}
      }
    });
    source.addEventListener('change',()=>syncChoice(item));
    source.addEventListener('invalid',()=>{button.setAttribute('aria-invalid','true');button.focus();});
    syncChoice(item);
  }
  function syncStepper(item) {
    if(!item.source.isConnected){steppers.delete(item.source);return;}
    const value=Number(item.source.value),min=item.source.min===''?-Infinity:Number(item.source.min),max=item.source.max===''?Infinity:Number(item.source.max);
    item.down.disabled=item.source.disabled||item.source.readOnly||(item.source.value!==''&&value<=min);
    item.up.disabled=item.source.disabled||item.source.readOnly||(item.source.value!==''&&value>=max);
    item.shell.classList.toggle('is-disabled',item.source.disabled);
  }
  function enhanceStepper(source) {
    const shell=document.createElement('span');shell.className='number-shell';source.before(shell);shell.append(source);
    const label=labelFor(source);
    const down=document.createElement('button'),up=document.createElement('button');
    down.type=up.type='button';down.className=up.className='stepper-button';down.textContent='−';up.textContent='+';
    down.setAttribute('aria-label',`Decrease ${label}`);up.setAttribute('aria-label',`Increase ${label}`);
    shell.prepend(down);shell.append(up);const item={source,shell,down,up};steppers.set(source,item);
    [[down,-1],[up,1]].forEach(([button,delta])=>button.addEventListener('click',()=>{
      if(source.disabled||source.readOnly)return;
      try{if(delta>0)source.stepUp();else source.stepDown();}catch{return;}
      source.dispatchEvent(new Event('input',{bubbles:true}));source.dispatchEvent(new Event('change',{bubbles:true}));syncStepper(item);
    }));
    source.addEventListener('input',()=>syncStepper(item));syncStepper(item);
  }
  function sync() {
    scheduled=false;
    document.querySelectorAll('select').forEach(source=>{if(!choices.has(source))enhanceChoice(source);});
    document.querySelectorAll('.field input[type=number]').forEach(source=>{if(!steppers.has(source))enhanceStepper(source);});
    choices.forEach(syncChoice);steppers.forEach(syncStepper);
    if(active&&active.source.closest('dialog')&&!active.source.closest('dialog').open)close();
  }
  function schedule(){if(!scheduled){scheduled=true;queueMicrotask(sync);}}
  const observer=new MutationObserver(records=>{
    if(records.some(r=>r.target.matches?.('select,option,optgroup,input[type=number]') || [...r.addedNodes,...r.removedNodes].some(n=>n.nodeType===1&&(n.matches('select,input[type=number]')||n.querySelector('select,input[type=number]')))))schedule();
  });
  observer.observe(document.body,{subtree:true,childList:true,attributes:true,attributeFilter:['disabled','selected','label','min','max','readonly']});
  document.addEventListener('pointerdown',event=>{if(active&&!active.button.contains(event.target)&&!active.menu.contains(event.target))close();},true);
  document.addEventListener('keydown',event=>{if(event.key==='Escape'&&active){event.preventDefault();event.stopImmediatePropagation();close(true);}},true);
  document.addEventListener('scroll',()=>{if(active)position(active);},true);
  window.addEventListener('resize',()=>{if(active)position(active);});
  window.addEventListener('hashchange',()=>close());
  document.addEventListener('close',()=>close(),true);
  document.addEventListener('reset',()=>queueMicrotask(sync),true);
  window.HabitControls={sync,close};sync();
})();
