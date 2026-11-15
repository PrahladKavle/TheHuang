`timescale 1ns/1ps
module gpu_top_tb;
 parameter integer LANES=8,WARPS=4;
 localparam integer IW=(WARPS>1)?$clog2(WARPS):1;
 reg [31:0] launch_args [0:3];
 reg perf_clear=0,perf_enable=0;
 wire [63:0] total_cycles,instructions_issued,active_lane_instructions;
 wire [63:0] scheduler_idle_cycles,memory_blocked_cycles;
 reg clk=0;always #5 clk=~clk;
 reg reset=1,launch_valid=0;
 reg [IW-1:0] launch_warp_id=0,debug_warp_id=0;
 reg [31:0] launch_pc=0;
 reg [LANES-1:0] launch_mask;
 reg [3:0] debug_register=4;
 wire [WARPS-1:0] running;
 wire busy,fault;
 wire [31:0] fault_pc,debug_data[0:LANES-1];
 integer transactions=0,active_lanes=0;
 gpu_top #(.LANES(LANES),.WARPS(WARPS),.PROGRAM_DEPTH(256),.DATA_DEPTH(256)) dut(.*);
 always @(posedge clk)
   if(!reset && dut.memory_request_valid && dut.memory_request_ready)
     transactions<=transactions+1;
 function automatic [31:0] enc(input integer op,d,a,b,imm);
 enc=(op<<26)|(d<<22)|(a<<18)|(b<<14)|(imm&16383);
 endfunction
 task tick;begin @(posedge clk);#1;end endtask
 initial begin
   for(integer l=0;l<LANES;l=l+1)begin launch_mask[l]=(l%2==0);if(l%2==0)active_lanes=active_lanes+1;end
   for(integer w=0;w<WARPS;w=w+1)begin
     dut.core.program_rom.memory[w*16]=enc(12,1,0,0,w*64);
     dut.core.program_rom.memory[w*16+1]=enc(12,2,0,0,100+w);
     dut.core.program_rom.memory[w*16+2]=enc(26,0,1,2,0);
     dut.core.program_rom.memory[w*16+3]=enc(12,3,0,0,77);
     dut.core.program_rom.memory[w*16+4]=enc(25,3,1,0,0);
     dut.core.program_rom.memory[w*16+5]=enc(0,4,3,2,0);
     dut.core.program_rom.memory[w*16+6]=enc(22,0,0,0,0);
   end
   tick();@(negedge clk);reset=0;
   for(integer w=0;w<WARPS;w=w+1)begin
     launch_valid=1;launch_warp_id=w;launch_pc=w*64;tick();@(negedge clk);
   end
   launch_valid=0;
   begin: run
     for(integer i=0;i<10000;i=i+1)begin
       tick();if(fault)$fatal(1,"fault PC=%h",fault_pc);
       if(!busy)disable run;
     end
     $fatal(1,"execution timeout");
   end
   if(transactions!=2*WARPS*active_lanes)$fatal(1,"masked lanes issued memory: count=%0d",transactions);
   for(integer w=0;w<WARPS;w=w+1)begin
     if(dut.data_ram.memory[w*16]!==100+w)$fatal(1,"store data");
     debug_warp_id=w;debug_register=4;#1;
     for(integer l=0;l<LANES;l=l+1)
       if(launch_mask[l] && debug_data[l]!==200+2*w)$fatal(1,"load/writeback warp=%0d lane=%0d got=%h",w,l,debug_data[l]);
   end
   // Misaligned load must fault at the original memory PC and not write.
   dut.core.program_rom.memory[200]=enc(25,4,0,0,1);
   @(negedge clk);launch_valid=1;launch_warp_id=0;launch_pc=800;tick();
   @(negedge clk);launch_valid=0;
   begin: fault_wait
     for(integer i=0;i<100;i=i+1)begin tick();if(fault)disable fault_wait;end
     $fatal(1,"missing alignment fault");
   end
   if(fault_pc!==800)$fatal(1,"wrong fault PC");
   debug_warp_id=0;#1;
   for(integer l=0;l<LANES;l=l+1)
     if(launch_mask[l] && debug_data[l]!==200)$fatal(1,"fault corrupted destination");
   $display("PASS: GPU with real RAM LANES=%0d WARPS=%0d transactions=%0d ",LANES,WARPS,transactions);
   $finish;
 end
 initial begin #1000000;$fatal(1,"timeout");end
endmodule
