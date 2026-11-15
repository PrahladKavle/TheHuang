`timescale 1ns/1ps
module warp_sync_tb;
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
   // Parent spawns all children, then joins their common program.
   dut.core.program_rom.memory[0]=enc(14,1,0,0,16);
   dut.core.program_rom.memory[1]=enc(23,0,1,0,14);
   dut.core.program_rom.memory[2]=enc(21,0,0,0,13);
   dut.core.program_rom.memory[16]=enc(14,2,0,0,1);
   dut.core.program_rom.memory[17]=enc(14,3,0,0,17);
   dut.core.program_rom.memory[18]=enc(7,6,2,0,2);
   dut.core.program_rom.memory[19]=enc(0,6,6,3,0);
   dut.core.program_rom.memory[20]=enc(12,4,0,0,99);
   dut.core.program_rom.memory[21]=enc(26,0,6,4,0);
   dut.core.program_rom.memory[22]=enc(24,0,0,0,0);
   dut.core.program_rom.memory[23]=enc(25,5,3,0,(WARPS-1)*4);
   dut.core.program_rom.memory[24]=enc(24,0,0,0,0);
   dut.core.program_rom.memory[25]=enc(14,7,0,0,18);
   dut.core.program_rom.memory[26]=enc(22,0,0,0,0);
   tick();@(negedge clk);reset=0;
   launch_valid=1;launch_warp_id=0;launch_pc=0;
   launch_args[0]=(32'hffffffff>>(32-WARPS)) & 32'hfffffffe;
   launch_args[1]=64;launch_args[2]=32'hdeadbeef;launch_args[3]=0;
   tick();@(negedge clk);launch_valid=0;
   for(integer a=0;a<4;a=a+1)launch_args[a]=0;
   run_done();
   for(integer w=0;w<WARPS;w=w+1)begin
     if(dut.data_ram.memory[16+w]!==99)$fatal(1,"store before barrier");
     for(integer l=0;l<LANES;l=l+1)begin
       expect_reg(w,2,l,w);expect_reg(w,5,l,99);expect_reg(w,7,l,32'hdeadbeef);
     end
   end
   if(dut.core.barrier_active)$fatal(1,"barrier epoch leaked");
   // Respawn with a partial mask; parent retires before children synchronize.
   dut.core.program_rom.memory[32]=enc(14,1,0,0,16);
   dut.core.program_rom.memory[33]=enc(14,8,0,0,0);
   dut.core.program_rom.memory[34]=enc(15,0,8,0,0);
   dut.core.program_rom.memory[35]=enc(23,0,1,0,12);
   dut.core.program_rom.memory[36]=enc(22,0,0,0,0);
   dut.core.program_rom.memory[48]=enc(24,0,0,0,0);
   dut.core.program_rom.memory[49]=enc(14,7,0,0,18);
   dut.core.program_rom.memory[50]=enc(24,0,0,0,0);
   dut.core.program_rom.memory[51]=enc(22,0,0,0,0);
   @(negedge clk);launch_valid=1;launch_pc=128;launch_args[0]=(32'hffffffff>>(32-WARPS)) & 32'hfffffffe;
   launch_args[2]=1234;tick();@(negedge clk);launch_valid=0;
   run_done();
   for(integer w=1;w<WARPS;w=w+1)
     for(integer l=0;l<LANES;l=l+1)expect_reg(w,7,l,(l==0)?32'hdeadbeef:1234);
   // Invalid self-targeting spawn must not advance or relaunch the caller.
   dut.core.program_rom.memory[60]=enc(12,1,0,0,1);
   dut.core.program_rom.memory[61]=enc(23,0,1,0,0);
   @(negedge clk);launch_valid=1;launch_pc=240;tick();@(negedge clk);launch_valid=0;
   begin: await_fault
     for(integer c=0;c<20;c=c+1)begin tick();if(fault)disable await_fault;end
     $fatal(1,"missing invalid spawn fault");
   end
   if(fault_pc!==244 || dut.core.pc[0]!==244)$fatal(1,"spawn fault not atomic");
   $display("PASS: WSPAWN/barrier integration LANES=%0d WARPS=%0d checks=%0d",LANES,WARPS,checks);$finish;
 end
 initial begin #1000000;$fatal(1,"timeout");end
endmodule
