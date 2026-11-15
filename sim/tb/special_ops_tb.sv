`timescale 1ns/1ps
module special_ops_tb;
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
   for(integer i=0;i<4;i=i+1)dut.core.program_rom.memory[i]=enc(14,i+1,0,0,i);
   for(integer i=0;i<4;i=i+1)dut.core.program_rom.memory[i+4]=enc(14,i+5,0,0,16+i);
   dut.core.program_rom.memory[8]=enc(10,9,5,6,0);
   dut.core.program_rom.memory[9]=enc(11,10,5,6,0);
   dut.core.program_rom.memory[10]=enc(7,11,1,0,2);
   dut.core.program_rom.memory[11]=enc(0,11,11,7,0);
   dut.core.program_rom.memory[12]=enc(26,0,11,1,0);
   dut.core.program_rom.memory[13]=enc(25,12,11,0,0);
   dut.core.program_rom.memory[14]=enc(14,0,0,0,16);
   dut.core.program_rom.memory[15]=enc(22,0,0,0,0);
   tick();@(negedge clk);reset=0;
   for(integer w=0;w<WARPS;w=w+1)begin
     launch_valid=1;launch_warp_id=w;
     launch_args[0]=32'hfffffff0-w;launch_args[1]=100+w;
     launch_args[2]=w*LANES*4;launch_args[3]=32'habcdef00+w;
     tick();@(negedge clk);
   end
   launch_valid=0;
   for(integer a=0;a<4;a=a+1)launch_args[a]=0; // Captured launch values must survive.
   run_done();
   for(integer w=0;w<WARPS;w=w+1)
     for(integer l=0;l<LANES;l=l+1)begin
       expect_reg(w,0,l,0);expect_reg(w,1,l,l);expect_reg(w,2,l,w);
       expect_reg(w,3,l,LANES);expect_reg(w,4,l,WARPS);
       expect_reg(w,5,l,32'hfffffff0-w);expect_reg(w,6,l,100+w);
       expect_reg(w,7,l,w*LANES*4);expect_reg(w,8,l,32'habcdef00+w);
       expect_reg(w,9,l,32'hfffffff0-w);expect_reg(w,10,l,100+w);
       expect_reg(w,12,l,l);
       if(dut.data_ram.memory[w*LANES+l]!==l)$fatal(1,"per-lane address/store");
     end
   // Re-launch with a partial mask: masked lanes retain prior RDSR results.
   @(negedge clk);launch_valid=1;launch_warp_id=0;
   for(integer l=0;l<LANES;l=l+1)launch_mask[l]=(l%2==0);
   launch_args[0]=32'hffffff00;launch_args[1]=77;launch_args[2]=0;launch_args[3]=999;
   tick();@(negedge clk);launch_valid=0;run_done();
   for(integer l=0;l<LANES;l=l+1)begin
     expect_reg(0,5,l,(l%2==0)?32'hffffff00:32'hfffffff0);
     expect_reg(0,9,l,(l%2==0)?32'hffffff00:32'hfffffff0);
     expect_reg(0,10,l,(l%2==0)?77:100);
   end
   // Invalid selector faults without committing rd.
   dut.core.program_rom.memory[32]=enc(14,5,0,0,4);
   @(negedge clk);launch_valid=1;launch_pc=128;
   tick();@(negedge clk);launch_valid=0;tick();
   if(!fault || fault_pc!==128)$fatal(1,"invalid selector must fault");
   expect_reg(0,5,0,32'hffffff00);
   $display("PASS: RDSR/MIN/MAX LANES=%0d WARPS=%0d checks=%0d",LANES,WARPS,checks);$finish;
 end
 initial begin #1000000;$fatal(1,"timeout");end
endmodule
