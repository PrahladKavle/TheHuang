`timescale 1ns/1ps
module minimal_core_tb;
 parameter integer LANES=8,WARPS=4;
 localparam integer IW=(WARPS>1)?$clog2(WARPS):1;
 reg [31:0] launch_args [0:3];
 reg perf_clear=0,perf_enable=0;
 wire [63:0] total_cycles,instructions_issued,active_lane_instructions;
 wire [63:0] scheduler_idle_cycles,memory_blocked_cycles;
 reg clk=0; always #5 clk=~clk;
 reg reset=1,launch_valid=0;
 reg [IW-1:0] launch_warp_id=0,debug_warp_id=0;
 reg [31:0] launch_pc=0;
 reg [LANES-1:0] launch_mask={LANES{1'b1}};
 reg [3:0] debug_register=3;
 wire [WARPS-1:0] running;
 wire memory_request_valid,memory_store,memory_response_ready;
 wire [31:0] memory_address,memory_write_data;
 reg memory_request_ready=0,memory_response_valid=0,memory_error=0;
 reg [31:0] memory_read_data=0;
 wire busy,fault;
 wire [31:0] fault_pc,debug_data[0:LANES-1];
 minimal_core #(.LANES(LANES),.WARPS(WARPS),.PROGRAM_DEPTH(32)) dut(.*);
 function automatic [31:0] enc(input integer op,d,a,b,imm);
 enc=(op<<26)|(d<<22)|(a<<18)|(b<<14)|(imm & 16383);
 endfunction
 task tick; begin @(posedge clk); #1; end endtask
 task wait_done;
 begin
   for(integer i=0;i<100;i=i+1) begin
     tick();
     if(fault) $fatal(1,"unexpected fault at %h",fault_pc);
     if(!busy) return;
   end
   $fatal(1,"timeout");
 end endtask
 initial begin
   // Constants -> addition -> immediate shift -> forward branch skips bad write.
   dut.program_rom.memory[0]=enc(12,1,0,0,2);
   dut.program_rom.memory[1]=enc(12,2,0,0,3);
   dut.program_rom.memory[2]=enc(0,3,1,2,0);
   dut.program_rom.memory[3]=enc(7,4,3,0,2);
   dut.program_rom.memory[4]=enc(21,0,0,0,1);
   dut.program_rom.memory[5]=enc(12,3,0,0,999);
   dut.program_rom.memory[6]=enc(22,0,0,0,0);
   tick(); @(negedge clk); reset=0;
   for(integer w=0;w<WARPS;w=w+1) begin
     launch_valid=1;launch_warp_id=w; tick(); @(negedge clk);
   end
   launch_valid=0;
   wait_done();
   for(integer w=0;w<WARPS;w=w+1) begin
     debug_warp_id=w;debug_register=3; #1;
     for(integer l=0;l<LANES;l=l+1) if(debug_data[l]!==5) $fatal(1,"ADD/branch result");
     debug_register=4; #1;
     for(integer l=0;l<LANES;l=l+1) if(debug_data[l]!==20) $fatal(1,"shift immediate result");
   end
   // Illegal instruction traps without advancing PC or writing.
   dut.program_rom.memory[8]=enc(63,3,0,0,0);
   @(negedge clk);launch_valid=1;launch_warp_id=0;launch_pc=32;
   tick(); @(negedge clk);launch_valid=0; tick();
   if(!fault || fault_pc!==32) $fatal(1,"unsupported opcode not trapped");
   debug_warp_id=0;debug_register=3; #1;
   for(integer l=0;l<LANES;l=l+1) if(debug_data[l]!==5) $fatal(1,"fault wrote register");
   repeat(3) tick();
   if(dut.pc[0]!==32) $fatal(1,"fault did not halt");
   @(negedge clk);reset=1;tick();
   if(fault || busy) $fatal(1,"reset failed");
   $display("PASS: minimal core LANES=%0d WARPS=%0d",LANES,WARPS);
   $finish;
 end
endmodule
