/*
 * Checks monitor transactions against independent predictions of what the DUT
 * should do, with the help of a golden model (ref_model). It keeps its own
 * memory and register values to check against the actual DUT.
 */
class cpu_sb #(int DataSize=32, int AddrSize=14);

    mailbox #(cpu_xbar_item #(DataSize, AddrSize)) sb_box;

    cpu_ref_model ref_model;

    // DUT state as tracked by the scoreboard
    logic [31:0] expected_imem [ISRAM_WORDS];
    logic [31:0] expected_dmem [DSRAM_WORDS];
    logic [31:0] expected_regs [REG_COUNT];
    ref_store_t  expected_stores [$];

    // Test and comparison states
    string test_name;          // Name shown with a scoreboard failure
    bit program_running;       // A CPU program has an active reference prediction
    bit log_transactions;      // Optional external-write logging switch

    // Register reads are checked only after the CPU finishes normally
    bit checking_regs;            // Compare register reads only after a clean halt
    int checks;                   // Number of completed comparisons
    int errors;                   // Number of scoreboard mismatches
    int observed_stores;          // CPU stores seen in the current program

    // Constructor
        function new(mailbox #(cpu_xbar_item #(DataSize, AddrSize)) sb_box);
        this.sb_box = sb_box;
        this.ref_model = new();
        this.test_name = "startup";
        this.program_running = 1'b0;
        this.log_transactions = 1'b1;
        this.checking_regs = 1'b1;
        this.checks = 0;
        this.errors = 0;
        foreach (expected_imem[i]) begin
            expected_imem[i] = EBREAK_WORD;
        end
        foreach (expected_dmem[i]) begin
            expected_dmem[i] = '0;
        end
        foreach (expected_regs[i]) begin
            expected_regs[i] = '0;
        end
    endfunction: new

    function void set_test(input string name);
        this.test_name = name;
    endfunction: set_test

    // Record every mismatch during bug hunt, while retaining fail-fast behavior
    // for normal member regressions.
    function void fail(input string message);
        errors++;
        $error($stime, " SB: [%s] %s\n", test_name, message);
        if (!$test$plusargs("NO_STOP_ON_ERROR"))
            $finish;
    endfunction: fail

    // Check monitor transactions against predictions
    task run();
        cpu_xbar_item #(DataSize, AddrSize) trans;

        forever begin
            sb_box.get(trans);

            case (trans.kind)

                // Reset clears CPU state but does not erase the memories
                DUT_RESET: begin
                    foreach (expected_regs[i]) begin
                        expected_regs[i] = '0;
                    end
                    expected_stores.delete();
                    program_running = 1'b0;
                end

                // Track writes made through the DUT's external memory port
                XBAR_WRITE: begin
                    case (trans.get_window())
                        WIN_ISRAM: begin
                            expected_imem[trans.word_index()] = trans.data;
                            if (log_transactions) begin
                                $display($stime, " SB: External write imem[0x%03x] <- 0x%08x\n",
                                         trans.word_index(), trans.data);
                            end
                        end
                        WIN_DSRAM: begin
                            expected_dmem[trans.word_index()] = trans.data;
                            if (log_transactions) begin
                                $display($stime, " SB: External write dmem[0x%03x] <- 0x%08x\n",
                                         trans.word_index(), trans.data);
                            end
                        end
                        WIN_REG: begin
                            fail($sformatf(
                                "external write to the register file window at 0x%04x - that window is read only",
                                trans.addr));
                        end
                    endcase
                end

                // Compare external read data with the scoreboard's expected memory
                XBAR_READ: begin
                    logic [31:0] expected;
                    string what;

                    case (trans.get_window())
                        WIN_ISRAM: begin
                            expected = expected_imem[trans.word_index()];
                            what     = $sformatf("imem[0x%03x]", trans.word_index());
                        end
                        WIN_DSRAM: begin
                            expected = expected_dmem[trans.word_index()];
                            what     = $sformatf("dmem[0x%03x]", trans.word_index());
                        end
                        WIN_REG: begin
                            expected = expected_regs[trans.addr[6:2]];
                            what     = $sformatf("register x%0d", trans.addr[6:2]);
                        end
                        default: begin
                            expected = 'x;
                            what     = $sformatf("unmapped address 0x%04x", trans.addr);
                        end
                    endcase

                    if ((trans.get_window() == WIN_REG) && !checking_regs) begin
                        $display($stime, " SB: External read %s returned 0x%08x (not checked)\n",
                                 what, trans.data);
                    end else begin
                        checks++;
                        if (trans.data === expected) begin
                            $display($stime,
                                     " SB: External read %s, Expected 0x%08x, Matches Actual 0x%08x\n",
                                     what, expected, trans.data);
                        end else begin
                            fail($sformatf("read of %s returned 0x%08x, expected 0x%08x",
                                           what, trans.data, expected));
                        end
                    end
                end

                // Run the reference model when CPU execution begins
                CPU_START: begin
			ref_model.load_imem(expected_imem);
			ref_model.load_dmem(expected_dmem);

			ref_model.clear_state();
			ref_model.run(MAX_REF_INSTR);

			expected_regs = ref_model.regs;
			expected_stores = ref_model.store_queue;

			observed_stores = 0;
			program_running = 1'b1;

                end

                // Each CPU store must match the next expected store
                CPU_STORE: begin
                    ref_store_t exp_store;
	            if (expected_stores.size() == 0) begin
			fail($sformatf("Unexpected CPU store to addr 0x%0x with data 0x%0x", trans.addr, trans.data));
		    end else begin
			exp_store = expected_stores.pop_front();
			if(trans.addr != exp_store.addr || trans.data != exp_store.data) begin
				fail($sformatf("Store mismatch: expected [0x%0x] <- 0x%0x, got [0x%0x] <- 0x%0x", 
                                           exp_store.addr, exp_store.data, trans.addr, trans.data));	
			end
			observed_stores++;
		    end
                end

                // Each CPU load must return the current expected memory value
                CPU_LOAD: begin
                    logic [31:0] expected;
		    if(trans.data != expected_dmem[trans.addr]) begin
			fail($sformatf("Load mismatch at addr 0x%0x: expected 0x%0x, got 0x%0x", 
                                       trans.addr, expected_dmem[trans.addr], trans.data));
		    end

                end

                // A normal halt must finish all expected CPU activity
                CPU_HALT: begin
			program_running = 1'b0;
			if (expected_stores.size() > 0) begin
				fail($sformatf("CPU halted before completing %0d expected stores", expected_stores.size()));
			end
                end

                default: ;
            endcase
        end
    endtask: run

endclass: cpu_sb
