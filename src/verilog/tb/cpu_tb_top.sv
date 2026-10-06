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

       prog = '{
            asm_instr(.op(OP_SW), .rs1(0), .rs2(0), .imm(4)), 
            EBREAK_WORD
       };
       run_directed("min_one_store", prog);

       prog = '{
            asm_instr(.op(OP_SW), .rs1(0), .rs2(2), .imm(1060)),
            asm_instr(.op(OP_SW), .rs1(0), .rs2(4), .imm(220)),
            asm_instr(.op(OP_SW), .rs1(4), .rs2(3), .imm(1696)),
            EBREAK_WORD
       };
       run_directed("min_three_stores", prog);

       prog = '{
            asm_instr(.op(OP_LW), .rd(3), .rs1(0), .imm(900)),
            EBREAK_WORD
       };
       run_directed("min_lw_x3_900", prog);

       prog = '{
            asm_instr(.op(OP_LW), .rd(6), .rs1(0), .imm(900)),
            EBREAK_WORD
       };
       run_directed("min_lw_x6_900", prog);

       prog = '{
            asm_instr(.op(OP_LW), .rd(3), .rs1(0), .imm(504)),
            EBREAK_WORD
       };
       run_directed("min_lw_x3_504", prog);

       prog = '{
            asm_instr(.op(OP_LW), .rd(6), .rs1(3), .imm(504)),
            asm_instr(.op(OP_LW), .rd(3), .rs1(7), .imm(900)),
            EBREAK_WORD
       };
       run_directed("min_lw_pair", prog);
       prog = '{
            asm_instr(.op(OP_LW), .rd(6), .rs1(3), .imm(504)),
            asm_instr(.op(OP_BEQ), .rd(7), .rs1(6), .imm(8)),
            asm_instr(.op(OP_LW), .rd(3), .rs1(7), .imm(900)),
            EBREAK_WORD
       };
       run_directed("min_lw_branch", prog);

       prog = '{
            asm_instr(.op(OP_ADDI), .rd(6), .rs1(0), .imm(1)),
            asm_instr(.op(OP_BEQ), .rs1(7), .rs2(6), .imm(8)),
            asm_instr(.op(OP_ADDI), .rd(3), .rs1(0), .imm(5)),
            EBREAK_WORD
       };
       run_directed("min_beq_rs1zero", prog);

       prog = '{
            asm_instr(.op(OP_ADDI), .rd(6), .rs1(0), .imm(1)),
            asm_instr(.op(OP_BEQ), .rs1(6), .rs2(7), .imm(8)),
            asm_instr(.op(OP_ADDI), .rd(3), .rs1(0), .imm(5)),
            EBREAK_WORD
       };
       run_directed("min_beq_rs2zero", prog);

       prog = '{
            asm_instr(.op(OP_ADDI), .rd(6), .rs1(0), .imm(1)),
            asm_instr(.op(OP_ADDI), .rd(7), .rs1(0), .imm(2)),
            asm_instr(.op(OP_BEQ), .rs1(7), .rs2(6), .imm(8)),
            asm_instr(.op(OP_ADDI), .rd(3), .rs1(0), .imm(5)),
            EBREAK_WORD
       };
       run_directed("min_beq_nonzero", prog);

       prog = '{
            asm_instr(.op(OP_LW), .rd(6), .rs1(0), .imm(504)),
            asm_instr(.op(OP_BEQ), .rs1(7), .rs2(6), .imm(8)),
            asm_instr(.op(OP_ADDI), .rd(3), .rs1(0), .imm(5)),
            EBREAK_WORD
       };
       run_directed("min_lwuse_beq", prog);

       prog = '{
            asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(1)),
            asm_instr(.op(OP_ADDI), .rd(2), .rs1(0), .imm(31)),
            asm_instr(.op(OP_SLL), .rd(6), .rs1(1), .rs2(2)),
            asm_instr(.op(OP_BEQ), .rs1(7), .rs2(6), .imm(8)),
            asm_instr(.op(OP_ADDI), .rd(3), .rs1(0), .imm(5)),
            EBREAK_WORD
       };
       run_directed("min_beq_highbit", prog);

       prog = '{
            asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(1)),
            asm_instr(.op(OP_ADDI), .rd(2), .rs1(0), .imm(30)),
            asm_instr(.op(OP_SLL), .rd(6), .rs1(1), .rs2(2)),
            asm_instr(.op(OP_BEQ), .rs1(7), .rs2(6), .imm(8)),
            asm_instr(.op(OP_ADDI), .rd(3), .rs1(0), .imm(5)),
            EBREAK_WORD
        };
        run_directed("min_beq_bit30", prog);

        prog = '{
            asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(1)),
            asm_instr(.op(OP_ADDI), .rd(2), .rs1(0), .imm(16)),
            asm_instr(.op(OP_SLL), .rd(6), .rs1(1), .rs2(2)),
            asm_instr(.op(OP_BEQ), .rs1(7), .rs2(6), .imm(8)),
            asm_instr(.op(OP_ADDI), .rd(3), .rs1(0), .imm(5)),
            EBREAK_WORD
        };
        run_directed("min_beq_bit16", prog);

        prog = '{
            asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(1)),
            asm_instr(.op(OP_ADDI), .rd(2), .rs1(0), .imm(8)),
            asm_instr(.op(OP_SLL), .rd(6), .rs1(1), .rs2(2)),
            asm_instr(.op(OP_BEQ), .rs1(7), .rs2(6), .imm(8)),
            asm_instr(.op(OP_ADDI), .rd(3), .rs1(0), .imm(5)),
            EBREAK_WORD
        };
        run_directed("min_beq_bit8", prog);

        prog = '{
            asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(1)),
            asm_instr(.op(OP_ADDI), .rd(2), .rs1(0), .imm(7)),
            asm_instr(.op(OP_SLL), .rd(6), .rs1(1), .rs2(2)),
            asm_instr(.op(OP_BEQ), .rs1(7), .rs2(6), .imm(8)),
            asm_instr(.op(OP_ADDI), .rd(3), .rs1(0), .imm(5)),
            EBREAK_WORD
        };
        run_directed("min_beq_bit7", prog);

        prog = '{
            asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(1)),
            asm_instr(.op(OP_ADDI), .rd(2), .rs1(0), .imm(4)),
            asm_instr(.op(OP_SLL), .rd(6), .rs1(1), .rs2(2)),
            asm_instr(.op(OP_BEQ), .rs1(7), .rs2(6), .imm(8)),
            asm_instr(.op(OP_ADDI), .rd(3), .rs1(0), .imm(5)),
            EBREAK_WORD
        };
        run_directed("min_beq_bit4", prog);

        prog = '{
            asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(1)),
            asm_instr(.op(OP_ADDI), .rd(2), .rs1(0), .imm(2)),
            asm_instr(.op(OP_SLL), .rd(6), .rs1(1), .rs2(2)),
            asm_instr(.op(OP_BEQ), .rs1(7), .rs2(6), .imm(8)),
            asm_instr(.op(OP_ADDI), .rd(3), .rs1(0), .imm(5)),
            EBREAK_WORD
        };
        run_directed("min_beq_bit2", prog);

        prog = '{
            asm_instr(.op(OP_ADDI), .rd(6), .rs1(0), .imm(256)),
            asm_instr(.op(OP_BEQ), .rs1(7), .rs2(6), .imm(8)),
            asm_instr(.op(OP_ADDI), .rd(3), .rs1(0), .imm(5)),
            EBREAK_WORD
        };
        run_directed("min_beq_imm256", prog);

        prog = '{
            asm_instr(.op(OP_ADDI), .rd(6), .rs1(0), .imm(257)),
            asm_instr(.op(OP_BEQ), .rs1(7), .rs2(6), .imm(8)),
            asm_instr(.op(OP_ADDI), .rd(3), .rs1(0), .imm(5)),
            EBREAK_WORD
        };
        run_directed("min_beq_imm257", prog);

        prog = '{
            asm_instr(.op(OP_ADDI), .rd(6), .rs1(0), .imm(255)),
            asm_instr(.op(OP_BEQ), .rs1(7), .rs2(6), .imm(8)),
            asm_instr(.op(OP_ADDI), .rd(3), .rs1(0), .imm(5)),
            EBREAK_WORD
        };
        run_directed("min_beq_imm255", prog);

        prog = '{
            asm_instr(.op(OP_LW), .rd(6), .rs1(0), .imm(504)),
            asm_instr(.op(OP_ADDI), .rd(9), .rs1(0), .imm(0)),
            asm_instr(.op(OP_BEQ), .rs1(7), .rs2(6), .imm(8)),
            asm_instr(.op(OP_ADDI), .rd(3), .rs1(0), .imm(5)),
            EBREAK_WORD
        };
        run_directed("min_lw_gap_beq", prog);

        prog = '{
            asm_instr(.op(OP_ADDI), .rd(6), .rs1(0), .imm(5)),
            asm_instr(.op(OP_LW), .rd(6), .rs1(0), .imm(504)),
            asm_instr(.op(OP_BEQ), .rs1(7), .rs2(6), .imm(8)),
            asm_instr(.op(OP_ADDI), .rd(3), .rs1(0), .imm(5)),
            EBREAK_WORD
        };
        run_directed("min_lwuse_stale_ne", prog);

        prog = '{
            asm_instr(.op(OP_ADDI), .rd(6), .rs1(0), .imm(5)),
            asm_instr(.op(OP_ADDI), .rd(7), .rs1(0), .imm(5)),
            asm_instr(.op(OP_LW), .rd(6), .rs1(0), .imm(504)),
            asm_instr(.op(OP_BEQ), .rs1(7), .rs2(6), .imm(8)),
            asm_instr(.op(OP_ADDI), .rd(3), .rs1(0), .imm(5)),
            EBREAK_WORD
        };
        run_directed("min_lwuse_stale_eq", prog);

        prog = '{
            asm_instr(.op(OP_ADDI), .rd(6), .rs1(0), .imm(5)),
            asm_instr(.op(OP_LW), .rd(6), .rs1(0), .imm(504)),
            asm_instr(.op(OP_ADD), .rd(4), .rs1(6), .rs2(0)),
            EBREAK_WORD
        };
        run_directed("min_lwuse_add", prog);

       

        // 1.3 x0_write_protection
        prog = '{
            asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(5)),
            asm_instr(.op(OP_ADDI), .rd(0), .rs1(0), .imm(99)),
            asm_instr(.op(OP_ADD),  .rd(0), .rs1(1), .rs2(1)),
            asm_instr(.op(OP_ADD),  .rd(2), .rs1(0), .rs2(0)),
            EBREAK_WORD
        };
        run_directed("x0_write_protection", prog);

        // 1.4 x0_source_reads_zero
        prog = '{
            asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(50)),
            asm_instr(.op(OP_SUB),  .rd(2), .rs1(1), .rs2(0)),
            asm_instr(.op(OP_SUB),  .rd(3), .rs1(0), .rs2(1)),
            EBREAK_WORD
        };
        run_directed("x0_source_reads_zero", prog);

        // 1.5 add_value_classes
        prog = '{
            asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(1)),
            asm_instr(.op(OP_ADDI), .rd(2), .rs1(0), .imm(31)),
            asm_instr(.op(OP_SLL),  .rd(3), .rs1(1), .rs2(2)),
            asm_instr(.op(OP_ADD),  .rd(4), .rs1(3), .rs2(3)),
            asm_instr(.op(OP_ADDI), .rd(5), .rs1(0), .imm(100)),
            asm_instr(.op(OP_ADDI), .rd(6), .rs1(0), .imm(-40)),
            asm_instr(.op(OP_ADD),  .rd(7), .rs1(5), .rs2(6)),
            EBREAK_WORD
        };
        run_directed("add_value_classes", prog);

        // 1.6 sub_value_classes
        prog = '{
            asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(5)),
            asm_instr(.op(OP_ADDI), .rd(2), .rs1(0), .imm(3)),
            asm_instr(.op(OP_SUB),  .rd(3), .rs1(1), .rs2(2)),
            asm_instr(.op(OP_SUB),  .rd(4), .rs1(2), .rs2(1)),
            asm_instr(.op(OP_SUB),  .rd(5), .rs1(1), .rs2(1)),
            EBREAK_WORD
        };
        run_directed("sub_value_classes", prog);

        // 1.7 sll_shift_amount_masking
        prog = '{
            asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(1)),
            asm_instr(.op(OP_ADDI), .rd(2), .rs1(0), .imm(0)),
            asm_instr(.op(OP_SLL),  .rd(3), .rs1(1), .rs2(2)),
            asm_instr(.op(OP_ADDI), .rd(4), .rs1(0), .imm(31)),
            asm_instr(.op(OP_SLL),  .rd(5), .rs1(1), .rs2(4)),
            asm_instr(.op(OP_ADDI), .rd(6), .rs1(0), .imm(32)),
            asm_instr(.op(OP_SLL),  .rd(7), .rs1(1), .rs2(6)),
            asm_instr(.op(OP_ADDI), .rd(8), .rs1(0), .imm(33)),
            asm_instr(.op(OP_SLL),  .rd(9), .rs1(1), .rs2(8)),
            EBREAK_WORD
        };
        run_directed("sll_shift_amount_masking", prog);

        // 1.8 srl_is_logical
        prog = '{
            asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(1)),
            asm_instr(.op(OP_ADDI), .rd(2), .rs1(0), .imm(31)),
            asm_instr(.op(OP_SLL),  .rd(3), .rs1(1), .rs2(2)),
            asm_instr(.op(OP_ADDI), .rd(4), .rs1(0), .imm(1)),
            asm_instr(.op(OP_SRL),  .rd(5), .rs1(3), .rs2(4)),
            asm_instr(.op(OP_SRL),  .rd(6), .rs1(3), .rs2(2)),
            EBREAK_WORD
        };
        run_directed("srl_is_logical", prog);

        // 1.9 shift_by_computed_amount
        prog = '{
            asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(10)),
            asm_instr(.op(OP_ADDI), .rd(2), .rs1(0), .imm(6)),
            asm_instr(.op(OP_SUB),  .rd(3), .rs1(1), .rs2(2)),
            asm_instr(.op(OP_ADDI), .rd(4), .rs1(0), .imm(3)),
            asm_instr(.op(OP_SLL),  .rd(5), .rs1(4), .rs2(3)),
            EBREAK_WORD
        };
        run_directed("shift_by_computed_amount", prog);

        // 1.10 sw_lw_roundtrip_distinct_words
        prog = '{
            asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(42)),
            asm_instr(.op(OP_SW),   .rs1(0), .rs2(1), .imm(4)),
            asm_instr(.op(OP_ADDI), .rd(2), .rs1(0), .imm(99)),
            asm_instr(.op(OP_SW),   .rs1(0), .rs2(2), .imm(8)),
            asm_instr(.op(OP_LW),   .rd(3), .rs1(0), .imm(8)),
            asm_instr(.op(OP_LW),   .rd(4), .rs1(0), .imm(4)),
            EBREAK_WORD
        };
        run_directed("sw_lw_roundtrip_distinct_words", prog);

        // 1.11 mem_negative_offset
        prog = '{
            asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(16)),
            asm_instr(.op(OP_ADDI), .rd(2), .rs1(0), .imm(77)),
            asm_instr(.op(OP_SW),   .rs1(1), .rs2(2), .imm(-8)),
            asm_instr(.op(OP_LW),   .rd(3), .rs1(1), .imm(-8)),
            asm_instr(.op(OP_LW),   .rd(4), .rs1(0), .imm(8)),
            EBREAK_WORD
        };
        run_directed("mem_negative_offset", prog);

        // 1.12 mem_byte_to_word_scaling (data memory holds random values after init_memories)
        prog = '{
            asm_instr(.op(OP_LW), .rd(1), .rs1(0), .imm(4)),
            asm_instr(.op(OP_LW), .rd(2), .rs1(0), .imm(8)),
            asm_instr(.op(OP_LW), .rd(3), .rs1(0), .imm(12)),
            EBREAK_WORD
        };
        run_directed("mem_byte_to_word_scaling", prog);

        // 1.14 sw_does_not_write_rd
        prog = '{
            asm_instr(.op(OP_ADDI), .rd(4), .rs1(0), .imm(123)),
            asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(55)),
            asm_instr(.op(OP_SW),   .rs1(0), .rs2(1), .imm(4)),
            EBREAK_WORD
        };
        run_directed("sw_does_not_write_rd", prog);

        // 1.15 lw_into_x0
        prog = '{
            asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(7)),
            asm_instr(.op(OP_SW),   .rs1(0), .rs2(1), .imm(4)),
            asm_instr(.op(OP_LW),   .rd(0), .rs1(0), .imm(4)),
            asm_instr(.op(OP_ADD),  .rd(2), .rs1(0), .rs2(0)),
            EBREAK_WORD
        };
        run_directed("lw_into_x0", prog);

        // 1.16 beq_taken_forward
        prog = '{
            asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(0)),
            asm_instr(.op(OP_BEQ),  .rs1(1), .rs2(0), .imm(8)),
            asm_instr(.op(OP_ADDI), .rd(2), .rs1(0), .imm(1)),
            asm_instr(.op(OP_ADDI), .rd(3), .rs1(0), .imm(2)),
            EBREAK_WORD
        };
        run_directed("beq_taken_forward", prog);

        // 1.17 beq_not_taken
        prog = '{
            asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(1)),
            asm_instr(.op(OP_BEQ),  .rs1(1), .rs2(0), .imm(8)),
            asm_instr(.op(OP_ADDI), .rd(2), .rs1(0), .imm(1)),
            asm_instr(.op(OP_ADDI), .rd(3), .rs1(0), .imm(2)),
            EBREAK_WORD
        };
        run_directed("beq_not_taken", prog);

        // 1.18 beq_backward_loop
        prog = '{
            asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(3)),
            asm_instr(.op(OP_ADDI), .rd(2), .rs1(0), .imm(0)),
            asm_instr(.op(OP_ADDI), .rd(2), .rs1(2), .imm(10)),
            asm_instr(.op(OP_ADDI), .rd(1), .rs1(1), .imm(-1)),
            asm_instr(.op(OP_BEQ),  .rs1(1), .rs2(0), .imm(8)),
            asm_instr(.op(OP_BEQ),  .rs1(0), .rs2(0), .imm(-12)),
            EBREAK_WORD
        };
        run_directed("beq_backward_loop", prog);

        // 1.19 beq_equal_nonzero
        prog = '{
            asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(5)),
            asm_instr(.op(OP_ADDI), .rd(2), .rs1(0), .imm(5)),
            asm_instr(.op(OP_BEQ),  .rs1(1), .rs2(2), .imm(8)),
            asm_instr(.op(OP_ADDI), .rd(3), .rs1(0), .imm(1)),
            asm_instr(.op(OP_ADDI), .rd(4), .rs1(0), .imm(2)),
            EBREAK_WORD
        };
        run_directed("beq_equal_nonzero", prog);

        // 1.21 no_execution_past_ebreak
        prog = '{
            asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(1)),
            EBREAK_WORD,
            asm_instr(.op(OP_ADDI), .rd(2), .rs1(0), .imm(99)),
            asm_instr(.op(OP_SW),   .rs1(0), .rs2(2), .imm(4)),
            EBREAK_WORD
        };
        run_directed("no_execution_past_ebreak", prog);

        // 1.22 unsupported_encoding_is_nop
        prog = '{
            asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(5)),
            asm_instr(.op(OP_NOP)),
            asm_instr(.op(OP_ADDI), .rd(2), .rs1(0), .imm(7)),
            EBREAK_WORD
        };
        run_directed("unsupported_encoding_is_nop", prog);

        // 1.26 store_then_load_same_word
        prog = '{
            asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(88)),
            asm_instr(.op(OP_SW),   .rs1(0), .rs2(1), .imm(4)),
            asm_instr(.op(OP_LW),   .rd(2), .rs1(0), .imm(4)),
            EBREAK_WORD
        };
           run_directed("store_then_load_same_word", prog);

        // 1.27 branch_on_just_written_reg
        prog = '{
            asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(5)),
            asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(0)),
            asm_instr(.op(OP_BEQ),  .rs1(1), .rs2(0), .imm(8)),
            asm_instr(.op(OP_ADDI), .rd(2), .rs1(0), .imm(1)),
            asm_instr(.op(OP_ADDI), .rd(3), .rs1(0), .imm(2)),
            EBREAK_WORD
        };
        run_directed("branch_on_just_written_reg", prog);


	    // 1.30 ext_mem_boundaries: first and last word of both SRAMs
        sb.set_test("ext_mem_boundaries");
        drv.xbar_write(32'h0000_0000, 32'h1111_0000);
        drv.xbar_write(32'h0000_0FFC, 32'h2222_0FFC);
        drv.xbar_write(32'h0000_1000, 32'h3333_1000);
        drv.xbar_write(32'h0000_1FFC, 32'h4444_1FFC);
        drv.xbar_read(32'h0000_0000);
        drv.xbar_read(32'h0000_0FFC);
        drv.xbar_read(32'h0000_1000);
        drv.xbar_read(32'h0000_1FFC);

        // 1.29 external_halt_loop: a halt request stops a CPU that never halts on its own
        sb.set_test("external_halt_loop");
        prog = '{
            asm_instr(.op(OP_BEQ), .rs1(0), .rs2(0), .imm(0)),
            EBREAK_WORD
        };
        drv.reset_task();
        seqr.load_program(prog);
        seqr.wait_for_empty();
        repeat (2) @(cpu_if.cb);
        drv.start_cpu();
        repeat (10) @(cpu_if.cb);
        if (cpu_if.cb.cpu_active !== 1'b1) assertion_fail("external_halt_loop: CPU was not running before the halt request");
        drv.halt_cpu_now();
        if (cpu_if.cb.cpu_active !== 1'b0) assertion_fail("external_halt_loop: cpu_active still high after the halt request");

        // 1.28 reset_while_active: reset in the middle of a program clears the registers
        sb.set_test("reset_while_active");
        prog = '{
            asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(5)),
            asm_instr(.op(OP_BEQ), .rs1(0), .rs2(0), .imm(0)),
            EBREAK_WORD
        };
        drv.reset_task();
        seqr.load_program(prog);
        seqr.wait_for_empty();
        repeat (2) @(cpu_if.cb);
        drv.start_cpu();
        repeat (15) @(cpu_if.cb);
        if (cpu_if.cb.cpu_active !== 1'b1) assertion_fail("reset_while_active: CPU was not running before reset");
        drv.reset_task();
        if (cpu_if.cb.cpu_active !== 1'b0) assertion_fail("reset_while_active: cpu_active still high after reset");
        readback(2, REG_COUNT);

        
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
    logic rst_prev = 1'b0;
    always @(posedge cpu_if.clk) rst_prev <= cpu_if.reset;


   // 3.2: NO_MEM_ACCESS_WHEN_IDLE - The CPU does not drive a data-SRAM access while cpu_active is low
   NO_MEM_ACCESS_WHEN_IDLE:
     assert property (@(posedge cpu_if.clk) disable iff (rst)
         (!cpu_if.cpu_active && !cpu_if.r_en && !cpu_if.w_en) |-> (!cpu_if.dsram_en))
     else assertion_fail("CPU drove a data-SRAM access while not active");

   // 3.3: RESET_QUIESCES_CONTROL - After reset has been held two cycles, the CPU is inactive and not halted
   RESET_QUIESCES_CONTROL:
     assert property (@(posedge cpu_if.clk)
         (cpu_if.reset && rst_prev) |-> (!cpu_if.cpu_active && !cpu_if.cpu_halted))
     else assertion_fail("Control signals not idle while reset was asserted");
    
    // 3.1: HALT_RELEASES_CPU - An external halt request returns memory ownership to the external port within two cycles
   HALT_RELEASES_CPU:
     assert property (@(posedge cpu_if.clk) disable iff (rst)
         (cpu_if.halt_cpu && cpu_if.cpu_active) |-> ##[1:2] !cpu_if.cpu_active)
     else assertion_fail("cpu_active stayed high after an external halt request");


    // Example assertion
    // It checks one interface rule and sends failures through the testbench counter
    NO_SIMULTANEOUS_READ_WRITE:
        assert property (@(posedge clk) disable iff (rst)
            !(cpu_if.w_en && cpu_if.r_en))
        else assertion_fail("w_en_i and r_en_i were asserted together");

endmodule: cpu_tb_top
