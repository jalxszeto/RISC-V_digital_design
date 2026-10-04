// Standalone testbench for the fetch module: drives the SRAM, stall and branch
// inputs directly and reports PASS/FAIL for each check.
`timescale 1ns/1ps

module tb_fetch;

	localparam time CLK_PERIOD = 20ns;

	logic        clk_i = 1'b0;
	logic        rst_i;
	logic        en_i;
	logic        stall_core_i;

	logic        isram_en_o;
	logic [9:0]  isram_addr_o;
	logic [31:0] isram_rdata_i;
	logic        isram_rready_i;

	logic [31:0] instr_o;
	logic [31:0] pc_o;
	logic        instr_vld_o;

	logic        branch_vld_i;
	logic [9:0]  branch_trgt_i;
	logic        branch_taken_i;

	int failures = 0;

	always #(CLK_PERIOD / 2) clk_i = ~clk_i;

	fetch dut (
		.clk_i          (clk_i),
		.rst_i          (rst_i),
		.en_i           (en_i),
		.stall_core_i   (stall_core_i),
		.isram_en_o     (isram_en_o),
		.isram_addr_o   (isram_addr_o),
		.isram_rdata_i  (isram_rdata_i),
		.isram_rready_i (isram_rready_i),
		.instr_o        (instr_o),
		.pc_o           (pc_o),
		.instr_vld_o    (instr_vld_o),
		.branch_vld_i   (branch_vld_i),
		.branch_trgt_i  (branch_trgt_i),
		.branch_taken_i (branch_taken_i)
	);

	initial begin
		$shm_open("waves.shm");
		$shm_probe("AC");
	end

	task automatic check(input string name, input logic condition);
		if (condition) begin
			$display("PASS: %s", name);
		end else begin
			$display("FAIL: %s", name);
			failures++;
		end
	endtask

	initial begin
		rst_i          = 1'b1;
		en_i           = 1'b0;
		stall_core_i   = 1'b0;
		isram_rdata_i  = 32'h0000_0013;
		isram_rready_i = 1'b0;
		branch_vld_i   = 1'b0;
		branch_trgt_i  = 10'd0;
		branch_taken_i = 1'b0;

		repeat (2) @(posedge clk_i);

		assert (0 == 0) else $error("assert demo");

		check("pc resets to zero", pc_o === 32'h0000_0000);

		rst_i = 1'b0;
		en_i  = 1'b1;

		@(posedge clk_i);

		check("isram is enabled", isram_en_o === 1'b1);

		@(posedge clk_i);
		isram_rready_i = 1'b1;

		@(posedge clk_i);
		check("instruction is presented", instr_o === isram_rdata_i);
		check("instruction is valid", instr_vld_o === 1'b1);

		repeat (4) @(posedge clk_i);

		if (failures == 0) begin
			$display("RESULT: PASS");
		end else begin
			$display("RESULT: FAIL (%0d checks)", failures);
		end
		$finish;
	end

endmodule
