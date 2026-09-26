module alu ( 
    input logic [31:0] operand_a_i,
    input logic [31:0] operand_b_i,
    input logic [3:0] alu_op_i,
    output logic [31:0] result_o

);

always_comb begin
    result_o = '0;
    case (alu_op_i)
        4'd0: result_o = operand_a_i + operand_b_i;
        4'd1: result_o = operand_a_i - operand_b_i;
        4'd2: result_o = operand_a_i << operand_b_i[4:0];
        4'd3: result_o = operand_a_i >> operand_b_i[4:0];
        default: result_o = '0;
    endcase
end

endmodule