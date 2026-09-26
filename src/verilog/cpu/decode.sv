module decode (
    input logic [31:0] instr_i,

    output logic [4:0] rs1_addr_o,
    output logic [4:0] rs2_addr_o,
    output logic [4:0] rd_addr_o,

    output logic [31:0] imm_o,
    output logic [3:0] alu_op_o,

    output logic use_imm_o,
    output logic reg_write_o,
    output logic is_ebreak_o,
    output logic is_load_o,
    output logic is_store_o,
    output logic is_branch_o
);

    assign rs1_addr_o = instr_i[19:15];
    assign rs2_addr_o = instr_i[24:20];
    assign rd_addr_o = instr_i[11:7];
    
     // I am taking the 12-bit immediate and putting 20 copies of instr_i[31] on top of it which perserves the value's sign for addi -2048
    logic [31:0] imm_i_type;
    logic [31:0] imm_s_type;
    logic [31:0] imm_b_type;
    assign imm_i_type = {{20{instr_i[31]}}, instr_i[31:20]};
    assign imm_s_type = {{20{instr_i[31]}}, instr_i[31:25], instr_i[11:7]};
    assign imm_b_type = {{19{instr_i[31]}}, instr_i[31], instr_i[7], instr_i[30:25], instr_i[11:8], 1'b0};

    logic [6:0] opcode;
    assign opcode = instr_i[6:0];
    logic [2:0] funct3;
    logic [6:0] funct7;
    assign funct3 = instr_i[14:12];
    assign funct7 = instr_i[31:25];

    always_comb begin
        // always have defauls
        alu_op_o = 4'd0;
        use_imm_o = 1'b0;
        reg_write_o = 1'b0;
        is_ebreak_o = 1'b0;
        is_load_o = 1'b0;
        imm_o = imm_i_type;
        is_store_o = 1'b0;
        is_branch_o = 1'b0;

        if (opcode == 7'b0010011) begin
            //addi
            alu_op_o = 4'd0;
            use_imm_o = 1'b1; // should the alu's second operand be the immediate instead of rs2. For addi, the B operant is the immediate. So its 1'b1 since there is an immediate in addi
            reg_write_o = 1'b1; // same reason as above this is 1 since addi writes into a register
        end else if (opcode == 7'b1110011 && instr_i[31:20] == 12'd1) begin // ebreak is 12'd1 and ecall is 12'd0 so we need the extra check to differentiate the two
            //ebreak
            is_ebreak_o = 1'b1;
            reg_write_o = 1'b0; // doesnt write into a register just halts
        end else if (opcode == 7'b0110011) begin
            // R-type
            use_imm_o = 1'b0; // no immediate
            reg_write_o = 1'b1; // THey do write to a register

            case (funct3)
                3'b000: alu_op_o = (funct7 == 7'b0100000) ? 4'd1 : 4'd0; // if its true then you sub, if its false then you add
                3'b001: alu_op_o = 4'd2;
                3'b101: alu_op_o = 4'd3;
                default: alu_op_o = 4'd0;
            endcase
        end else if (opcode == 7'b0000011) begin
            //loadWord
            alu_op_o = 4'd0; // doing an register arithmetic with 4 bit value 
            use_imm_o = 1'b1; // the offset is an immediate
            reg_write_o = 1'b1;
            is_load_o = 1'b1;
        end else if (opcode == 7'b0100011) begin
            // sw
            alu_op_o = 4'd0;
            use_imm_o = 1'b1;
            reg_write_o = 1'b0;
            is_store_o = 1'b1;
            imm_o = imm_s_type;
        end else if (opcode == 7'b1100011 && funct3 == 3'b000) begin
            // BEQ
            alu_op_o = 4'd1; // sutract, so I test for zero
            use_imm_o = 1'b0; // operands are register 1 and 2 not immediates
            reg_write_o = 1'b0;
            is_branch_o = 1'b1;
            imm_o = imm_b_type;
        end
    end
endmodule