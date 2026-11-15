import unittest
import subprocess
import tempfile
from pathlib import Path
from tools.assembler import assemble
from model.gpu_model import GPUModel, GPUFault

ROOT=Path(__file__).resolve().parents[1]

class ModelTests(unittest.TestCase):
    def model(self, source, warps=1):
        m=GPUModel(assemble(source),lanes=4,warps=warps)
        m.launch();m.run();return m

    def test_signed_fixedpoint(self):
        m=self.model("LI r1,-98304,r15\nLI r2,131072,r15\nMUL r3,r1,r2\nMIN r4,r1,r2\nMAX r5,r1,r2\nRET")
        self.assertEqual(m.regs[0][0][3:6],[0xfffd0000,0xfffe8000,0x20000])

    def test_masks_ballot(self):
        m=self.model("RDSR r1,LANE_ID\nLDI r2,77\nPUSHM\nSETM r1\nBALLOT r2,r1\nPOPM\nRET")
        self.assertEqual([l[2] for l in m.regs[0]],[77,14,14,14])

    def test_spawn_barrier(self):
        m=self.model("LDI r1,2\nWSPAWN r1,child\nBARRIER\nRET\nchild: BARRIER\nRDSR r2,WARP_ID\nBARRIER\nRET",warps=2)
        self.assertEqual(m.regs[1][0][2],1)
        self.assertFalse(any(m.running))

    def test_faults(self):
        for source in ["POPM", "LDR r1,1(r0)", "ADD r1,r2,r3", "PRESENT"]:
            with self.subTest(source=source),self.assertRaises(GPUFault):self.model(source)

    def test_rtl_comparison(self):
        # Real assembler output is executed by both Python and the RTL system.
        for kernel,register in [('add',3),('lanes',6)]:
            with self.subTest(kernel=kernel),tempfile.TemporaryDirectory() as td:
                words=assemble((ROOT/f'software/kernels/{kernel}.S').read_text())
                m=GPUModel(words,lanes=8,warps=4,data_depth=32)
                for w in range(4):m.launch(w)
                m.run()
                hexfile=Path(td)/'program.hex'
                hexfile.write_text(''.join(f'{x:08x}\n' for x in words))
                tb=f"""`timescale 1ns/1ps
module compare_tb;
reg clk=0; always #5 clk=~clk;
reg reset=1,launch_valid=0,perf_clear=0,perf_enable=0;
reg [1:0] launch_warp_id=0,debug_warp_id=0;
reg [31:0] launch_pc=0,launch_args[0:3];
reg [7:0] launch_mask=255;
reg [3:0] debug_register={register};
wire [3:0] running; wire busy,fault;
wire [31:0] fault_pc,debug_data[0:7];
gpu_top #(.PROGRAM_DEPTH({len(words)}),.DATA_DEPTH(32),.PROGRAM_INIT_FILE("{hexfile}")) dut(
.clk(clk),.reset(reset),.launch_valid(launch_valid),.launch_warp_id(launch_warp_id),
.launch_pc(launch_pc),.launch_mask(launch_mask),.launch_args(launch_args),
.debug_warp_id(debug_warp_id),.debug_register(debug_register),.debug_data(debug_data),
.perf_clear(perf_clear),.perf_enable(perf_enable),.busy(busy),.fault(fault),.fault_pc(fault_pc),.running(running));
initial begin
 @(posedge clk);#1;@(negedge clk);reset=0;
 for(integer w=0;w<4;w=w+1)begin
  launch_valid=1;launch_warp_id=w;@(posedge clk);#1;@(negedge clk);
 end
 launch_valid=0;
 begin: wait_done
 for(integer c=0;c<10000;c=c+1)begin
  @(posedge clk);#1;if(fault)$fatal(1,"RTL fault");if(!busy)disable wait_done;
 end
 $fatal(1,"timeout");end
 for(integer w=0;w<4;w=w+1)begin
  debug_warp_id=w;#1;
  for(integer l=0;l<8;l=l+1)$display("REG %0d %0d %h",w,l,debug_data[l]);
 end
 for(integer a=0;a<32;a=a+1)$display("RAM %0d %h",a,dut.data_ram.memory[a]);
 $finish;end
endmodule
"""
                path=Path(td)/'compare.sv';path.write_text(tb)
                binary=str(Path(td)/'sim')
                subprocess.run(['iverilog','-g2012','-s','compare_tb','-o',binary,*map(str,(ROOT/'rtl').rglob('*.sv')),str(path)],check=True,capture_output=True)
                result=subprocess.run(['vvp',binary],check=True,capture_output=True,text=True,timeout=10)
                reg_count=mem_count=0
                for line in result.stdout.splitlines():
                    fields=line.split()
                    if fields[0]=='REG':
                        self.assertEqual(int(fields[3],16),m.regs[int(fields[1])][int(fields[2])][register]);reg_count+=1
                    elif fields[0]=='RAM' and m.memory[int(fields[1])] is not None:
                        self.assertEqual(int(fields[2],16),m.memory[int(fields[1])]);mem_count+=1
                self.assertEqual(reg_count,32)
                if kernel=='lanes':self.assertEqual(mem_count,32)

if __name__=='__main__':unittest.main()
