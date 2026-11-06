export function createPhoneScreenTime({host,escape,svg,dayKey,focusDuration,phonePeriod}) {
  const get = id=>document.getElementById(id);
  let active = false, loading = false, snapshot = null, selectedDevice = '', selectedDay = dayKey();
  let source = 'events', settingsReports = [], readingSettings = false, settingsLoaded = false, periodDays = 1;
  let sync = {enabled:false,running:false,current:0,total:0,message:''};
  const dateText = date=>new Date(`${date}T12:00:00`).toLocaleDateString(undefined,{weekday:'long',month:'short',day:'numeric'});
  function refresh() {
    if (loading) return;
    loading = true; render(); host.postMessage({action:'phoneScreenTime'});
  }
  function showState(kind,title,text) {
    get('phone-empty').hidden = false; get('phone-data').hidden = true;
    get('phone-state-symbol').innerHTML = svg(kind==='permission'?'lock':'sun');
    get('phone-state-title').textContent = title; get('phone-state-description').textContent = text;
    get('phone-access-steps').hidden = kind!=='permission';
    get('phone-access-settings').hidden = kind!=='permission';
    get('phone-empty-retry').textContent = kind==='loading'?'Reading synced activity…':'Try again';
    get('phone-empty-retry').disabled = loading;
  }
  function render() {
    get('phone-refresh').disabled = loading || sync.running;
    get('phone-refresh').textContent = loading?'Refreshing…':'Refresh';
    get('phone-updated').textContent = snapshot?.updatedAt ? `Read on this Mac · ${new Date(snapshot.updatedAt).toLocaleTimeString(undefined,{hour:'2-digit',minute:'2-digit'})}` : 'Your iPhone’s data, read locally';
    const settings = source === 'settings';
    const groupedReports = new Map();
    for (const report of settingsReports) {
      if (!groupedReports.has(report.deviceName)) groupedReports.set(report.deviceName,{id:`settings:${report.deviceName}`,name:report.deviceName,days:[]});
      groupedReports.get(report.deviceName).days.push({...report,apps:report.apps.map(app=>({...app,bundleID:'Settings report'})),hours:null});
    }
    const devices = settings ? [...groupedReports.values()].map(d=>({...d,days:d.days.sort((a,b)=>a.date.localeCompare(b.date))})) : snapshot?.devices || [];
    const picker = get('phone-device');
    get('phone-device-field').hidden = devices.length<2;
    if (!devices.some(d=>d.id===selectedDevice)) selectedDevice = devices.find(d=>/iphone 16 pro max/i.test(d.name))?.id || [...devices].sort((a,b)=>b.days.reduce((s,d)=>s+d.totalSeconds,0)-a.days.reduce((s,d)=>s+d.totalSeconds,0))[0]?.id || '';
    picker.innerHTML = devices.map(d=>`<option value="${escape(d.id)}" ${d.id===selectedDevice?'selected':''}>${escape(d.name)}${devices.filter(other=>other.name===d.name).length>1?` · ${escape(d.id.slice(-6))}`:''}</option>`).join('');
    const device = devices.find(d=>d.id===selectedDevice);
    const period = settings && device && periodDays>1 ? phonePeriod(settingsReports,device.name,periodDays) : null;
    get('phone-period-range').hidden=!settings;document.querySelector('.phone-day-shortcuts').hidden=settings&&periodDays>1;
    $$range().forEach(button=>{button.setAttribute('aria-pressed',String(Number(button.dataset.phoneRange)===periodDays));button.hidden=!settings;});
    get('phone-import-progress').hidden=!sync.running;get('phone-import-progress').value=sync.current;get('phone-import-progress').max=Math.max(1,sync.total);get('phone-cancel-import').hidden=!sync.running;
    get('phone-sync-status').textContent=sync.message || (sync.enabled?'Automatic refresh every 15 minutes · keep Settings on this iPhone report.':'Automatic refresh is off.');
    get('phone-settings-auto').checked=sync.enabled;
    for(const id of ['phone-import-week','phone-import-month'])get(id).disabled=readingSettings||sync.running;
    get('phone-device-name').textContent = device?.name || 'Your iPhone';
    get('phone-import-details').hidden = !snapshot?.detail;
    get('phone-import-error').value = snapshot?.detail || '';
    get('phone-source-settings').setAttribute('aria-pressed',String(settings)); get('phone-source-events').setAttribute('aria-pressed',String(!settings));
    get('phone-read-settings').disabled = readingSettings || sync.running; get('phone-read-settings').textContent = readingSettings?'Reading Settings…':'Read from Settings';
    if (settings && !devices.length) showState('settings','Bring the Settings report here.','Open Settings, select your iPhone and Today or Yesterday, then choose Read from Settings above.');
    else if (!settings && loading && !snapshot) showState('loading','Reading the activity shared by your iPhone.','Checking the synced files already on this Mac.');
    else if (!settings && snapshot?.status==='permission') showState('permission','A little access. Your iPhone, in view.','Allow FocoNow to read the iPhone activity synced to this Mac. Everything stays on your Mac.');
    else if (!settings && snapshot && !['ready','empty'].includes(snapshot.status) && snapshot.status!=='missing') showState('error','The synced activity couldn’t be read.','Apple’s private storage format may have changed. You can retry; your habits and focus history are safe.');
    else if (!device || (!settings && snapshot?.status==='missing')) showState('empty','Waiting for your iPhone’s activity.','Keep Screen Time and Share Across Devices on for both devices, using the same Apple Account. Synced activity can arrive a few hours later.');
    else {
      get('phone-empty').hidden = true; get('phone-data').hidden = false;
      if (!device.days.some(d=>d.date===selectedDay)) selectedDay=device.days.some(d=>d.date===dayKey())?dayKey():device.days.at(-1)?.date || dayKey();
      const day = period || device.days.find(d=>d.date===selectedDay) || {totalSeconds:0,hours:Array(24).fill(0),apps:[]};
      get('phone-total').textContent = focusDuration(day.totalSeconds);
      get('phone-selected-date').textContent = period?`Last ${periodDays} days · ${period.available} / ${period.count} days imported`:selectedDay===dayKey()?'Today':dateText(selectedDay);
      get('phone-source-caption').textContent = settings?'IMPORTED FROM THE OPEN SETTINGS REPORT':'FROM YOUR IPHONE · PARTIAL SYNCED ACTIVITY';
      get('phone-updated').textContent = settings?`Settings report read · ${new Date(day.capturedAt).toLocaleString(undefined,{month:'short',day:'numeric',hour:'2-digit',minute:'2-digit'})}`:get('phone-updated').textContent;
      get('phone-history-label').textContent = period?`${dateText(period.days[0].date)} – ${dateText(period.days.at(-1).date)}`:settings?'Saved Settings reports · select a day':'Last 7 days · partial activity';
      get('phone-latest').textContent = settings?'Displayed All Usage total':snapshot.newestEvent ? `Latest synced activity · ${new Date(snapshot.newestEvent).toLocaleString(undefined,{month:'short',day:'numeric',hour:'2-digit',minute:'2-digit'})}` : 'No synced activity found yet';
      get('phone-import-warning').textContent = settings?(period?`${period.available} of ${period.count} daily Settings reports are included. Missing days are not counted as zero. Use Import ${periodDays} days to fill the period.`:'This is the total shown in Settings when read. Only the app rows exposed by Settings are included below.'):`Partial activity${snapshot.newestEvent?` · synced through ${new Date(snapshot.newestEvent).toLocaleString(undefined,{month:'short',day:'numeric',hour:'2-digit',minute:'2-digit'})}`:''}. This is not Apple’s complete Screen Time total.${snapshot.warning?' '+snapshot.warning:''}`;
      get('phone-import-warning').hidden = false;
      const chartDays=period?.days || device.days;
      get('phone-bars').classList.toggle('month-range',periodDays===30&&settings);
      const max = Math.max(3600,...chartDays.map(d=>d.totalSeconds||0));
      get('phone-bars').innerHTML = chartDays.map(d=>`<button class="focus-bar" data-phone-day="${d.date}" ${d.missing?'disabled':''} aria-pressed="${d.date===selectedDay}" aria-label="${escape(dateText(d.date))}: ${d.missing?'not imported':focusDuration(d.totalSeconds)}" title="${escape(dateText(d.date))} · ${d.missing?'not imported':focusDuration(d.totalSeconds)}"><span class="bar-column"><span class="bar-fill" style="height:${Math.max(d.totalSeconds>0?1:0,(d.totalSeconds||0)/max*100)}%"></span><span class="bar-value">${d.missing?'—':focusDuration(d.totalSeconds)}</span></span><span class="bar-date">${periodDays===30&&settings?(chartDays.indexOf(d)%5===0?new Date(`${d.date}T12:00:00`).getDate():''):escape(new Date(`${d.date}T12:00:00`).toLocaleDateString(undefined,{weekday:'short'}))}</span><i></i></button>`).join('');
      get('phone-bars').querySelectorAll('[data-phone-day]').forEach(button=>button.addEventListener('click',()=>{selectedDay=button.dataset.phoneDay;periodDays=1;render();}));
      get('phone-hour-title').textContent = `Your day, hour by hour`;
      get('phone-hour-panel').hidden = settings;
      get('phone-hour-panel').parentElement.classList.toggle('settings-report-metrics',settings);
      const peak = Math.max(3600,...(day.hours||[]));
      get('phone-hours').innerHTML = (day.hours||[]).map((seconds,hour)=>`<div role="img" aria-label="${hour}:00, ${focusDuration(seconds)}" title="${hour}:00 · ${focusDuration(seconds)}"><i style="height:${Math.max(seconds>0?3:0,seconds/peak*100)}%"></i></div>`).join('');
      get('phone-app-count').textContent = `${day.apps.length} ${day.apps.length===1?'app':'apps'}`;
      const top = day.apps[0]?.seconds || 1;
      get('phone-apps').innerHTML = day.apps.length ? day.apps.map((app,index)=>`<article class="phone-app-row"><span class="phone-app-icon">${app.icon?.startsWith('data:image/png;base64,')?`<img src="${escape(app.icon)}" alt="">`:escape((app.name||'?').slice(0,1).toUpperCase())}</span><div><span>${escape(app.name)}</span><small>${escape(app.bundleID)}</small><div class="allocation-track"><i style="width:${app.seconds/top*100}%"></i></div></div><strong>${focusDuration(app.seconds)}</strong></article>`).join('') : '<p class="insight-empty">No iPhone app sessions have synced for this day yet.</p>';
      get('phone-top-app').textContent = day.apps[0]?.name || '—';
      get('phone-total-label').textContent = period?'TOTAL FROM DAILY SETTINGS REPORTS':settings?'TOTAL SHOWN IN SETTINGS':'PARTIAL SYNCED APP ACTIVITY';
      get('phone-source-note').textContent = settings?'Saved from the visible Settings report. The total is Apple’s displayed All Usage figure, not the sum of the app rows. Open Settings to view its full hourly chart. Your focus timer stays separate.':'This activity-event feed can be delayed or incomplete. Refresh rereads available events; it does not force iCloud to sync. Use Read from Settings to import Apple’s displayed total.';
      get('phone-today').setAttribute('aria-pressed',String(selectedDay===dayKey()));
      const yesterday = new Date(); yesterday.setDate(yesterday.getDate()-1);
      get('phone-yesterday').setAttribute('aria-pressed',String(selectedDay===dayKey(yesterday)));
      get('phone-today').disabled = settings && !device.days.some(d=>d.date===dayKey());
      get('phone-yesterday').disabled = settings && !device.days.some(d=>d.date===dayKey(yesterday));
    }
    window.HabitControls?.sync();
  }
  function $$range(){return [...document.querySelectorAll('[data-phone-range]')];}
  $$range().forEach(button=>button.addEventListener('click',()=>{periodDays=Number(button.dataset.phoneRange);source='settings';render();}));
  function importPeriod(days){periodDays=days;source='settings';readingSettings=true;get('phone-settings-message').textContent=`Reading ${days} daily reports automatically…`;render();host.postMessage({action:'phoneSettingsImport',days});}
  get('phone-import-week').addEventListener('click',()=>importPeriod(7));
  get('phone-import-month').addEventListener('click',()=>importPeriod(30));
  get('phone-cancel-import').addEventListener('click',()=>host.postMessage({action:'phoneSettingsCancel'}));
  get('phone-settings-auto').addEventListener('change',event=>host.postMessage({action:'phoneSettingsAuto',enabled:event.target.checked}));
  get('phone-read-settings').addEventListener('click',()=>{readingSettings=true;get('phone-settings-message').textContent='Reading only the Screen Time report in System Settings…';render();host.postMessage({action:'phoneSettingsRead'});});
  get('phone-open-settings').addEventListener('click',()=>host.postMessage({action:'phoneOpenSettings'}));
  get('phone-settings-access').addEventListener('click',()=>host.postMessage({action:'phoneSettingsAccess'}));
  get('phone-source-settings').addEventListener('click',()=>{source='settings';selectedDevice='';render();});
  get('phone-source-events').addEventListener('click',()=>{source='events';selectedDevice='';render();});
  get('phone-refresh').addEventListener('click',()=>{if(source==='settings'){if(periodDays>1)importPeriod(periodDays);else get('phone-read-settings').click();}else refresh();});
  get('phone-empty-retry').addEventListener('click',()=>{if(source==='settings'){if(periodDays>1)importPeriod(periodDays);else get('phone-read-settings').click();}else refresh();});
  get('phone-access-settings').addEventListener('click',()=>host.postMessage({action:'phoneAccessSettings'}));
  get('phone-device').addEventListener('change',event=>{selectedDevice=event.target.value;render();});
  get('phone-today').addEventListener('click',()=>{selectedDay=dayKey();periodDays=1;render();});
  get('phone-yesterday').addEventListener('click',()=>{const d=new Date();d.setDate(d.getDate()-1);selectedDay=dayKey(d);periodDays=1;render();});
  get('phone-import-error').addEventListener('focus',event=>event.target.select());
  return {
    activate(value) { active=value; if(value) { if(!settingsLoaded){settingsLoaded=true;host.postMessage({action:'phoneSettingsHistory'});}refresh(); } },
    event(detail) {
      if(detail.type==='phoneSettingsSync'){sync=detail;render();}
      else if(detail.type==='phoneSettingsReports') { if(detail.sync)sync=detail.sync;const firstHistory=settingsReports.length===0;settingsReports=detail.reports||[];if(firstHistory&&settingsReports.length)source='settings';render(); }
      else if(detail.type==='phoneSettingsRead') { readingSettings=false;get('phone-settings-message').textContent=detail.message || (detail.status==='ready'?'Settings report saved. Its displayed total is shown below.':'The report could not be read.');get('phone-settings-access').hidden=detail.status!=='accessibility';if(detail.status==='ready'){if(detail.batch)periodDays=detail.days;settingsReports=detail.reports;source='settings';selectedDevice=`settings:${detail.deviceName}`;selectedDay=detail.date;}render(); }
      else if(detail.type==='phoneScreenTime') { snapshot=detail.snapshot;loading=false;render(); }
      else if(detail.type==='phoneScreenTimeRefresh' && active) refresh();
    },
  };
}
