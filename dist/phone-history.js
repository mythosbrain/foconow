export function phonePeriod(reports, deviceName, count = 7, now = Date.now()) {
  const key = date=>`${date.getFullYear()}-${String(date.getMonth()+1).padStart(2,'0')}-${String(date.getDate()).padStart(2,'0')}`;
  const today = new Date(now); today.setHours(12,0,0,0);
  const latest = new Map();
  for (const report of reports) {
    if (report.deviceName !== deviceName || !Number.isFinite(report.totalSeconds) || report.totalSeconds<0) continue;
    if (!latest.has(report.date) || latest.get(report.date).capturedAt<report.capturedAt) latest.set(report.date,report);
  }
  const days = Array.from({length:count},(_,i)=>{
    const date = new Date(today); date.setDate(date.getDate()-count+1+i);
    const record = latest.get(key(date));
    return record ? {...record,missing:false} : {date:key(date),missing:true,totalSeconds:null,apps:[]};
  });
  const apps = new Map(); let seconds=0, capturedAt=0, available=0;
  for (const day of days) {
    if(day.missing) continue;
    available++;seconds+=day.totalSeconds;capturedAt=Math.max(capturedAt,day.capturedAt||0);
    for(const app of day.apps||[]) if(Number.isFinite(app.seconds)&&app.seconds>=0) apps.set(app.name,(apps.get(app.name)||0)+app.seconds);
  }
  return {days,totalSeconds:seconds,capturedAt,available,count,apps:[...apps].map(([name,seconds])=>({name,seconds,bundleID:'Settings reports'})).sort((a,b)=>b.seconds-a.seconds)};
}
