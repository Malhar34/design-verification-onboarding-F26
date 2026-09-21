/*
 * Builds programs and external-port transactions, then sends them to the
 * driver through xbar_box. The sequencer describes intent but never drives or
 * observes the DUT directly.
 */
class cpu_sequencer #(int DataSize=32, int AddrSize=14);

    mailbox #(cpu_xbar_item #(DataSize, AddrSize)) xbar_box;

    // Constructor
    function new();
        xbar_box = new();
    endfunction: new

    // Build a random program and enqueue frontdoor instruction writes.
    // idx and prog_len are assigned before randomization because branch
    // constraints depend on the instruction's position.
    task gen_program(input int num, input bit verbose=1'b1);
        cpu_seq_item #(DataSize, AddrSize) instr;
        int prog_len;

        prog_len = num + 1; // +1 for the ebreak

        for (int i = 0; i < num; i++) begin
            instr = new();
            instr.idx = i;
            instr.prog_len = prog_len;
            if (!instr.randomize()) begin
                $error($stime, " Seq: randomization failed for instruction %0d\n", i);
            end
            if (verbose) begin
                instr.display();
            end
            send_write_trans(word_addr(ISRAM_BASE, i), instr.encode());
        end

        // Append ebreak explicitly so a random program cannot halt early
        instr = new();
        instr.idx = num;
        instr.prog_len = prog_len;
        instr.op = OP_EBREAK;
        instr.rs1 = '0;
        instr.rs2 = '0;
        instr.rd = '0;
        instr.imm = 0;
        if (verbose) begin
            instr.display();
        end
        send_write_trans(word_addr(ISRAM_BASE, num), instr.encode());
    endtask: gen_program

    // Stage one external write transaction
    task send_write_trans(input logic [AddrSize-1:0] addr, input logic [DataSize-1:0] data);
        cpu_xbar_item #(DataSize, AddrSize) trans;

        trans = new();
        trans.kind = XBAR_WRITE;
        trans.addr = addr;
        trans.data = data;
        trans.is_write = 1'b1;
        xbar_box.put(trans);
    endtask: send_write_trans

    // Stage one external read transaction
    task send_read_trans(input logic [AddrSize-1:0] addr);
        cpu_xbar_item #(DataSize, AddrSize) trans;

        trans = new();
        trans.kind = XBAR_READ;
        trans.addr = addr;
        trans.is_write = 1'b0;
        xbar_box.put(trans);
    endtask: send_read_trans

    // Stage a program as instruction-memory writes starting at word zero
    task load_program(const ref logic [31:0] prog [$]);
        foreach (prog[i]) begin
            send_write_trans(word_addr(ISRAM_BASE, i), prog[i]);
        end
    endtask: load_program

    // Generate external-port traffic. cpu_xbar_item constraints define the
    // useful behavior; the mailbox mechanics are supplied.
    task gen_xbar(input int num, input bit verbose=1'b0);
        cpu_xbar_item #(DataSize, AddrSize) trans;

        for (int i = 0; i < num; i++) begin
            trans = new();
            if (!trans.randomize()) begin
                $error($stime, " Seq: randomization failed for xbar item %0d\n", i);
            end
            if (verbose) begin
                trans.display();
            end
            xbar_box.put(trans);
        end
    endtask: gen_xbar

    // Wait until the driver has pulled every staged mailbox transaction
    task wait_for_empty();
        while (xbar_box.num() != 0) begin
            #10;
        end
    endtask: wait_for_empty

endclass: cpu_sequencer