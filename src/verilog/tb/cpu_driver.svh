/*
 * Converts sequences from the sequencer into signals that drive the external
 * port of the DUT. This is the only class that drives the DUT. It uses the
 * clocking block to avoid races with the monitor.
 *
 * Check memory_controller to see how it arbitrates memory ownership between
 * the CPU and the external port, and acts as a crossbar (xbar) to route external
 * access to ISRAM, DSRAM, and registers.
 */
class cpu_driver #(int DataSize=32, int AddrSize=14);

    virtual interface cpu_if #(.DataSize(DataSize), .AddrSize(AddrSize)) cpuVif;

    mailbox #(cpu_xbar_item #(DataSize, AddrSize)) xbar_box;

    // Maximum cycles to wait for an external read to finish
    int xbar_timeout = 32;

    // Maximum cycles to wait for the CPU to halt
    int run_timeout = 20000;

    int timeouts;                // Counts timeout failures
    bit last_run_completed;      // High when the CPU reports a clean halt

    // Constructor
    function new(virtual interface cpu_if #(DataSize, AddrSize) cpuVif,
                 mailbox #(cpu_xbar_item #(DataSize, AddrSize)) xbar_box);
      this.cpuVif   = cpuVif;
      this.xbar_box = xbar_box;
      this.timeouts = 0;
      this.last_run_completed = 1'b0;
    endfunction: new

    // Put the DUT into a known reset state
    task reset_task();
	cpuVif.cb.reset <= 1'b1;
	cpuVif.cb.en_cpu <= 1'b0;
	cpuVif.cb.halt_cpu <= 1'b0;
	cpuVif.cb.addr <= '0;
	cpuVif.cb.wdata <= '0;
	cpuVif.cb.w_en <= 1'b0;
	cpuVif.cb.r_en <= 1'b0;
	
	repeat (5) @(cpuVif.cb);
	cpuVif.cb.reset <= 1'b0;
	repeat (2) @(cpuVif.cb);


    endtask: reset_task

    // Send one write through the DUT's external memory port
    task xbar_write(input logic [AddrSize-1:0] addr, input logic [DataSize-1:0] data);
        if (addr[1:0] != 2'b00) begin
            $error($stime, " Drv: external write address 0x%0x is not word aligned\n", addr);
        end

	cpuVif.cb.addr <= addr;
	cpuVif.cb.wdata	<= data;
	cpuVif.cb.w_en <= 1'b1;


	@(cpuVif.cb);

	cpuVif.cb.w_en <= 1'b0;

	@(cpuVif.cb);

    endtask: xbar_write

    // Send one read through the external memory port and wait for its data
    task xbar_read(input logic [AddrSize-1:0] addr);
        bit timed_out;
        int count;

        if (addr[1:0] != 2'b00) begin
            $error($stime, " Drv: external read address 0x%0x is not word aligned\n", addr);
        end

	    cpuVif.cb.addr <= addr;
	    cpuVif.cb.r_en <= 1'b1;
	    cpuVif.cb.w_en <= 1'b0;

        timed_out = 1'b0;
        count     = 0;
    
        if (window_of(addr) != WIN_REG) begin
            @(cpuVif.cb); // SRAm answers on the following cycle so I can ignore any rready left over from the last read
        end
        
	    forever begin
		    @(cpuVif.cb);
		    count++;
		
		    if (cpuVif.cb.rready === 1'b1) begin
			    break;
		    end

		    if (count > 100) begin
			    timed_out = 1'b1;
			    $error($stime, " Drv: external read timeout at 0x%0x\n", addr);
			    break;
		    end
	    end
	
	    cpuVif.cb.r_en <= 1'b0;	

    endtask: xbar_read

    // Drive a start request for one CPU run
    task start_cpu();
	    cpuVif.cb.en_cpu <= 1'b1;
	    @(cpuVif.cb);
	    cpuVif.cb.en_cpu <= 1'b0;

    endtask: start_cpu

    // Wait for the CPU to halt, or fail after the allowed number of cycles
    task wait_for_halt(output int cycles, input int max_cycles=0);
        int limit;
	    bit halted;

        limit  = (max_cycles == 0) ? run_timeout : max_cycles;
        cycles = 0;
	    halted = 1'b0;
	    last_run_completed = 1'b0;

	    while (!halted && cycles < limit) begin
		    @(cpuVif.cb);
		    cycles++;
		    if (cpuVif.cb.cpu_halted) begin
			    halted = 1'b1;
		    end
	    end

	    if (halted) begin
		    last_run_completed = 1'b1;
	    end else begin
		    timeouts++;
		    $error($stime, " Drv: CPU did not halt within %0d cycles\n", limit);
	    end

    endtask: wait_for_halt

    // Start CPU and wait for it to halt
    task run_program(input int max_cycles=0);
        int cycles;

        last_run_completed = 1'b0;
        start_cpu();
        wait_for_halt(cycles, max_cycles);
    endtask: run_program

    // Stop a program through an external halt and wait for memory ownership
    // to return to the external port
    task halt_cpu_now();
	    int count = 0;

	    // Pulse the halt signal for one cycle
	    cpuVif.cb.halt_cpu <= 1'b1;
	    @(cpuVif.cb);
	    cpuVif.cb.halt_cpu <= 1'b0;

	    forever begin
		    if (cpuVif.cb.cpu_active === 1'b0) begin
			    break;
		    end

		    if (count > 100) begin
			    $error($stime, " Drv: timeout waiting for CPU to halt\n");
			    break;
		    end

		    @(cpuVif.cb);
		    count++;
	    end

    endtask: halt_cpu_now

    // Main driver loop. Keeps taking transactions from the mailbox and
    // driving them through the DUT
    task run();
        cpu_xbar_item #(DataSize, AddrSize) trans;

        forever begin
            xbar_box.get(trans);
            if (trans.is_write) begin
                xbar_write(trans.addr, trans.data);
            end else begin
                xbar_read(trans.addr);
            end
        end
    endtask: run

endclass: cpu_driver
