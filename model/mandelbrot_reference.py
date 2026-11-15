"""Standalone Mandelbrot oracle, independent of the GPU interpreter.
Default Q16.16 follows GPU MUL (signed 64-bit product, >>16, wrap32).
--fraction-bits 13 emulates wrapping 32-bit products in the supplied C example,
assuming two's-complement overflow and arithmetic signed right shifts.
C signed overflow itself is undefined; this is an explicit emulation convention.
"""
import argparse
from decimal import Decimal
import json
from pathlib import Path

TARGETS={"neck":("-0.75","0",64),"seahorse":("-0.745","0.113",128),
         "elephant":("0.275","0.007",128),"triple":("-0.088","0.654",128)}

def wrap32(value):
    value &= 0xffffffff
    return value if value < 0x80000000 else value-0x100000000

def multiply(a,b,bits=16):
    product=a*b
    if bits==13: product=wrap32(product)
    return wrap32(product >> bits)

def escape_iterations(cr,ci,max_iter=128,bits=16):
    zr=zi=0
    for iteration in range(max_iter):
        zr2=multiply(zr,zr,bits)
        zi2=multiply(zi,zi,bits)
        if wrap32(zr2+zi2)>4*(1<<bits): return iteration
        nzr=wrap32(wrap32(zr2-zi2)+cr)
        if bits==13:
            nzi=wrap32((wrap32(2*wrap32(zr*zi)) >> bits)+ci)
        else:
            # GPU kernel sequence: MUL zr,zi then double with ADD.
            nzi=wrap32(2*multiply(zr,zi,bits)+ci)
        zr,zi=nzr,nzi
    return max_iter

def color(iteration,max_iter):
    t=iteration & (max_iter-1)
    return (((t*8)&255)<<16)|(((t*5)&255)<<8)|((t*13)&255)

def render(width=16,height=16,target="seahorse",step=0,max_iter=None,bits=16):
    if width<1 or height<1 or step<0 or step>32 or bits not in (13,16):
        raise ValueError("positive dimensions, step 0..32, fractional bits 13 or 16 required")
    re,im,default_iter=TARGETS[target]
    max_iter=default_iter if max_iter is None else max_iter
    if max_iter<1 or max_iter & (max_iter-1): raise ValueError("iteration limit must be a positive power of two for reference palette")
    scale=1<<bits
    cx,cy=int(Decimal(re)*scale),int(Decimal(im)*scale)
    zoom=3*scale//2
    for _ in range(step): zoom=zoom*7//8
    dx=max(1,(zoom*2)//width)
    dy=max(1,((zoom*2*height)//width)//height)
    x0,y0=cx-dx*(width//2),cy-dy*(height//2)
    iterations=[]
    for y in range(height):
        ci=wrap32(y0+y*dy)
        for x in range(width):
            iterations.append(escape_iterations(wrap32(x0+x*dx),ci,max_iter,bits))
    return dict(width=width,height=height,target=target,step=step,fraction_bits=bits,
                max_iter=max_iter,x_start=x0,y_start=y0,x_step=dx,y_step=dy,
                iterations=iterations,pixels=[color(i,max_iter) for i in iterations],
                layout="row-major, one 32-bit word per 0x00RRGGBB pixel")

def write_ppm(path,frame):
    payload=bytearray()
    for pixel in frame['pixels']:payload.extend(((pixel>>16)&255,(pixel>>8)&255,pixel&255))
    Path(path).write_bytes(f"P6\n{frame['width']} {frame['height']}\n255\n".encode()+payload)

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--width',type=int,default=16);p.add_argument('--height',type=int,default=16)
    p.add_argument('--target',choices=TARGETS,default='seahorse')
    p.add_argument('--step',type=int,default=0);p.add_argument('--max-iter',type=int)
    p.add_argument('--fraction-bits',type=int,choices=(13,16),default=16)
    p.add_argument('-o','--output',type=Path,default=Path('output/mandelbrot/reference.json'))
    p.add_argument('--ppm',type=Path)
    args=p.parse_args()
    try:
        frame=render(args.width,args.height,args.target,args.step,args.max_iter,args.fraction_bits)
        args.output.parent.mkdir(parents=True,exist_ok=True)
        args.output.write_text(json.dumps(frame,indent=2)+'\n')
        if args.ppm:
            args.ppm.parent.mkdir(parents=True,exist_ok=True);write_ppm(args.ppm,frame)
    except (ValueError,OSError) as error:p.exit(1,f'{error}\n')
    print(f"Rendered {args.width}x{args.height} reference -> {args.output}")

if __name__=='__main__':main()
