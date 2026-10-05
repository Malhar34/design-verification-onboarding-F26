/*
 * Top-level testbench
 */
module cpu_tb_top;

    import cpu_tb_pkg::*;

    parameter int DataSize = DATA_W;
    parameter int AddrSize = XBAR_AW;

    string requested_seed = "default";

    int assertion_errors = 0;

    logic clk = 0;
    always #5 clk = ~clk;

    // IF instantiation
    cpu_if #(.DataSize(DataSize), .AddrSize(AddrSize)) cpu_if(.clk(clk));

    // DUT instantiation
    chip_top dut (
        .clk_i(clk),
        .rst_i(cpu_if.cpu.reset),
        .en_cpu_i(cpu_if.cpu.en_cpu),
        .halt_cpu_i(cpu_if.cpu.halt_cpu),
        .cpu_halted_o(cpu_if.cpu.cpu_halted),
        .addr_i(cpu_if.cpu.addr),
        .wdata_i(cpu_if.cpu.wdata),
        .w_en_i(cpu_if.cpu.w_en),
        .r_en_i(cpu_if.cpu.r_en),
        .rdata_o(cpu_if.cpu.rdata),
        .rready_o(cpu_if.cpu.rready)
    );

    // Observation signals from the DUT memory path
    assign cpu_if.cpu_active     = dut.cpu_enable_q;
    assign cpu_if.dsram_en       = dut.dsram_en;
    assign cpu_if.dsram_write_en = dut.dsram_write_en;
    assign cpu_if.dsram_addr     = dut.dsram_addr;
    assign cpu_if.dsram_wdata    = dut.dsram_wdata;
    assign cpu_if.dsram_rdata    = dut.dsram_rdata;

    cpu_tb_pkg::cpu_sequencer #(.DataSize(DataSize), .AddrSize(AddrSize)) seqr;
    cpu_tb_pkg::cpu_driver #(.DataSize(DataSize), .AddrSize(AddrSize))    drv;
    cpu_tb_pkg::cpu_monitor #(.DataSize(DataSize), .AddrSize(AddrSize))   mon;
    cpu_tb_pkg::cpu_sb #(.DataSize(DataSize), .AddrSize(AddrSize))        sb;

    // Record failed assertion
    function void assertion_fail(input string message);
        assertion_errors++;
        $error($stime, " ASSERT: %s\n", message);
    endfunction: assertion_fail

    // Initialize both memories through the DUT's external memory port
    task automatic init_memories();
        $display($stime, " TB: Initializing instruction and data memories\n");
        mon.log_transactions = 1'b0;
        sb.log_transactions = 1'b0;
        for (int i = 0; i < ISRAM_WORDS; i++) begin
            seqr.send_write_trans(word_addr(ISRAM_BASE, i), EBREAK_WORD);
        end
        for (int i = 0; i < DSRAM_WORDS; i++) begin
            seqr.send_write_trans(word_addr(DSRAM_BASE, i), $urandom());
        end
        seqr.wait_for_empty();
        repeat (2) @(cpu_if.cb);
        mon.log_transactions = 1'b1;
        sb.log_transactions = 1'b1;
        $display($stime, " TB: Memory initialization complete\n");
    endtask: init_memories

    // Queue external reads on a memory window
    task automatic readback(input int window, input int num_words, input int start_word=0);
        logic [AddrSize-1:0] base;

        case (window)
            0: base = ISRAM_BASE;
            1: base = DSRAM_BASE;
            2: base = REG_BASE;
            default: base = REG_BASE;
        endcase

        for (int i = 0; i < num_words; i++) begin
            seqr.send_read_trans(word_addr(base, start_word + i));
        end
        seqr.wait_for_empty();
        repeat (4) @(cpu_if.cb);
    endtask: readback

    task automatic preload_dmem(input logic [31:0] values [$], input int start_word=0);
        foreach (values[i]) begin
            seqr.send_write_trans(word_addr(DSRAM_BASE, start_word + i), values[i]);
        end
        seqr.wait_for_empty();
        repeat (2) @(cpu_if.cb);
    endtask: preload_dmem

    // Run a directed test
    task automatic run_directed(input string name, const ref logic [31:0] program_words [$],
            input int max_cycles=2000, input int dmem_words=16);
        $display("");
        $display("=================================================================");
        $display(" TEST: %s", name);
        $display("=================================================================");
        sb.set_test(name);

        drv.reset_task();
        seqr.load_program(program_words);
        seqr.wait_for_empty();
        repeat (2) @(cpu_if.cb);
        drv.run_program(max_cycles);

        if (drv.last_run_completed) begin
            readback(2, REG_COUNT);
            readback(1, dmem_words);
        end else begin
            $display($stime, " TB: Skipping %s readback after CPU timeout\n", name);
            drv.reset_task();
        end
    endtask: run_directed

    // Basic smoke test for loading, running, and observing a program that halts
    task automatic run_smoke_test();
        logic [31:0] smoke_prog [$];
        smoke_prog = '{ EBREAK_WORD };
        run_directed("smoke_ebreak", smoke_prog, 100, 1);
    endtask: run_smoke_test

    // Smoke test for stopping the CPU from outside the program
    // Readback is skipped because the CPU stops before the program completes
    task automatic run_external_halt_smoke();
        logic [31:0] long_prog [$];

        for (int i = 0; i < 32; i++) begin
            long_prog.push_back(asm_instr(.op(OP_ADDI), .rd(1), .rs1(1), .imm(1)));
        end
        long_prog.push_back(EBREAK_WORD);

        $display("");
        $display("=================================================================");
        $display(" TEST: smoke_external_halt");
        $display("=================================================================");
        sb.set_test("smoke_external_halt");

        drv.reset_task();
        seqr.load_program(long_prog);
        seqr.wait_for_empty();
        repeat (2) @(cpu_if.cb);
        drv.start_cpu();
        repeat (12) @(cpu_if.cb);
        drv.halt_cpu_now();
        drv.reset_task();
    endtask: run_external_halt_smoke

    

    // TEST PROGRAM
    logic [31:0] prog [$];
    logic [31:0] data [$];

    int NUM_RANDOM_PROGRAMS = 20;
    int NUM_RANDOM_XBAR = 300;

    initial begin
        int total_errors;

        mon = new(cpu_if);
        sb = new(mon.mon_box);
        seqr = new();
        drv = new(cpu_if, seqr.xbar_box);

        void'($value$plusargs("NUM_RANDOM_PROGRAMS=%d", NUM_RANDOM_PROGRAMS));
        void'($value$plusargs("NUM_RANDOM_XBAR=%d", NUM_RANDOM_XBAR));
        if ($test$plusargs("REF_TRACE")) begin
            sb.ref_model.trace = 1'b1;
        end

        fork
            mon.run();
            sb.run();
            drv.run();
        join_none

        drv.reset_task();
        init_memories();

        run_smoke_test();
        run_external_halt_smoke();


        // DIRECTED TESTS
	begin
	   logic [31:0] prog [$];

           drv.reset_task();
           init_memories();

           // Use the existing helpers
	   // Test: addi_imm_limits (Sign extension limits)
	   prog = '{
               asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(2047)),
               asm_instr(.op(OP_ADDI), .rd(2), .rs1(0), .imm(-2048)),
	       asm_instr(.op(OP_ADDI), .rd(3), .rs1(0), .imm(-1)),
               EBREAK_WORD
           };
	   // Environemtn's helper
	   run_directed("addi_imm_limits", prog);
	
	   // Test: raw_dependency_chain (Read after write)
	   prog = '{
	       asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(7)),
	       asm_instr(.op(OP_ADDI), .rd(2), .rs1(1), .imm(-3)),
	       EBREAK_WORD
	   };
	   run_directed("raw_dependency_chain", prog);
	
	   //feedback test: External memory boundaries( MAx 4KB SRAM word address)
	   drv.xbar_write(32'h0000_0FFC, 32'hDEAD_BEEF);
	   drv.xbar_read(32'h0000_0FFC);

	   // feedback Test: External halt request against an infitnite loop
	   prog = '{
	       asm_instr(.op(OP_BEQ), .rs1(0), .rs2(0), .imm(0)),
	       EBREAK_WORD
	   };
	   drv.start_cpu(); // start waiting for halt
	   #50; // goes through the loop for a little bit
	   drv.halt_cpu_now(); //Interupt the infiti nite loop externally

	   // Feedback Tets: Reset during CPU active
	   drv. start_cpu();
	   #30;
	   cpu_if.reset = 1'b1;
	   #20;
	   cpu_if.reset = 1'b0;
        
           // Example Test: addi with a positive immediate
            prog = '{
               asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(5)),
               asm_instr(.op(OP_ADDI), .rd(2), .rs1(1), .imm(100)),
               EBREAK_WORD
           };
           run_directed("addi_positive", prog);
	
	end


        // CONSTRAINED-RANDOM TESTS
        // Use the existing helpers
	for (int p = 0; p < 20; p++) begin
        int len;
        len = $urandom_range(5, 30);

        $display(" RANDOM PROGRAM %0d of 20, %0d instruction", p, len);
        sb.set_test($sformatf("random_%0d", p));

        drv.reset_task();
        init_memories();
        seqr.gen_program(len);
        seqr.wait_for_empty();
        repeat (2) @(cpu_if.cb);
        drv.run_program(2000);

        if (drv.last_run_completed) begin
            readback(2, REG_COUNT);
            readback(1, 16);
        end else begin
            $display($stime, " TB: Skipping random_%0d readback after CPU timeout\n", p);
            drv.reset_task();
        end
    end
	seqr.gen_xbar(NUM_RANDOM_XBAR);


        // TEST FINISH
        repeat (20) @(cpu_if.cb);
        total_errors = sb.errors + drv.timeouts + mon.errors + assertion_errors;
        if (sb.checks == 0) begin
            $error("Testbench performed zero checks; no results were verified");
        end

        $display("=================================================================");
        $display("  Scoreboard mismatches : %0d", sb.errors);
        $display("  Driver timeouts       : %0d", drv.timeouts);
        $display("  Monitor protocol errs : %0d", mon.errors);
        $display("  Assertion failures    : %0d", assertion_errors);
        $display("=================================================================");
        $display();

        if (total_errors == 0) begin
            $display("=================================================================");
            $display(" TEST PASSED!");
            $display("=================================================================");
        end else begin
            $display("=================================================================");
            $display(" TEST FAILED: %0d error(s)", total_errors);
            $display("=================================================================");
        end
        $finish;
    end

    // Stop a broken DUT or testbench instead of letting the simulation run forever
    initial begin
        #10ms;
        $display(" TEST FAILED - global timeout");
        $fatal(1, "global timeout");
    end

    initial begin
        void'($value$plusargs("SEED_LABEL=%s", requested_seed));
        if ($test$plusargs("BUG_HUNT_WAVES")) begin
            $shm_open("bug_hunt_waves.shm");
        end else begin
            $shm_open("waves.shm");
        end
        $shm_probe("AC");
    end

    wire rst = cpu_if.reset;

    // 3.1: No_Store_TO_DATA0 - The CPU never asserts a data-SRAM write to word address 0
    NO_STORE_TO_DATA0:
      assert property (@(posedge cpu_if.clk) disable iff (rst)
	(cpu_if.cpu_active && cpu_if.dsram_en && cpu_if.dsram_write_en) |-> (cpu_if.dsram_addr != 10'd0))
      else $error("Assertion Violation: CPU asserted a data-SRAM write to word address 0");

   // 3.2: NO_MEM_ACCESS_WHEN_IDLE - The CPU does not drive a data-SRAM access while cpu_active is low
   NO_MEM_ACCESS_WHEN_IDLE:
     assert property (@(posedge cpu_if.clk) disable iff (rst)
	 (!cpu_if.cpu_active && !cpu_if.r_en && !cpu_if.w_en) |-> (!cpu_if.dsram_en))
     else $error("Assertion Violation: CPU drove a data-SRAM access while not active");

    // Example assertion
    // It checks one interface rule and sends failures through the testbench counter
    NO_SIMULTANEOUS_READ_WRITE:
        assert property (@(posedge clk) disable iff (rst)
            !(cpu_if.w_en && cpu_if.r_en))
        else assertion_fail("w_en_i and r_en_i were asserted together");

endmodule: cpu_tb_top
