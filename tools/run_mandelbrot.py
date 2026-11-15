"""Assemble, model, simulate and compare a Mandelbrot frame at selectable resolution."""
import argparse
import csv
import time
import json
from pathlib import Path
import re
import struct
import subprocess
import sys
import zlib
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from tools.assembler import assemble
from model.gpu_model import GPUModel
from model.mandelbrot_reference import render,write_ppm

def hexwrite(path,values):
    path.write_text(''.join(f'{x & 0xffffffff:08x}\n' for x in values))

def pngwrite(path,frame,scale=16):
    # Nearest-neighbor preview of the measured framebuffer; no smoothing.
    width,height=frame['width']*scale,frame['height']*scale
    rows=[]
    for y in range(frame['height']):
        row=bytearray([0])
        for x in range(frame['width']):
            p=frame['pixels'][y*frame['width']+x]
            row.extend(bytes(((p>>16)&255,(p>>8)&255,p&255))*scale)
        rows.extend([bytes(row)]*scale)
    def chunk(name,data):
        return struct.pack('!I',len(data))+name+data+struct.pack('!I',zlib.crc32(name+data)&0xffffffff)
    path.write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('!2I5B',width,height,8,2,0,0,0))+
                     chunk(b'IDAT',zlib.compress(b''.join(rows)))+chunk(b'IEND',b''))

PRESETS={'16':(16,16),'128':(128,128),'320x240':(320,240)}

def generate_kernel(width,height):
    if (width,height) not in PRESETS.values():raise ValueError('unsupported resolution')
    source=(ROOT/'software/kernels/mandelbrot.S.in').read_text()
    return source.replace('@WIDTH@',str(width)).replace('@HEIGHT@',str(height)).replace('@ITERATION_BASE@',str(width*height*4))

def comparison(target,step):
    base=ROOT/'output/mandelbrot'
    reports=[]
    for width,height in PRESETS.values():
        path=base/f'{width}x{height}'/f'{target}_step{step}'/'verification.json'
        if path.exists(): reports.append(json.loads(path.read_text()))
    columns=['resolution','pixels','cycles','cycles_per_pixel','instructions','issued_lane_utilization',
             'issue_occupancy','scheduler_idle','memory_blocked','simulation_wall_seconds']
    rows=[]
    for report in reports:
        row={key:report.get(key) for key in columns}
        rows.append(row)
    name=f'comparison_{target}_step{step}'
    with (base/(name+'.csv')).open('w',newline='') as f:
        writer=csv.DictWriter(f,fieldnames=columns);writer.writeheader();writer.writerows(rows)
    lines=['# Mandelbrot resolution comparison','',
           '8 lanes, 4 warps, 128 iterations, Q16.16; same center and horizontal view.',
           '320x240 uses its natural 4:3 aspect ratio, so vertical coverage differs.',
           'Simulation wall time measures vvp only, including RAM comparison and dump; it depends on the host.',
           'Memory-blocked cycles can overlap issued instructions; they are not all wasted cycles.','',
           '| Resolution | Pixels | Cycles | Cycles/pixel | Instructions | Lane utilization | Issue occupancy | Idle cycles | Memory-blocked | Simulation seconds |',
           '|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|']
    for q in reports:
        lines.append(f"| {q['resolution']} | {q['pixels']} | {q['cycles']} | {q['cycles_per_pixel']:.2f} | {q['instructions']} | {q['issued_lane_utilization']:.1%} | {q['issue_occupancy']:.1%} | {q['scheduler_idle']} | {q['memory_blocked']} | {q['simulation_wall_seconds']:.3f} |")
    if len(reports)>1:
        baseline=reports[0]
        lines+=['','Relative to '+baseline['resolution']+':']
        for q in reports[1:]:lines.append(f"- {q['resolution']}: {q['pixels']/baseline['pixels']:.0f}x pixels, {q['cycles']/baseline['cycles']:.2f}x simulated cycles.")
    (base/(name+'.md')).write_text('\n'.join(lines)+'\n')
    return base/(name+'.md')

