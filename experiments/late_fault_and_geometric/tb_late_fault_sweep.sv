`timescale 1ns/1ps
module late_fault_campaign #(parameter integer SPARES=-1)(output logic finished=0);
 localparam integer W=16,C=(SPARES<0)?48:16+SPARES;
 localparam bit PROPOSAL=(SPARES<0);
 logic clk=0,reset=1,start=0,we=0;
 logic [W-1:0] data=0;
 logic [C-1:0] ilrs=0,ihrs=0;
 wire valid,done,busy;
 wire [15:0] cycles;
 wire [W-1:0] word_out,reject;
 wire [C-1:0] dlrs,dhrs;
 generate if(PROPOSAL) begin
  publication_scalable_memristor_core #(.WIDTH(W),.ARCHITECTURE(2)) dut(
   .clk(clk),.reset(reset),.start(start),.operational_write_enable(we),.operational_write_data(data),
   .inject_lrs_fault_map(ilrs),.inject_hrs_fault_map(ihrs),.busy(busy),.done(done),.fault_found(),
   .diagnosis_valid(valid),.bist_cycle_count(cycles),.corrected_data(word_out),.uncorrectable_map(reject),
   .unprotected_data(),.standard_tmr_data(),.lrs_fault_map(dlrs),.hrs_fault_map(dhrs),.replica_health_map());
 end else begin
  q2_shared_spare_core #(.WIDTH(W),.SPARES(SPARES)) dut(
   .clk(clk),.reset(reset),.start(start),.operational_write_enable(we),.operational_write_data(data),
   .inject_lrs_fault_map(ilrs),.inject_hrs_fault_map(ihrs),.busy(busy),.done(done),.fault_found(),
   .diagnosis_valid(valid),.bist_cycle_count(cycles),.corrected_data(word_out),.uncorrectable_map(reject),
   .lrs_fault_map(dlrs),.hrs_fault_map(dhrs),.cell_health_map(),.logical_to_physical_map());
 end endgenerate
 always #5 clk=~clk;
 integer fd,sf,pf,id=0,accepted_correct=0,sdc=0,rejected=0,recovered=0;
 integer cell_id,polarity,bg;
 logic [W-1:0] expected_word;
 string scheme;
 task automatic bist;
  integer wait_cycles;
  @(negedge clk);start=1;
  @(posedge clk);#1;if(valid!==0)$fatal(1,"BIST did not invalidate diagnosis");
  @(negedge clk);start=0;wait_cycles=1;
  while(done!==1 && wait_cycles<40)begin @(posedge clk);#1;wait_cycles++;end
  if(done!==1 || valid!==1 || cycles!=(PROPOSAL?5:21))$fatal(1,"BIST completion/latency failure");
  if(dlrs!==ilrs || dhrs!==ihrs)$fatal(1,"Incorrect actual diagnosis");
  @(posedge clk);#1;
 endtask
 task automatic write_word;
  @(negedge clk);we=1;
  @(posedge clk);#1;
  @(negedge clk);we=0;#1;
  if(valid!==1 || reject!=='0 || word_out!==data)$fatal(1,"Write failed after BIST");
 endtask
 initial begin
  scheme=PROPOSAL?"proposed":((SPARES==2)?"remap_two_spares":"remap_matched_cells");
  fd=$fopen({scheme,"_late_scenarios.csv"},"w");
  if(fd==0)$fatal(1,"Cannot open scenario CSV");
  $fdisplay(fd,"id,scheme,cells,cell_id,polarity,background,data,observed,diagnosis_valid,reject_map,diagnosed_lrs_map,diagnosed_hrs_map,accepted_correct,silent_wrong,retest_correct,status");
  for(cell_id=0;cell_id<C;cell_id++)for(polarity=0;polarity<2;polarity++)for(bg=0;bg<4;bg++)begin
   @(negedge clk);reset=1;ilrs=0;ihrs=0;start=0;we=0;
   repeat(3)@(posedge clk);
   @(negedge clk);reset=0;
   bist();
   case(bg)0:data='0;1:data='1;2:data=16'haaaa;default:data=16'h5555;endcase
   write_word();
   @(negedge clk);if(polarity==0)ilrs[cell_id]=1;else ihrs[cell_id]=1;
   #1;
   expected_word=data;
   if(!PROPOSAL && cell_id<W)expected_word[cell_id]=(polarity==0);
   if(valid!==1 || reject!=='0 || dlrs!=='0 || dhrs!=='0 || word_out!==expected_word)
    $fatal(1,"Late-fault output or stale-map assertion failed scheme=%s cell=%0d pol=%0d bg=%0d",scheme,cell_id,polarity,bg);
   if(word_out===data)accepted_correct++;else sdc++;
   $fwrite(fd,"%0d,%s,%0d,%0d,%0d,%0d,%h,%h,%0d,%h,%h,%h,%0d,%0d,",id,scheme,C,cell_id,polarity,bg,data,word_out,valid,reject,dlrs,dhrs,(word_out===data),(word_out!==data));
   bist();write_word();recovered++;
   $fdisplay(fd,"1,PASS");id++;
  end
  if(id!=C*8 || accepted_correct+sdc+rejected!=id || recovered!=id)$fatal(1,"Summary count failure");
  sf=$fopen({scheme,"_late_summary.csv"},"w");
  $fdisplay(sf,"scheme,width,cells,checks,accepted_correct,silent_wrong,rejected,retest_correct,status");
  $fdisplay(sf,"%s,16,%0d,%0d,%0d,%0d,%0d,%0d,PASS",scheme,C,id,accepted_correct,sdc,rejected,recovered);$fclose(sf);
  pf=$fopen({scheme,"_late_PASS.txt"},"w");$fdisplay(pf,"ALL %0d LATE-FAULT CHECKS PASSED: %s",id,scheme);$fclose(pf);$fclose(fd);
  $display("LATE-FAULT SWEEP PASSED %s: %0d checks, %0d accepted correct, %0d silent wrong, %0d retest correct",scheme,id,accepted_correct,sdc,recovered);
  finished=1;
 end
endmodule
module tb_late_fault_sweep;
 wire p,c,m;
 late_fault_campaign #(.SPARES(-1)) proposal(p);
 late_fault_campaign #(.SPARES(2)) compact(c);
 late_fault_campaign #(.SPARES(32)) matched(m);
 initial begin wait(p&&c&&m);$display("ALL LATE-FAULT SWEEPS PASSED");$finish;end
 initial begin #1000000;$fatal(1,"Sweep timeout");end
endmodule
