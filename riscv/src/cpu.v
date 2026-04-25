

// Simple RISCV32I CPU - Basic implementation for testing
// Supports basic RV32I instruction set

module cpu(
  input  wire                 clk_in,			// system clock signal
  input  wire                 rst_in,			// reset signal
	input  wire					        rdy_in,			// ready signal, pause cpu when low

  input  wire [ 7:0]          mem_din,		// data input bus
  output wire [ 7:0]          mem_dout,		// data output bus
  output wire [31:0]          mem_a,			// address bus (only 17:0 is used)
  output wire                 mem_wr,			// write/read signal (1 for write)
		
	input  wire                 io_buffer_full, // 1 if uart buffer is full
		
	output wire [31:0]			dbgreg_dout		// cpu register output (debugging demo)
);

// Internal state registers
reg [31:0] pc;                // Program counter
reg [31:0] reg_file [0:31];   // Register file (32 registers)
reg [31:0] clock_counter;     // Clock counter for 0x30004 reads
reg program_finished;         // Program termination flag

// Memory interface signals
reg [31:0] mem_addr_reg;
reg [7:0]  mem_data_out_reg;
reg mem_write_reg;
reg mem_access_pending;

// Pipeline registers
reg [31:0] if_id_instr;
reg [31:0] if_id_pc;
reg if_id_valid;

reg [31:0] id_ex_instr;
reg [31:0] id_ex_pc;
reg [6:0]  id_ex_opcode;
reg [4:0]  id_ex_rd;
reg [4:0]  id_ex_rs1;
reg [4:0]  id_ex_rs2;
reg [31:0] id_ex_imm;
reg id_ex_valid;

reg [31:0] ex_alu_result;
reg [31:0] ex_mem_addr;
reg [31:0] ex_mem_data;
reg ex_mem_write;
reg ex_valid;

reg [31:0] mem_wb_result;
reg [4:0]  mem_wb_rd;
reg mem_wb_write;
reg mem_wb_valid;

// Control signals
reg stall;
reg flush;

// Instruction fetch state
reg [31:0] instr_fetch_addr;
reg [15:0] instr_halfword;
reg instr_fetch_pending;

// Execute stage temporary variables
reg [31:0] rs1_data;
reg [31:0] rs2_data;
reg [3:0] alu_op_code;

// Helper function declarations
function [6:0] get_opcode;
  input [31:0] instr;
  begin
    get_opcode = instr[6:0];
  end
endfunction

function [4:0] get_rd;
  input [31:0] instr;
  begin
    get_rd = instr[11:7];
  end
endfunction

function [4:0] get_rs1;
  input [31:0] instr;
  begin
    get_rs1 = instr[19:15];
  end
endfunction

function [4:0] get_rs2;
  input [31:0] instr;
  begin
    get_rs2 = instr[24:20];
  end
endfunction

function [2:0] get_funct3;
  input [31:0] instr;
  begin
    get_funct3 = instr[14:12];
  end
endfunction

function [6:0] get_funct7;
  input [31:0] instr;
  begin
    get_funct7 = instr[31:25];
  end
endfunction

function [31:0] get_imm_i;
  input [31:0] instr;
  begin
    get_imm_i = {{21{instr[31]}}, instr[30:20]};
  end
endfunction

function [31:0] get_imm_s;
  input [31:0] instr;
  begin
    get_imm_s = {{21{instr[31]}}, instr[30:25], instr[11:7]};
  end
endfunction

