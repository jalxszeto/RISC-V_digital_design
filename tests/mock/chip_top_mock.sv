// Verification-infrastructure mock. This is not a processor model.
// It implements the debug memory map and halts one cycle after CPU enable so
// the ebreak test can exercise the complete Makefile/testbench path.
module chip_top (
    input  logic        clk_i,
    input  logic        rst_i,
    input  logic        en_cpu_i,
    input  logic        halt_cpu_i,
    output logic        cpu_halted_o,
    
    // Crossbar Interface to memory + regfile
    input  logic [13:0] addr_i,
    input  logic [31:0] wdata_i,
    input  logic        w_en_i,
    input  logic        r_en_i,
    output logic [31:0] rdata_o,
    output logic        rready_o
);
    logic [31:0] isram [0:1023];
    logic [31:0] dsram [0:1023];
    logic [31:0] regs  [0:31];
    integer i;

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            cpu_halted_o <= 1'b0;
            for (i = 0; i < 32; i++)
                regs[i] <= 32'd0;
        end else begin
            if (en_cpu_i || halt_cpu_i)
                cpu_halted_o <= 1'b1;

            if (!en_cpu_i && w_en_i) begin
                case (addr_i[13:12])
                    2'b00: isram[addr_i[11:2]] <= wdata_i;
                    2'b01: dsram[addr_i[11:2]] <= wdata_i;
                    default: ;
                endcase
            end
        end
    end

    always_comb begin
        rready_o = !en_cpu_i && (w_en_i || r_en_i);
        rdata_o  = 32'd0;
        if (!en_cpu_i && r_en_i) begin
            case (addr_i[13:12])
                2'b00: rdata_o = isram[addr_i[11:2]];
                2'b01: rdata_o = dsram[addr_i[11:2]];
                2'b10: rdata_o = regs[addr_i[6:2]];
                default: rdata_o = 32'd0;
            endcase
        end
    end
endmodule