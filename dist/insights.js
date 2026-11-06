// Calendar boundaries are local; elapsed time always uses actual milliseconds.
export function insightDate(date) {
  const d = new Date(date);
  return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;
}
export function focusIntervals(timer, now = Date.now()) {
  const spans = [...(timer.focusSpans || [])];
  if (timer.phase === 'work' && timer.status === 'running' && timer.endsAt) {
    const start = timer.focusStartedAt ?? timer.endsAt - timer.remaining * 1000;
    spans.push({start,end:Math.min(now,timer.endsAt),taskId:timer.taskId,taskTitle:timer.taskTitle});
  }
  // Older versions kept completed sessions only. Preserve those totals once.
  for (const session of timer.sessions || []) if (!session.tracked) {
    spans.push({start:session.endedAt-session.seconds*1000,end:session.endedAt,taskId:session.taskId,taskTitle:session.taskTitle,legacy:true});
  }
  return spans.filter(s=>Number.isFinite(s.start) && Number.isFinite(s.end) && s.end>s.start).map(s=>({...s,end:Math.min(now,s.end)})).filter(s=>s.end>s.start);
}
export function focusReport(timer, planner = {}, count = 7, now = Date.now()) {
  const today = new Date(now); today.setHours(0,0,0,0);
  const first = new Date(today); first.setDate(first.getDate()-count*2+1);
  const days = [];
  for (let i=0;i<count*2;i++) {
    const start = new Date(first); start.setDate(first.getDate()+i);
    const end = new Date(start); end.setDate(end.getDate()+1);
    const date = insightDate(start), plan = planner.days?.[date] || planner[date] || {};
    days.push({date,start:+start,end:+end,seconds:0,hours:Array(24).fill(0),tasks:(plan.tasks||[]).length,done:(plan.tasks||[]).filter(t=>t.done).length,reviewed:!!plan.summarySavedAt,sessions:0,spans:[]});
  }
  const intervals = focusIntervals(timer,now);
  for (const day of days) {
    for (const span of intervals) {
      const start = Math.max(day.start,span.start), end = Math.min(day.end,span.end);
      if (end<=start) continue;
      day.seconds += (end-start)/1000;
      day.spans.push({...span,start,end});
      // Walk real hours, so daylight-saving days don't lose or invent time.
      for (let cursor=start;cursor<end;) {
        const local = new Date(cursor);
        const nextHour = cursor + (60-local.getMinutes())*60000 - local.getSeconds()*1000 - local.getMilliseconds();
        const stop = Math.min(end,nextHour);
        day.hours[new Date(cursor).getHours()] += (stop-cursor)/1000;
        cursor = stop;
      }
    }
    day.sessions = (timer.sessions||[]).filter(s=>insightDate(s.endedAt)===day.date).length;
  }
  const current = days.slice(count), previous = days.slice(0,count);
  const sum = a=>a.reduce((v,d)=>v+d.seconds,0);
  const seconds = sum(current), previousSeconds = sum(previous);
  const hours = Array.from({length:24},(_,i)=>current.reduce((v,d)=>v+d.hours[i],0));
  const tasks = current.reduce((v,d)=>v+d.tasks,0), done = current.reduce((v,d)=>v+d.done,0);
  const byTask = new Map();
  for (const d of current) for (const span of d.spans) {
    const key = span.taskId || '__open';
    const row = byTask.get(key) || {id:key,title:span.taskTitle || 'Open focus',seconds:0};
    row.seconds += (span.end-span.start)/1000; byTask.set(key,row);
  }
  return {days:current,seconds,previousSeconds,average:seconds/count,activeDays:current.filter(d=>d.seconds>0).length,tasks,done,sessions:current.reduce((v,d)=>v+d.sessions,0),bestHour:hours.some(v=>v>0)?hours.indexOf(Math.max(...hours)):null,byTask:[...byTask.values()].sort((a,b)=>b.seconds-a.seconds)};
}
export function focusDuration(seconds, precise = false) {
  const minutes = Math.floor(Math.max(0,seconds)/60), hours = Math.floor(minutes/60);
  if (seconds>0 && minutes===0) return precise ? `${Math.floor(seconds)}s` : '<1m';
  return hours ? `${hours}h ${String(minutes%60).padStart(2,'0')}m` : `${minutes}m`;
}
