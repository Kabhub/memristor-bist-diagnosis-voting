`timescale 1ns/1ps
module q2_remap_campaign #(
    parameter integer WIDTH=16, SPARES=2
) (output logic finished=0);
    localparam integer CELLS=WIDTH+SPARES, AB=$clog2(CELLS);
    localparam integer N=1+2*CELLS*CELLS;
    localparam bit MATCHED=(SPARES==2*WIDTH);
    logic clk=0, reset, start, we;
    logic [WIDTH-1:0] data, alternating;
    logic [CELLS-1:0] ilrs, ihrs, expected_lrs, expected_hrs;
    wire busy, done, found, valid;
    wire [15:0] cycles;
    wire [WIDTH-1:0] out_word, reject;
    wire [CELLS-1:0] dlrs, dhrs, health;
    wire [WIDTH*AB-1:0] mapping;
    wire [WIDTH-1:0] proposed_word, proposed_reject, tmr_word;
    wire [CELLS-1:0] proposed_lrs, proposed_hrs;
    wire proposed_valid;
    q2_shared_spare_core #(.WIDTH(WIDTH),.SPARES(SPARES)) dut (
        .clk(clk),.reset(reset),.start(start),.operational_write_enable(we),
        .operational_write_data(data),.inject_lrs_fault_map(ilrs),.inject_hrs_fault_map(ihrs),
        .busy(busy),.done(done),.fault_found(found),.diagnosis_valid(valid),
        .bist_cycle_count(cycles),.corrected_data(out_word),.uncorrectable_map(reject),
        .lrs_fault_map(dlrs),.hrs_fault_map(dhrs),.cell_health_map(health),
        .logical_to_physical_map(mapping)
    );
    generate if (MATCHED) begin : gen_paired
        publication_scalable_memristor_core #(.WIDTH(WIDTH),.ARCHITECTURE(2)) proposal (
            .clk(clk),.reset(reset),.start(start),.operational_write_enable(we),
            .operational_write_data(data),.inject_lrs_fault_map(ilrs),.inject_hrs_fault_map(ihrs),
            .busy(),.done(),.fault_found(),.diagnosis_valid(proposed_valid),.bist_cycle_count(),
            .unprotected_data(),.standard_tmr_data(tmr_word),.corrected_data(proposed_word),
            .lrs_fault_map(proposed_lrs),.hrs_fault_map(proposed_hrs),
            .replica_health_map(),.uncorrectable_map(proposed_reject)
        );
    end else begin : gen_no_pair
        assign proposed_word='0; assign proposed_reject='0; assign tmr_word='0;
        assign proposed_lrs='0; assign proposed_hrs='0; assign proposed_valid=0;
    end endgenerate
    always #5 clk=~clk;
    integer fd, sf, pf, bf, n=0, singles=0, doubles=0;
    integer checks=0, passes=0, paired_checks=0, paired_passes=0, tmr_failures=0;
    integer a,b,pa,pb, addr;
    string prefix;
    logic [WIDTH*AB-1:0] expected_mapping;
    logic [WIDTH-1:0] expected_reject;

    task automatic fail(input string message);
        $display("REMAP FAILURE SPARES=%0d scenario=%0d: %s",SPARES,n,message);
        if (fd!=0) $fflush(fd);
        $fatal(1,"%s",message);
    endtask
    task automatic bist;
        integer elapsed;
        @(negedge clk);
        if (busy!==0 || done!==0) fail("Not idle before BIST");
        start=1;
        @(posedge clk); #1;
        if (valid!==0 || busy!==1) fail("BIST did not invalidate prior mapping");
        @(negedge clk); start=0;
        elapsed=1;
        while(done!==1 && elapsed<WIDTH+10) begin
            @(posedge clk); #1; elapsed=elapsed+1;
            if (done!==1 && valid!==0) fail("Allocation exposed a partial mapping");
        end
        if(done!==1 || valid!==1 || cycles!=WIDTH+5 || elapsed!=WIDTH+5)
            fail("Unexpected BIST-plus-allocation latency");
        if (dlrs!==expected_lrs || dhrs!==expected_hrs ||
            health!==~(expected_lrs|expected_hrs) || found!==( |(expected_lrs|expected_hrs)))
            fail("Actual BIST maps/polarities differ from injected cell faults");
        @(posedge clk); #1;
        if (done!==0 || busy!==0) fail("Controller did not return to IDLE");
    endtask
    task automatic verify_mapping;
        logic [SPARES-1:0] used;
        logic [CELLS-1:0] selected_cells;
        integer chosen;
        used='0; selected_cells='0; expected_mapping='0; expected_reject='0;
        for (integer i=0; i<WIDTH; i=i+1) begin
            addr=i;
            if (expected_lrs[i] || expected_hrs[i]) begin
                chosen=-1;
                for(integer s=0;s<SPARES;s=s+1)
                    if (chosen==-1 && !used[s] && !expected_lrs[WIDTH+s] && !expected_hrs[WIDTH+s]) chosen=s;
                if(chosen==-1) expected_reject[i]=1;
                else begin addr=WIDTH+chosen; used[chosen]=1; end
            end
            expected_mapping[i*AB +: AB]=AB'(addr);
            if (!expected_reject[i]) begin
                if (selected_cells[addr] || expected_lrs[addr] || expected_hrs[addr])
                    fail("Oracle allocation is unhealthy or aliases logical bits");
                selected_cells[addr]=1;
            end
        end
        if(mapping!==expected_mapping || reject!==expected_reject) fail("Incorrect greedy remap/rejection");
    endtask
    task automatic write_and_check(input logic [WIDTH-1:0] value, input bit count_check);
        @(negedge clk); data=value; we=1;
        @(posedge clk); #1;
        if ((out_word & ~expected_reject)!==(value & ~expected_reject) || reject!==expected_reject)
            fail("Healthy remapped word was not written/read correctly");
        @(negedge clk); we=0;
        @(posedge clk); #1;
        if ((out_word & ~expected_reject)!==(value & ~expected_reject)) fail("Data did not persist with writes disabled");
        if (mapping!==expected_mapping || dlrs!==expected_lrs || dhrs!==expected_hrs)
            fail("Operational write changed allocation or diagnosis");
        if(count_check) begin
            checks=checks+1; passes=passes+1;
            if(MATCHED) begin
                if(proposed_valid!==1 || proposed_lrs!==expected_lrs || proposed_hrs!==expected_hrs ||
                    proposed_word!==value || proposed_reject!=='0) fail("Paired proposal failed");
                paired_checks=paired_checks+1; paired_passes=paired_passes+1;
                if(tmr_word!==value) tmr_failures=tmr_failures+1;
            end
        end
    endtask
    task automatic scenario(input integer order, ca, cb, pola, polb);
        @(negedge clk); ilrs=expected_lrs; ihrs=expected_hrs;
        bist(); verify_mapping();
        if(expected_reject!=='0) fail("A zero/one/two-fault scenario was unrepairable");
        write_and_check('0,1); write_and_check('1,1);
        write_and_check(alternating,1); write_and_check(~alternating,1);
        $fdisplay(fd,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%h,%h,%h,%h,%h,%h,%0d,4,4,PASS",
            n,WIDTH,SPARES,CELLS,order,ca,cb,pola,polb,expected_lrs,expected_hrs,dlrs,dhrs,health,mapping,cycles);
        n=n+1;
        if(order==1) singles=singles+1;
        if(order==2) doubles=doubles+1;
        if(n%500==0) begin $fflush(fd); $display("SPARES=%0d progress %0d/%0d",SPARES,n,N); end
    endtask

    initial begin
        prefix=$sformatf("remap_w%0d_s%0d",WIDTH,SPARES);
        fd=$fopen({prefix,"_scenarios.csv"},"w");
        if(fd==0) $fatal(1,"Cannot open CSV");
        $fdisplay(fd,"scenario_id,width,spares,cells,fault_order,cell_a,cell_b,polarity_a,polarity_b,expected_lrs_map,expected_hrs_map,diagnosed_lrs_map,diagnosed_hrs_map,health_map,logical_to_physical_map,bist_and_allocation_cycles,word_checks,correct_word_checks,status");
        reset=1;start=0;we=0;data='0;ilrs='0;ihrs='0;expected_lrs='0;expected_hrs='0;
        for(integer i=0;i<WIDTH;i=i+1) alternating[i]=1'(i%2);
        repeat(3) @(posedge clk);
        @(negedge clk);reset=0;
        scenario(0,-1,-1,-1,-1);
        for(a=0;a<CELLS;a=a+1) for(pa=0;pa<2;pa=pa+1) begin
            expected_lrs='0;expected_hrs='0;
            if(pa==0) expected_lrs[a]=1;else expected_hrs[a]=1;
            scenario(1,a,-1,pa,-1);
        end
        for(a=0;a<CELLS-1;a=a+1) for(b=a+1;b<CELLS;b=b+1)
            for(pa=0;pa<2;pa=pa+1) for(pb=0;pb<2;pb=pb+1) begin
                expected_lrs='0;expected_hrs='0;
                if(pa==0) expected_lrs[a]=1;else expected_hrs[a]=1;
                if(pb==0) expected_lrs[b]=1;else expected_hrs[b]=1;
                scenario(2,a,b,pa,pb);
            end
        if(n!=N || singles!=2*CELLS || doubles!=2*CELLS*(CELLS-1) || checks!=4*N || passes!=4*N)
            fail("Exhaustive scenario/check count mismatch");
        if(MATCHED && (paired_checks!=4*N || paired_passes!=4*N || tmr_failures!=12*WIDTH))
            fail("Matched-cell paired comparison count mismatch");
        $fclose(fd);fd=0;
        bf=$fopen({prefix,"_boundary_checks.csv"},"w");
        if(bf==0) fail("Cannot open boundary CSV");
        $fdisplay(bf,"check,remap_result,proposal_result,status");
        // Three faulty primaries exhaust only the compact two-spare budget.
        @(negedge clk);expected_lrs='0;expected_hrs='0;
        expected_hrs[0]=1;expected_hrs[1]=1;expected_hrs[2]=1;
        ilrs=expected_lrs;ihrs=expected_hrs;bist();verify_mapping();
        if(!MATCHED && expected_reject!==WIDTH'(4)) fail("Two-spare exhaustion was not rejected");
        if(MATCHED && expected_reject!=='0) fail("Matched pool did not repair three primaries");
        write_and_check('0,0);write_and_check('1,0);
        if(MATCHED) $fdisplay(bf,"three_primary_faults,accepted_correct,accepted_correct,PASS");
        else $fdisplay(bf,"three_primary_faults,rejected_bit_2,not_instantiated,PASS");
        if(MATCHED) begin
            // These IDs are all three replicas of proposed bit 0, but are a
            // primary plus two spares in the remapper. Allocation layouts differ.
            @(negedge clk);expected_lrs='0;expected_hrs='0;
            expected_hrs[0]=1;expected_hrs[WIDTH]=1;expected_hrs[2*WIDTH]=1;
            ilrs=expected_lrs;ihrs=expected_hrs;bist();verify_mapping();
            write_and_check('1,0);
            if(proposed_reject!==WIDTH'(1)) fail("Proposal triple-replica boundary did not reject");
            $fdisplay(bf,"triple_replica_site_faults,accepted_correct,rejected_bit_0,PASS");
        end
        // Establish a clean map, then introduce a fault AFTER diagnosis.
        @(negedge clk);expected_lrs='0;expected_hrs='0;ilrs='0;ihrs='0;
        bist();verify_mapping();write_and_check('1,0);
        @(negedge clk);ihrs[0]=1;
        @(posedge clk);#1;
        if(out_word!==~WIDTH'(1) || reject!=='0 || dhrs!=='0)
            fail("Late-fault remap vulnerability check mismatch");
        if(MATCHED && (proposed_word!=='1 || proposed_reject!=='0)) fail("TMR did not mask one new fault");
        if(MATCHED) $fdisplay(bf,"new_fault_after_diagnosis,silent_wrong_bit_0,accepted_correct,PASS");
        else $fdisplay(bf,"new_fault_after_diagnosis,silent_wrong_bit_0,not_instantiated,PASS");
        expected_hrs[0]=1;bist();verify_mapping();write_and_check('1,0);
        $fdisplay(bf,"late_fault_after_retest,accepted_correct,not_scored,PASS");
        @(negedge clk);expected_lrs='0;expected_hrs='0;ilrs='0;ihrs='0;
        bist();verify_mapping();write_and_check(alternating,0);
        $fdisplay(bf,"clear_fault_maps_and_remap,accepted_correct,not_scored,PASS");
        $fclose(bf);
        sf=$fopen({prefix,"_summary.csv"},"w");
        if(sf==0) fail("Cannot open summary");
        $fdisplay(sf,"width,spares,cells,scenarios,single_scenarios,double_scenarios,exactly_localized,word_checks,correct_word_checks,paired_proposed_checks,paired_proposed_correct,paired_tmr_failures,bist_diagnosis_cycles,allocation_cycles,total_test_cycles,boundary_checks_passed,status");
        $fdisplay(sf,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,5,%0d,%0d,1,PASS",
            WIDTH,SPARES,CELLS,n,singles,doubles,n-1,checks,passes,paired_checks,paired_passes,tmr_failures,WIDTH,WIDTH+5);
        $fclose(sf);
        pf=$fopen({prefix,"_PASS.txt"},"w");
        if(pf==0) fail("Cannot open PASS marker");
        $fdisplay(pf,"ALL %0d REMAP SCENARIOS PASSED: WIDTH=%0d; SPARES=%0d; WORD_CHECKS=%0d",n,WIDTH,SPARES,checks);
        $fclose(pf);
        $display("ALL %0d REMAP SCENARIOS PASSED: SPARES=%0d; checks=%0d; latency=%0d",n,SPARES,checks,WIDTH+5);
        finished=1;
    end
endmodule
module tb_q2_remap_w16;
    wire compact_done, matched_done;
    q2_remap_campaign #(.WIDTH(16),.SPARES(2)) compact(compact_done);
    q2_remap_campaign #(.WIDTH(16),.SPARES(32)) matched(matched_done);
    initial begin
        wait(compact_done && matched_done);
        $display("ALL DEFECT-AWARE BASELINE TESTS PASSED");
        $finish;
    end
    initial begin #10000000; $fatal(1,"Baseline campaign timeout"); end
endmodule