def run_preset(preset,target,step,timeout):
    width,height=PRESETS[preset];pixels=width*height
    out=ROOT/'output/mandelbrot'/f'{width}x{height}'/f'{target}_step{step}'
    out.mkdir(parents=True,exist_ok=True)
    print(f'[{width}x{height}] Building independent reference...',flush=True)
    started=time.perf_counter();frame=render(width,height,target,step,max_iter=128)
    reference_seconds=time.perf_counter()-started
    source=generate_kernel(width,height);(out/'program.S').write_text(source)
    words=assemble(source);hexwrite(out/'program.hex',words)
    launch_args=[frame[k] for k in ['x_start','y_start','x_step','y_step']]
    hexwrite(out/'launch_args.hex',launch_args)
    hexwrite(out/'expected.hex',frame['pixels']+frame['iterations'])
    started=time.perf_counter();model=GPUModel(words,data_depth=2*pixels)
    for w in range(4):model.launch(w,args=launch_args)
    model.run(max_instructions=pixels*4096)
    model_seconds=time.perf_counter()-started
    if model.memory!=frame['pixels']+frame['iterations']:raise RuntimeError('Python GPU differs from reference')
    print(f'[{width}x{height}] PASS Python model ({model.instructions:,} instructions); running RTL...',flush=True)
    name='mandelbrot_tb';binary=out/'mandelbrot_sim'
    sources=[str(p) for p in (ROOT/'rtl').rglob('*.sv')]
    params=dict(WIDTH=width,HEIGHT=height,PROGRAM_WORDS=len(words),MAX_CYCLES=pixels*4096,
                PROGRAM_FILE=str(out/'program.hex'),EXPECTED_FILE=str(out/'expected.hex'),
                ARGS_FILE=str(out/'launch_args.hex'),FRAME_FILE=str(out/'rtl_frame.hex'))
    flags=[f'-P{name}.{k}='+('"'+v+'"' if isinstance(v,str) else str(v)) for k,v in params.items()]
    started=time.perf_counter()
    subprocess.run(['iverilog','-g2012','-s',name,*flags,'-o',str(binary),*sources,str(ROOT/'sim/tb/mandelbrot_tb.sv')],check=True)
    compile_seconds=time.perf_counter()-started
    started=time.perf_counter()
    result=subprocess.run(['vvp',str(binary)],cwd=ROOT,check=True,capture_output=True,text=True,timeout=timeout)
    simulation_seconds=time.perf_counter()-started
    print(result.stdout,end='',flush=True);(out/'simulation.log').write_text(result.stdout)
    values=[int(line.strip(),16) for line in (out/'rtl_frame.hex').read_text().splitlines()
            if line.strip() and not line.lstrip().startswith('//')]
    if values!=frame['pixels']+frame['iterations']:raise RuntimeError('RTL dump differs from reference')
    rtl_frame=dict(frame,pixels=values[:pixels],iterations=values[pixels:])
    write_ppm(out/'rtl_frame.ppm',rtl_frame)
    pngwrite(out/'rtl_frame.png',rtl_frame,scale=1)
    pngwrite(out/'rtl_preview.png',rtl_frame,scale=max(1,512//max(width,height)))
    counters={k:int(v) for k,v in re.findall(r'(cycles|instructions|active_lane_instructions|scheduler_idle|memory_blocked)=(\d+)',result.stdout)}
    if counters['instructions']!=model.instructions:raise RuntimeError('model/RTL issued instruction count mismatch')
    report=dict(match=True,resolution=f'{width}x{height}',pixels=pixels,iteration_counts=pixels,
        target=target,step=step,lanes=8,warps=4,max_iter=128,fraction_bits=16,
        kernel_words=len(words),model_instructions=model.instructions,counters=counters,**counters,
        cycles_per_pixel=counters['cycles']/pixels,
        issued_lane_utilization=counters['active_lane_instructions']/(counters['instructions']*8),
        issue_occupancy=counters['instructions']/counters['cycles'],
        reference_wall_seconds=reference_seconds,model_wall_seconds=model_seconds,
        compile_wall_seconds=compile_seconds,simulation_wall_seconds=simulation_seconds,
        ram_bytes=pixels*8)
    (out/'reference.json').write_text(json.dumps(frame,indent=2)+'\n')
    (out/'verification.json').write_text(json.dumps(report,indent=2)+'\n')
    print(f'[{width}x{height}] VERIFIED: {out / "rtl_preview.png"}',flush=True)
    return report

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--resolution',choices=[*PRESETS,'all'],default='16')
    parser.add_argument('--target',choices=['neck','seahorse','elephant','triple'],default='seahorse')
    parser.add_argument('--step',type=int,default=0)
    parser.add_argument('--timeout',type=int,default=1800,help='wall-clock limit per RTL run in seconds')
    args=parser.parse_args()
    for preset in (PRESETS if args.resolution=='all' else [args.resolution]):
        run_preset(preset,args.target,args.step,args.timeout)
        print('Comparison: '+str(comparison(args.target,args.step)),flush=True)

if __name__=='__main__':main()
