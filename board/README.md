# ZedBoard demonstration

Part xc7z020clg484-1; Vivado 2026.1; 100-MHz GCLK.
For the double-fault demo, create a new Vivado RTL project and add memristor_cell.sv, memristor_bist_8bit.sv, tmr_memristor_bit.sv, tmr_memristor_memory_8bit.sv, zedboard_oled_status.sv and zedboard_memristor_q2_demo_top.sv. Set the double-fault top and add zedboard_memristor.xdc. Synthesize, implement and generate the bitstream; use Hardware Manager to program the board. Check DRC and both setup/hold timing rather than relying on bitstream generation alone.

For behavioural simulation add tb_zedboard_memristor_q2_demo_top.sv to simulation sources, set that simulation top and run all. This testbench checks six representative cases; a simulator PASS is distinct from a physical board observation.

Controls from the supplied double-fault top:
- SW0 enables the double fault.
- SW1: 0 stuck-LRS, 1 stuck-HRS.
- SW4:SW2 select logical bit 0-7.
- SW6:SW5: 00 A+B, 01 A+C, 10 B+C, 11 reserved/no fault.
- SW7: 0 corrected-output/health view, 1 comparison view.
- BTNU resets test logic; BTNC starts BIST and the automatic challenge write; BTNR toggles OLED power.

The separate zedboard_memristor_top and its testbench preserve the earlier single-fault design. Do not interchange its controls with the double-fault top. Board photographs remain author-deferred. Recorded board-top implementation reports are archived under archive/initial_campaigns/zedboard_q2_demo_reports.