function [31:0] get_imm_b;
  input [31:0] instr;
  begin
    get_imm_b = {{20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0};
  end
endfunction

function [31:0] get_imm_u;
  input [31:0] instr;
  begin
    get_imm_u = {instr[31:12], 12'b0};
  end
endfunction

function [31:0] get_imm_j;
  input [31:0] instr;
  begin
    get_imm_j = {{12{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0};
  end
endfunction

// Main CPU state machine
always @(posedge clk_in)
  begin
    if (rst_in)
      begin
        pc <= 32'h0;
        clock_counter <= 32'h0;
        program_finished <= 1'b0;
        mem_access_pending <= 1'b0;
        instr_fetch_pending <= 1'b0;
        if_id_valid <= 1'b0;
        id_ex_valid <= 1'b0;
        ex_valid <= 1'b0;
        mem_wb_valid <= 1'b0;
        stall <= 1'b0;
        flush <= 1'b0;
        reg_file[0] <= 32'h0;
      end
    else if (!rdy_in)
      begin
        // Pause CPU when rdy_in is low
      end
    else if (!program_finished)
      begin
        clock_counter <= clock_counter + 1;
        
        // Memory access handling
        if (mem_access_pending)
          begin
            mem_access_pending <= 1'b0;
          end
        
        // Instruction fetch
        if (!instr_fetch_pending && !stall)
          begin
            instr_fetch_addr <= pc;
            instr_fetch_pending <= 1'b1;
          end
        else if (instr_fetch_pending)
          begin
            // Simple 32-bit instruction fetch
            if_id_instr <= {mem_din, instr_halfword};
            if_id_pc <= pc;
            if_id_valid <= 1'b1;
            pc <= pc + 4;
            instr_fetch_pending <= 1'b0;
          end
        
        // Instruction decode
        if (if_id_valid && !id_ex_valid)
          begin
            id_ex_instr <= if_id_instr;
            id_ex_pc <= if_id_pc;
            id_ex_opcode <= get_opcode(if_id_instr);
            id_ex_rd <= get_rd(if_id_instr);
            id_ex_rs1 <= get_rs1(if_id_instr);
            id_ex_rs2 <= get_rs2(if_id_instr);
            
            case (get_opcode(if_id_instr))
              7'b0010011: id_ex_imm <= get_imm_i(if_id_instr);
              7'b0100011: id_ex_imm <= get_imm_s(if_id_instr);
              7'b1100011: id_ex_imm <= get_imm_b(if_id_instr);
              7'b0110111: id_ex_imm <= get_imm_u(if_id_instr);
              7'b0010111: id_ex_imm <= get_imm_u(if_id_instr);
              7'b1101111: id_ex_imm <= get_imm_j(if_id_instr);
              default:    id_ex_imm <= 32'b0;
            endcase
            
            id_ex_valid <= 1'b1;
            if_id_valid <= 1'b0;
          end
        
        // Execute stage
        if (id_ex_valid && !ex_valid)
          begin
            rs1_data = (id_ex_rs1 != 0) ? reg_file[id_ex_rs1] : 32'b0;
            rs2_data = (id_ex_rs2 != 0) ? reg_file[id_ex_rs2] : 32'b0;
            
            case (id_ex_opcode)
              7'b0110011: begin
                case (get_funct3(id_ex_instr))
                  3'b000: alu_op_code = (get_funct7(id_ex_instr) == 7'b0000000) ? 4'b0000 : 4'b0001;
                  3'b001: alu_op_code = 4'b0010;
                  3'b010: alu_op_code = 4'b0011;
                  3'b011: alu_op_code = 4'b0100;
                  3'b100: alu_op_code = 4'b0101;
                  3'b101: alu_op_code = (get_funct7(id_ex_instr) == 7'b0000000) ? 4'b0110 : 4'b0111;
                  3'b110: alu_op_code = 4'b1000;
                  3'b111: alu_op_code = 4'b1001;
                endcase
                ex_alu_result <= alu_operation(rs1_data, rs2_data, alu_op_code);
              end
              7'b0010011: begin
                case (get_funct3(id_ex_instr))
                  3'b000: ex_alu_result <= rs1_data + id_ex_imm;
                  3'b001: ex_alu_result <= rs1_data << id_ex_imm[4:0];
                  3'b010: ex_alu_result <= ($signed(rs1_data) < $signed(id_ex_imm)) ? 32'b1 : 32'b0;
                  3'b011: ex_alu_result <= (rs1_data < id_ex_imm) ? 32'b1 : 32'b0;
                  3'b100: ex_alu_result <= rs1_data ^ id_ex_imm;
                  3'b101: ex_alu_result <= (get_funct7(id_ex_instr) == 7'b0000000) ? 
                                   rs1_data >> id_ex_imm[4:0] : $signed(rs1_data) >>> id_ex_imm[4:0];
                  3'b110: ex_alu_result <= rs1_data | id_ex_imm;
                  3'b111: ex_alu_result <= rs1_data & id_ex_imm;
                endcase
              end
              7'b0110111: ex_alu_result <= id_ex_imm;
              7'b0010111: ex_alu_result <= id_ex_pc + id_ex_imm;
              default: ex_alu_result <= 32'b0;
            endcase
            
            if (id_ex_opcode == 7'b0100011)
              begin
                ex_mem_addr <= rs1_data + id_ex_imm;
                ex_mem_data <= rs2_data;
                ex_mem_write <= 1'b1;
              end
            else if (id_ex_opcode == 7'b0000011)
              begin
                ex_mem_addr <= rs1_data + id_ex_imm;
                ex_mem_write <= 1'b0;
              end
            else
              begin
                ex_mem_write <= 1'b0;
              end
            
            ex_valid <= 1'b1;
            id_ex_valid <= 1'b0;
          end
        
        // Memory stage
        if (ex_valid && !mem_wb_valid)
          begin
            if (ex_mem_write)
              begin
                mem_addr_reg <= ex_mem_addr;
                mem_data_out_reg <= ex_mem_data[7:0];
                mem_write_reg <= 1'b1;
                mem_access_pending <= 1'b1;
              end
            else if (id_ex_opcode == 7'b0000011)
              begin
                mem_addr_reg <= ex_mem_addr;
                mem_write_reg <= 1'b0;
                mem_access_pending <= 1'b1;
              end
            else
              begin
                mem_wb_result <= ex_alu_result;
                mem_wb_rd <= id_ex_rd;
                mem_wb_write <= (id_ex_rd != 0);
                mem_wb_valid <= 1'b1;
              end
            
            ex_valid <= 1'b0;
          end
        
        // Writeback stage
        if (mem_wb_valid)
          begin
            if (mem_wb_write)
              begin
                reg_file[mem_wb_rd] <= mem_wb_result;
              end
            mem_wb_valid <= 1'b0;
          end
        
        // Handle I/O operations
        if (mem_access_pending && !mem_write_reg)
          begin
            if (mem_addr_reg == 32'h30000)
              begin
                mem_wb_result <= {24'b0, mem_din};
                mem_wb_rd <= id_ex_rd;
                mem_wb_write <= (id_ex_rd != 0);
                mem_wb_valid <= 1'b1;
              end
            else if (mem_addr_reg == 32'h30004)
              begin
                mem_wb_result <= clock_counter;
                mem_wb_rd <= id_ex_rd;
                mem_wb_write <= (id_ex_rd != 0);
                mem_wb_valid <= 1'b1;
              end
            else
              begin
                mem_wb_result <= {24'b0, mem_din};
                mem_wb_rd <= id_ex_rd;
                mem_wb_write <= (id_ex_rd != 0);
                mem_wb_valid <= 1'b1;
              end
          end
        
        // Handle program termination
        if (mem_access_pending && mem_write_reg && mem_addr_reg == 32'h30004)
          begin
            program_finished <= 1'b1;
          end
      end
  end

// ALU operation function
function [31:0] alu_operation;
  input [31:0] a, b;
  input [3:0] op;
  begin
    case (op)
      4'b0000: alu_operation = a + b;
      4'b0001: alu_operation = a - b;
      4'b0010: alu_operation = a << b[4:0];
      4'b0011: alu_operation = $signed(a) < $signed(b) ? 32'b1 : 32'b0;
      4'b0100: alu_operation = a < b ? 32'b1 : 32'b0;
      4'b0101: alu_operation = a ^ b;
      4'b0110: alu_operation = a >> b[4:0];
      4'b0111: alu_operation = $signed(a) >>> b[4:0];
      4'b1000: alu_operation = a | b;
      4'b1001: alu_operation = a & b;
      default: alu_operation = 32'b0;
    endcase
  end
endfunction

// Memory interface assignments
assign mem_a = mem_addr_reg;
assign mem_dout = mem_data_out_reg;
assign mem_wr = mem_write_reg && mem_access_pending;

// Debug register output
assign dbgreg_dout = reg_file[1];

endmodule

