"""Functional, bit-accurate custom GPU ISA model; not cycle/timing accurate.
Uninitialized registers/RAM are None and fault when consumed. Memory executes
atomically per instruction; data races between warps have no RTL ordering guarantee.
"""
import argparse
import json
from pathlib import Path

MASK = 0xffffffff

def u32(x): return x & MASK

def signed(x): return x if x < 0x80000000 else x - 0x100000000

def sext14(x): return x if x < 8192 else x - 16384

class GPUFault(RuntimeError):
    pass

class GPUModel:
    def __init__(self, program, lanes=8, warps=4, data_depth=16384, stack_depth=8):
        if not 1 <= lanes <= 32 or not 1 <= warps <= 32 or data_depth < 1 or stack_depth < 1:
            raise ValueError("invalid GPU dimensions")
        self.program = list(program)
        if any(not isinstance(x, int) or not 0 <= x <= MASK for x in self.program):
            raise ValueError("program words must be unsigned 32-bit integers")
        self.lanes, self.warps, self.stack_depth = lanes, warps, stack_depth
        self.regs = [[[0]+[None]*15 for _ in range(lanes)] for _ in range(warps)]
        self.memory = [None]*data_depth
        self.pc = [0]*warps
        self.masks = [0]*warps
        self.stacks = [[] for _ in range(warps)]
        self.args = [[0]*4 for _ in range(warps)]
        self.running = [False]*warps
        self.waiting = set()
        self.members = None
        self.pointer = 0
        self.instructions = 0
        self.fault = None
        self.fault_pc = None

    @classmethod
    def from_hex(cls, path, **kwargs):
        words = [int(line.strip(), 16) for line in Path(path).read_text().splitlines() if line.strip()]
        return cls(words, **kwargs)

    def launch(self, warp=0, pc=0, mask=None, args=(0,0,0,0)):
        if self.fault or self.members is not None or not 0 <= warp < self.warps or self.running[warp]:
            raise GPUFault("invalid launch or launch during barrier")
        if len(args) != 4: raise ValueError("four launch arguments required")
        self.pc[warp] = u32(pc)
        self.masks[warp] = ((1 << self.lanes)-1) if mask is None else mask & ((1 << self.lanes)-1)
        self.args[warp] = [u32(a) for a in args]
        self.stacks[warp] = []
        self.waiting.discard(warp)
        self.running[warp] = True

    def read(self, warp, lane, register):
        value = self.regs[warp][lane][register]
        if value is None: raise GPUFault(f"uninitialized r{register}, lane {lane}")
        return value

    def _release(self):
        if self.members is not None:
            live = {w for w in self.members if self.running[w]}
            if live <= self.waiting:
                self.waiting.clear()
                self.members = None

    def step(self):
        if self.fault: raise GPUFault(self.fault)
        self._release()
        ready = [w for w in range(self.warps) if self.running[w] and w not in self.waiting]
        if not ready:
            if any(self.running): raise GPUFault("barrier deadlock: live participant never arrived")
            return False
        w = next((self.pointer+i) % self.warps for i in range(self.warps)
                 if (self.pointer+i) % self.warps in ready)
        try:
            self._execute(w)
        except GPUFault as error:
            self.fault, self.fault_pc = str(error), self.pc[w]
            raise GPUFault(f"warp {w}, PC 0x{self.pc[w]:08x}: {error}") from error
        self.pointer = (w+1) % self.warps
        self.instructions += 1
        self._release()
        return True

    def _execute(self, w):
        pc = self.pc[w]
        if pc % 4 or pc//4 >= len(self.program): raise GPUFault("invalid instruction address")
        word = self.program[pc//4]
        op, d, a, b, imm = word>>26, (word>>22)&15, (word>>18)&15, (word>>14)&15, word&16383
        active = [l for l in range(self.lanes) if self.masks[w] & (1<<l)]
        next_pc = u32(pc+4)
        target = u32(next_pc + sext14(imm)*4)
        writes = []
        if op <= 11:
            for l in active:
                x = self.read(w,l,a)
                y = (imm & 31) if op in (7,8) else self.read(w,l,b)
                if op == 0: value=x+y
                elif op == 1: value=x-y
                elif op == 2: value=x&y
                elif op == 3: value=x|y
                elif op == 4: value=x^y
                elif op == 5: value=int(signed(x)<signed(y))
                elif op == 6: value=(signed(x)*signed(y))>>16
                elif op == 7: value=x<<y
                elif op == 8: value=x>>y
                elif op == 9: value=int(x==y)
                elif op == 10: value=min(signed(x),signed(y))
                else: value=max(signed(x),signed(y))
                writes.append((l,value))
        elif op in (12,13):
            value = imm if op==12 else (word & 0x3ffff)<<14
            writes = [(l,value) for l in active]
        elif op == 14:
            if imm not in (0,1,2,3,16,17,18,19): raise GPUFault("invalid RDSR selector")
            for l in active:
                value = [l,w,self.lanes,self.warps][imm] if imm<4 else self.args[w][imm-16]
                writes.append((l,value))
        elif op == 15:
            self.masks[w] &= sum(1<<l for l in active if self.read(w,l,a)!=0)
        elif op == 16:
            if len(self.stacks[w]) >= self.stack_depth: raise GPUFault("mask stack overflow")
            self.stacks[w].append(self.masks[w])
        elif op == 17:
            if not self.stacks[w]: raise GPUFault("mask stack underflow")
            self.masks[w] = self.stacks[w].pop()
        elif op == 18:
            self.masks[w] = self.read(w,0,a) & ((1<<self.lanes)-1)
        elif op == 19:
            vote = sum(1<<l for l in active if self.read(w,l,a)!=0)
            writes = [(l,vote) for l in active]
        elif op in (20,21):
            if op==21 or active: next_pc=target
        elif op == 22:
            self.running[w]=False
            self.masks[w]=0
        elif op == 23:
            targets = self.read(w,0,a)
            children = [c for c in range(self.warps) if targets & (1<<c)]
            if self.members is not None or targets>>self.warps or any(self.running[c] for c in children) or target%4 or target//4>=len(self.program):
                raise GPUFault("invalid WSPAWN")
            for child in children: self.launch(child,target,self.masks[w],self.args[w])
        elif op == 24:
            if self.members is None: self.members={c for c in range(self.warps) if self.running[c]}
            self.waiting.add(w)
        elif op in (25,26):
            for l in active:
                address=u32(self.read(w,l,a)+sext14(imm))
                if address%4 or address//4>=len(self.memory): raise GPUFault("invalid data address")
                if op==26: self.memory[address//4]=self.read(w,l,b)
                else:
                    value=self.memory[address//4]
                    if value is None: raise GPUFault("uninitialized RAM read")
                    writes.append((l,value))
        else: raise GPUFault("unsupported instruction")
        for l,value in writes:
            if d: self.regs[w][l][d]=u32(value)
        self.pc[w]=next_pc

    def run(self, max_instructions=1000000):
        for _ in range(max_instructions):
            if not self.step(): return self
        if any(self.running): raise GPUFault("instruction limit exceeded")
        return self

    def snapshot(self):
        return dict(pc=self.pc, registers=self.regs, memory=self.memory,
                    running=self.running, masks=self.masks, instructions=self.instructions,
                    fault=self.fault, fault_pc=self.fault_pc)

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('program',type=Path)
    parser.add_argument('--lanes',type=int,default=8)
    parser.add_argument('--warps',type=int,default=4)
    parser.add_argument('--launch-all',action='store_true')
    parser.add_argument('--arg',type=lambda x:int(x,0),action='append',default=[])
    parser.add_argument('--data-depth',type=int,default=16384)
    parser.add_argument('--max-instructions',type=int,default=1000000)
    parser.add_argument('-o','--output',type=Path)
    args=parser.parse_args()
    try:
        if len(args.arg)>4: raise ValueError("at most four --arg values")
        model=GPUModel.from_hex(args.program,lanes=args.lanes,warps=args.warps,data_depth=args.data_depth)
        for w in range(args.warps if args.launch_all else 1): model.launch(w,args=args.arg+[0]*(4-len(args.arg)))
        model.run(args.max_instructions)
        output=json.dumps(model.snapshot(),indent=2)+'\n'
        if args.output: args.output.write_text(output)
        else: print(output,end='')
    except (GPUFault,ValueError,OSError) as error: parser.exit(1,f'{error}\n')

if __name__=='__main__': main()
