// Full-processor testbench: loads a program and initial data through the external
// port, runs the CPU until it halts, then compares registers and data SRAM to expected values.
`timescale 1ns/1ps

module tb_processor;
    localparam time CLK_PERIOD = 20ns;

    localparam logic [13:0] ISRAM_BASE = 14'h0000;
    localparam logic [13:0] DSRAM_BASE = 14'h1000;
    localparam logic [13:0] REG_BASE   = 14'h2000;

    localparam int ISRAM_WORDS = 1024;
    localparam int DSRAM_WORDS = 1024;
    localparam int REG_COUNT   = 32;

    logic        clk_i = 1'b0;
    logic        rst_i;
    logic        cpu_en_i;
    logic        cpu_halt_o;
    logic 	 halt_cpu;
    logic [13:0] addr;
    logic [31:0] wdata;
    logic        w_en;
    logic        r_en;
    logic [31:0] rdata;
    logic        ready;

    logic [31:0] program_image       [0:ISRAM_WORDS-1];
    logic [31:0] initial_data_image  [0:DSRAM_WORDS-1]; //starting data for dsram
    logic [31:0] expected_data_image [0:DSRAM_WORDS-1]; //expected final dsram
    logic [31:0] expected_regs_image [0:REG_COUNT-1];

    string program_file;
    string data_file;
    string expected_data_file;
    string expected_regs_file;

    int program_words;
    int data_words;
    int expected_data_words;
    int max_cpu_cycles;
    int crossbar_timeout;
    int failures;

    always #(CLK_PERIOD / 2) clk_i = ~clk_i;

    chip_top dut (
        .clk_i        (clk_i),
        .rst_i        (rst_i),
        .en_cpu_i     (cpu_en_i),
        .cpu_halted_o (cpu_halt_o),
        .halt_cpu_i   (halt_cpu),
	.addr_i       (addr),
        .wdata_i      (wdata),
        .w_en_i       (w_en),
        .r_en_i       (r_en),
        .rdata_o      (rdata),
        .rready_o     (ready)
    );

    function automatic logic [13:0] word_address(
        input logic [13:0] base,
        input int unsigned word_index
    );
        word_address = base + (word_index << 2); //cleaning up byte offset
    endfunction

    task automatic crossbar_write(
        input logic [13:0] write_addr,
        input logic [31:0] write_data
    );
        int wait_cycles;
        begin
            if (write_addr[1:0] != 2'b00)
                $fatal(1, "Crossbar write address %h is not word-aligned",
                       write_addr);

            @(negedge clk_i);
            addr  <= write_addr;
            wdata <= write_data;
            w_en  <= 1'b1;
            r_en  <= 1'b0;

            @(negedge clk_i);
            w_en  <= 1'b0;
            addr  <= '0;
            wdata <= '0;
        end
    endtask

    task automatic crossbar_read(
        input  logic [13:0] read_addr,
        output logic [31:0] read_data
    );
        int wait_cycles;
        begin
            if (read_addr[1:0] != 2'b00)
                $fatal(1, "Crossbar read address %h is not word-aligned",
                       read_addr);

            @(negedge clk_i);
            addr <= read_addr;
            w_en <= 1'b0;
            r_en <= 1'b1;

            wait_cycles = 0;
            while (ready !== 1'b1) begin
                @(posedge clk_i);
                #1;
                wait_cycles++;
                if (wait_cycles >= crossbar_timeout)
                    $fatal(1,
                           "Crossbar read timed out at address %h",
                           read_addr);
            end

            read_data = rdata;

            @(negedge clk_i);
            r_en <= 1'b0;
            addr <= '0;
        end
    endtask

    task automatic reset_dut;
        begin
            cpu_en_i <= 1'b0;
            rst_i    <= 1'b1;
            repeat (3) @(posedge clk_i);
            @(negedge clk_i);
            rst_i <= 1'b0;
        end
    endtask

    task automatic load_program;
        int i;
        begin
            $display("Loading %0d instruction words from %s",
                     program_words, program_file);
            $readmemh(program_file, program_image);
            for (i = 0; i < program_words; i++)
                crossbar_write(word_address(ISRAM_BASE, i),
                               program_image[i]);
        end
    endtask

    task automatic load_initial_data;
        int i;
        begin
            if (data_words > 0) begin
                $display("Loading %0d data words from %s",
                         data_words, data_file);
                $readmemh(data_file, initial_data_image);
                for (i = 0; i < data_words; i++)
                    crossbar_write(word_address(DSRAM_BASE, i),
                                   initial_data_image[i]);
            end
        end
    endtask

    task automatic run_until_halt;
        int cycles;
        begin
            @(negedge clk_i);
            cpu_en_i <= 1'b1;
            cycles = 0;
	    @(negedge clk_i);
	    cpu_en_i <= 1'b0;
            while (cpu_halt_o !== 1'b1) begin
                @(posedge clk_i);
                #1;
                cycles++;
                if (cycles >= max_cpu_cycles)
                    $fatal(1, "CPU did not halt within %0d cycles",
                           max_cpu_cycles);
            end

            $display("CPU halted after %0d cycles", cycles);
            @(negedge clk_i);
            cpu_en_i <= 1'b0;
	    repeat (3) @(negedge clk_i);
        end
    endtask

    task automatic check_word(
        input logic [13:0] check_addr,
        input logic [31:0] expected,
        input string       description
    );
        logic [31:0] actual;
        begin
            crossbar_read(check_addr, actual);
            if (actual !== expected) begin
                failures++;
                $error("FAIL: %s at %h: expected %h, got %h",
                       description, check_addr, expected, actual);
            end
        end
    endtask

    task automatic check_registers;
        int i;
        begin
            $readmemh(expected_regs_file, expected_regs_image);
            for (i = 0; i < REG_COUNT; i++)
                check_word(word_address(REG_BASE, i),
                           expected_regs_image[i],
                           $sformatf("register x%0d", i));
        end
    endtask

    task automatic check_data_memory;
        int i;
        begin
            if (expected_data_words > 0) begin
                $readmemh(expected_data_file, expected_data_image);
                for (i = 0; i < expected_data_words; i++)
                    check_word(word_address(DSRAM_BASE, i),
                               expected_data_image[i],
                               $sformatf("data word %0d", i));
            end
        end
    endtask

    initial begin
        $shm_open("waves.shm");
        $shm_probe("AC");

        rst_i        = 1'b1;
        cpu_en_i     = 1'b0;
        halt_cpu     = 1'b0;
	addr         = '0;
        wdata        = '0;
        w_en         = 1'b0;
        r_en         = 1'b0;
        failures     = 0;
        program_words       = 0;
        data_words          = 0;
        expected_data_words = 0;
        max_cpu_cycles      = 1000;
        crossbar_timeout    = 20;

        if (!$value$plusargs("PROGRAM=%s", program_file))
            $fatal(1, "Missing required +PROGRAM=<program.hex> plusarg");
        if (!$value$plusargs("PROGRAM_WORDS=%d", program_words) ||
            program_words <= 0 || program_words > ISRAM_WORDS)
            $fatal(1, "PROGRAM_WORDS must be between 1 and %0d",
                   ISRAM_WORDS);

        if ($value$plusargs("DATA=%s", data_file)) begin
            if (!$value$plusargs("DATA_WORDS=%d", data_words) ||
                data_words < 0 || data_words > DSRAM_WORDS)
                $fatal(1, "DATA_WORDS must be between 0 and %0d",
                       DSRAM_WORDS);
        end

        if (!$value$plusargs("EXPECTED_REGS=%s", expected_regs_file))
            $fatal(1,
                   "Missing required +EXPECTED_REGS=<expected_regs.hex> plusarg");

        if ($value$plusargs("EXPECTED_DATA=%s", expected_data_file)) begin
            if (!$value$plusargs("EXPECTED_DATA_WORDS=%d",
                                 expected_data_words) ||
                expected_data_words < 0 ||
                expected_data_words > DSRAM_WORDS)
                $fatal(1, "EXPECTED_DATA_WORDS must be between 0 and %0d",
                       DSRAM_WORDS);
        end

        void'($value$plusargs("MAX_CPU_CYCLES=%d", max_cpu_cycles));
        void'($value$plusargs("CROSSBAR_TIMEOUT=%d", crossbar_timeout));

        reset_dut();
        load_program();
        load_initial_data();
        run_until_halt();
        check_registers();
        check_data_memory();

        if (failures == 0)
            $display("PASS: processor behavior matches expected results");
        else
            $fatal(1, "FAIL: processor test found %0d mismatch(es)",
                   failures);

        $finish;
    end

endmodule
