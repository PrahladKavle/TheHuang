`timescale 1ns/1ps
module mask_execution_tb;
 parameter integer LANES=8,WARPS=4;
 localparam integer IW=(WARPS>1)?$clog2(WARPS):1;
 reg perf_clear=0,perf_enable=0;
 wire [63:0] total_cycles,instructions_issued,active_lane_instructions;
 wire [63:0] scheduler_idle_cycles,memory_blocked_cycles;
 reg clk=0;always #5 clk=~clk;
 reg reset=1,launch_valid=0;
 reg [IW-1:0] launch_warp_id=0,debug_warp_id=0;
 reg [31:0] launch_pc=0,launch_args[0:3];
 reg [LANES-1:0] launch_mask={LANES{1'b1}};
 reg [3:0] debug_register=0;
 wire [WARPS-1:0] running;
 wire busy,fault;
 wire [31:0] fault_pc,debug_data[0:LANES-1];
 integer checks=0;
 gpu_top #(.LANES(LANES),.WARPS(WARPS),.PROGRAM_DEPTH(256),.DATA_DEPTH(256)) dut(.*);
 function automatic [31:0] enc(input integer op,d,a,b,imm);
 enc=(op<<26)|(d<<22)|(a<<18)|(b<<14)|(imm&16383);
 endfunction
 task tick;begin @(posedge clk);#1;end endtask
 task run_done;
 begin: run
   for(integer c=0;c<5000;c=c+1)begin
     tick();if(fault)$fatal(1,"unexpected fault at %h",fault_pc);
     if(!busy)disable run;
   end
   $fatal(1,"timeout");
 end
 endtask
 task expect_reg(input integer w,regnum,lane,input [31:0] value);
 begin
   debug_warp_id=w;debug_register=regnum;#1;checks=checks+1;
   if(debug_data[lane]!==value)$fatal(1,"warp=%0d lane=%0d r%0d=%h expected=%h",w,lane,regnum,debug_data[lane],value);
 end
 endtask
 initial begin
   dut.core.program_rom.memory[0]=enc(14,1,0,0,0);
   dut.core.program_rom.memory[1]=enc(12,2,0,0,77);
   dut.core.program_rom.memory[2]=enc(12,3,0,0,1);
   dut.core.program_rom.memory[3]=enc(16,0,0,0,0);
   dut.core.program_rom.memory[4]=enc(15,0,1,0,0);
   dut.core.program_rom.memory[5]=enc(12,2,0,0,10);
   dut.core.program_rom.memory[6]=enc(16,0,0,0,0);
   dut.core.program_rom.memory[7]=enc(15,0,0,0,0);
   dut.core.program_rom.memory[8]=enc(20,0,0,0,1);
   dut.core.program_rom.memory[9]=enc(17,0,0,0,0);
   dut.core.program_rom.memory[10]=enc(12,2,0,0,20);
   dut.core.program_rom.memory[11]=enc(17,0,0,0,0);
   dut.core.program_rom.memory[12]=enc(12,4,0,0,1);
   dut.core.program_rom.memory[13]=enc(18,0,0,0,0);
   dut.core.program_rom.memory[14]=enc(20,0,0,0,1);
   dut.core.program_rom.memory[15]=enc(18,0,3,0,0);
   dut.core.program_rom.memory[16]=enc(12,2,0,0,30);
   dut.core.program_rom.memory[17]=enc(22,0,0,0,0);
   tick();@(negedge clk);reset=0;
   for(integer w=0;w<WARPS;w=w+1)begin
     launch_valid=1;launch_warp_id=w;tick();@(negedge clk);
   end
   launch_valid=0;run_done();
   for(integer w=0;w<WARPS;w=w+1)
     for(integer l=0;l<LANES;l=l+1)begin
       expect_reg(w,2,l,(l==0)?30:20);
       expect_reg(w,4,l,1);
     end
   // Empty stack on re-launch: POPM must fault without changing the PC/mask.
   dut.core.program_rom.memory[32]=enc(17,0,0,0,0);
   @(negedge clk);launch_valid=1;launch_warp_id=0;launch_pc=128;
   tick();@(negedge clk);launch_valid=0;tick();
   if(!fault || fault_pc!==128 || dut.core.pc[0]!==128 || dut.core.active_mask[0]!=={LANES{1'b1}})
     $fatal(1,"underflow must fault atomically");
   $display("PASS: mask execution LANES=%0d WARPS=%0d checks=%0d",LANES,WARPS,checks);$finish;
 end
 initial begin #1000000;$fatal(1,"timeout");end
endmodule
