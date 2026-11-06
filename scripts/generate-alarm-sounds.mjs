import fs from 'node:fs';
import path from 'node:path';

// Original, locally synthesized chimes: no network or licensed audio assets.
export function generateAlarmSounds(output) {
  const rate = 22050, length = 3.4;
  const melodies = {FocusFinished:[523.25,659.25,783.99,1046.5],BreakFinished:[880,659.25,880]};
  for (const [name,notes] of Object.entries(melodies)) {
    const frames = Math.ceil(rate*length), data = Buffer.alloc(44+frames*2);
    data.write('RIFF'); data.writeUInt32LE(data.length-8,4); data.write('WAVEfmt ',8);
    data.writeUInt32LE(16,16); data.writeUInt16LE(1,20); data.writeUInt16LE(1,22);
    data.writeUInt32LE(rate,24); data.writeUInt32LE(rate*2,28); data.writeUInt16LE(2,32); data.writeUInt16LE(16,34);
    data.write('data',36); data.writeUInt32LE(frames*2,40);
    for (let frame=0;frame<frames;frame++) {
      const t=frame/rate;
      let value=0;
      notes.forEach((hz,index)=>{
        const at=t-index*.38;
        if (at<0) return;
        const envelope=Math.min(1,at/.012)*Math.exp(-at*2.7)*Math.min(1,(length-t)/.15);
        value+=(Math.sin(at*hz*2*Math.PI)+.2*Math.sin(at*hz*4*Math.PI))*envelope*.26;
      });
      data.writeInt16LE(Math.round(Math.max(-.95,Math.min(.95,value))*32767),44+frame*2);
    }
    fs.writeFileSync(path.join(output,`${name}.wav`),data);
  }
}
