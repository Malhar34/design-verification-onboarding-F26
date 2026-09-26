//helpful enum for instruction types (you can use names instead of numbers)
`define functional
package cpu_pkg;

	typedef enum logic [4:0] {
		NOP,
		ADD,
		ADDI,
		SUB,
		SLL,
		SRL,
		LOAD,
		STORE,
		BEQ,
		EBREAK
	} instr_type_e;

endpackage
