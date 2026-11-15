`timescale 1ns/1ps
module instruction_frontend_tb;
 reg [31:0] instruction, addr=0;
 wire [5:0] opcode;
 wire [3:0] rd,rs1,rs2,alu_ctrl;
 wire illegal_instruction,register_write,use_immediate;
 wire memory_read,memory_write,branch,branch_any,warp_finish,warp_spawn,barrier,present;
 wire mask_set,mask_push,mask_pop,mask_replace,ballot,special_read;
 wire [1:0] immediate_mode;
 wire [31:0] immediate,rom_instruction;
 wire instruction_valid;
 instruction_decoder decoder(.*);
 immediate_generator immediates(.*);
 instruction_memory #(.DEPTH(3)) rom(.addr(addr),.instruction(rom_instruction),.instruction_valid(instruction_valid));
 task check(input bit ok,input string msg);
 begin if(!ok) $fatal(1,"%s",msg); end endtask
 initial begin
   for(integer op=0;op<64;op=op+1) begin
     instruction=(op<<26)|(3<<22)|(5<<18)|(7<<14)|14'h3fff; #1;
     check(opcode===op && rd===3 && rs1===5 && rs2===7,"fields");
     check(illegal_instruction===(op>=28),"illegal opcode");
     if(op<10) check(register_write && alu_ctrl==op,"ALU decode");
     if(op>=28) check(!register_write && !memory_write && !branch && !warp_finish,"illegal side effects");
   end
   instruction=(12<<26)|14'h3fff; #1;
   check(register_write && immediate===32'h3fff,"LDI unsigned");
   instruction=(13<<26)|18'h3ffff; #1;
   check(immediate===32'hffffc000,"LUI upper payload");
   instruction=(25<<26)|14'h3fff; #1;
   check(memory_read && register_write && immediate===32'hffffffff,"load negative offset");
   instruction=(26<<26)|14'h2000; #1;
   check(memory_write && !register_write && immediate===32'hffffe000,"store negative limit");
   instruction=(21<<26)|14'h1fff; #1;
   check(branch && immediate===8191,"branch positive limit");
   instruction=(20<<26); #1; check(branch_any,"conditional branch");
   instruction=(22<<26); #1; check(warp_finish,"finish");
   instruction=(7<<26)|31; #1; check(use_immediate && immediate===31,"shift immediate");
   rom.memory[0]=32'h12345678; rom.memory[2]=32'habcdef01;
   addr=0; #1; check(instruction_valid && rom_instruction===32'h12345678,"ROM first word");
   addr=8; #1; check(instruction_valid && rom_instruction===32'habcdef01,"ROM last word");
   addr=4; #1; check(instruction_valid,"ROM middle word address");
   addr=12; #1; check(!instruction_valid && rom_instruction===0,"ROM bounds");
   addr=1; #1; check(!instruction_valid && rom_instruction===0,"ROM alignment");
   addr=32'hfffffffc; #1; check(!instruction_valid,"ROM high address");
   $display("PASS: decoder 64 opcodes, immediate boundaries, ROM alignment/bounds");
   $finish;
 end
endmodule
