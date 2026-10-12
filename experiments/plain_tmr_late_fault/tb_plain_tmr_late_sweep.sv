`timescale 1ns/1ps
module tb_plain_tmr_late_sweep;
 localparam integer W=16,C=48;
 logic clk=0,reset=1,we=0;
 logic [15:0] data=0;
 logic [47:0] lrs=0,hrs=0;
 wire [15:0] observed;
 wire uncorrectable;
 review_tmr_baseline #(.WIDTH(W),.SELF_PURGING(0)) dut(
 .clk(clk),.reset(reset),.clear_purge(1'b0),.observe(1'b0),
 .write_enable(we),.write_data(data),.inject_lrs_fault_map(lrs),.inject_hrs_fault_map(hrs),
 .corrected_data(observed),.active_replica_mask(),.disagreement_detected(),.purge_event(),.uncorrectable(uncorrectable));
 always #5 clk=~clk;
 integer fd,sf,pf,n=0,good=0,cell_id,polarity,bg;
 initial begin
  fd=$fopen("plain_tmr_late_scenarios.csv","w");
  if(fd==0)$fatal(1,"CSV open failed");
  $fdisplay(fd,"id,cell_id,polarity,background,written,observed,uncorrectable,accepted_correct,status");
  for(cell_id=0;cell_id<C;cell_id++)for(polarity=0;polarity<2;polarity++)for(bg=0;bg<4;bg++)begin
   @(negedge clk);reset=1;we=0;lrs=0;hrs=0;
   repeat(3)@(posedge clk);
   @(negedge clk);reset=0;
   case(bg)0:data=16'h0000;1:data=16'hffff;2:data=16'haaaa;default:data=16'h5555;endcase
   we=1;@(posedge clk);#1;
   @(negedge clk);we=0;
   if(polarity==0)lrs[cell_id]=1;else hrs[cell_id]=1;
   #1;
   if(observed!==data || uncorrectable!==0)$fatal(1,"Plain TMR single-new-fault failure");
   $fdisplay(fd,"%0d,%0d,%0d,%0d,%h,%h,%0d,1,PASS",n,cell_id,polarity,bg,data,observed,uncorrectable);
   good++;n++;
  end
  if(n!=384||good!=384)$fatal(1,"Unexpected counts");
  sf=$fopen("plain_tmr_late_summary.csv","w");
  $fdisplay(sf,"scheme,width,cells,checks,accepted_correct,silent_wrong,rejected,status");
  $fdisplay(sf,"plain_tmr,16,48,%0d,%0d,0,0,PASS",n,good);$fclose(sf);
  pf=$fopen("plain_tmr_late_PASS.txt","w");$fdisplay(pf,"ALL 384 PLAIN TMR SINGLE-NEW-FAULT CHECKS PASSED");$fclose(pf);$fclose(fd);
  $display("ALL 384 PLAIN TMR SINGLE-NEW-FAULT CHECKS PASSED");$finish;
 end
endmodule
