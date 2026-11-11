// Testbench for APB_SLAVE.
// Drives APB transactions to all four internal registers via PADDR[3:2].
// Inspect PRDATA and individual REG_DATA outputs in Vivado waveform.
//
// Test sequence:
//   1. Reset                          - all REG_DATA outputs must be 0x00000000
//   2. Write all 4 registers          - each gets a unique value
//   3. Read back all 4 registers      - PRDATA must match written value per address
//   4. Register independence          - write REG0, verify REG1/2/3 unchanged
//   5. Overwrite                      - write REG2 twice, verify final value wins
//   6. Reset clears all registers     - all REG_DATA back to 0x00000000
`timescale 1ns/1ps

module APB_SLAVE_TB;

// ============================================================
// DUT SIGNALS
// ============================================================
reg [31:0] PWDATA;
reg [31:0] PADDR;
reg PSEL;
reg PENABLE;
reg PWRITE;
reg PCLK;
reg PRESETn;
wire [31:0] PRDATA;
wire PREADY;

// ============================================================
// DUT INSTANTIATION
// Expose internal register outputs for waveform visibility.
// ============================================================
APB_SLAVE DUT (.PRDATA(PRDATA),
               .PREADY(PREADY),
               .PWDATA(PWDATA),
               .PADDR(PADDR),
               .PSEL(PSEL),
               .PENABLE(PENABLE),
               .PWRITE(PWRITE),
               .PCLK(PCLK),
               .PRESETn(PRESETn));

// ============================================================
// CLOCK GENERATION - 100 MHz (10 ns period)
// ============================================================
initial begin
    PCLK = 1'b0;
end

always begin
    #5 PCLK = ~PCLK;
end

// ============================================================
// TASK : APB_WRITE
// Full SETUP + ACCESS write to a given address.
// ============================================================
task APB_WRITE;
    input [31:0] ADDR;
    input [31:0] DATA;
    begin
        // SETUP phase
        @(posedge PCLK); #1;
        PSEL    = 1'b1;
        PENABLE = 1'b0;
        PWRITE  = 1'b1;
        PADDR   = ADDR;
        PWDATA  = DATA;

        // ACCESS phase
        @(posedge PCLK); #1;
        PENABLE = 1'b1;

        // Return to IDLE
        @(posedge PCLK); #1;
        PSEL    = 1'b0;
        PENABLE = 1'b0;
        PWRITE  = 1'b0;
        PADDR   = 32'h0000_0000;
        PWDATA  = 32'h0000_0000;
    end
endtask

// ============================================================
// TASK : APB_READ
// Full SETUP + ACCESS read from a given address.
// PRDATA is visible on waveform during ACCESS phase.
// ============================================================
task APB_READ;
    input [31:0] ADDR;
    begin
        // SETUP phase
        @(posedge PCLK); #1;
        PSEL    = 1'b1;
        PENABLE = 1'b0;
        PWRITE  = 1'b0;
        PADDR   = ADDR;

        // ACCESS phase
        @(posedge PCLK); #1;
        PENABLE = 1'b1;

        // Return to IDLE
        @(posedge PCLK); #1;
        PSEL    = 1'b0;
        PENABLE = 1'b0;
        PADDR   = 32'h0000_0000;
    end
endtask

// ============================================================
// STIMULUS
// ============================================================
initial begin

    // --------------------------------------------------------
    // INITIALISE
    // --------------------------------------------------------
    PWDATA  = 32'h0000_0000;
    PADDR   = 32'h0000_0000;
    PSEL    = 1'b0;
    PENABLE = 1'b0;
    PWRITE  = 1'b0;
    PRESETn = 1'b1;

    // --------------------------------------------------------
    // TEST 1 : RESET
    // All four registers must power up / reset to 0x00000000.
    // Observe : REG0/1/2/3 DATA all 0x00000000
    // --------------------------------------------------------
    PRESETn = 1'b0;
    repeat(2) @(posedge PCLK);
    #1;
    PRESETn = 1'b1;
    repeat(2) @(posedge PCLK);

    // --------------------------------------------------------
    // TEST 2 : WRITE ALL 4 REGISTERS
    // Each register gets a unique value.
    // PADDR[3:2] selects the register:
    //   0x00 -> REG0,  0x04 -> REG1,  0x08 -> REG2,  0x0C -> REG3
    // Observe : each REGx_DATA changes only on its write cycle
    // --------------------------------------------------------
    APB_WRITE(32'h0000_0000, 32'hAAAA_0000);   // REG0 = 0xAAAA0000
    APB_WRITE(32'h0000_0004, 32'hBBBB_1111);   // REG1 = 0xBBBB1111
    APB_WRITE(32'h0000_0008, 32'hCCCC_2222);   // REG2 = 0xCCCC2222
    APB_WRITE(32'h0000_000C, 32'hDDDD_3333);   // REG3 = 0xDDDD3333
    repeat(2) @(posedge PCLK);

    // --------------------------------------------------------
    // TEST 3 : READ BACK ALL 4 REGISTERS
    // PRDATA must reflect the correct register per address.
    // Observe : PRDATA changes with each read address
    //   0x00 -> 0xAAAA0000
    //   0x04 -> 0xBBBB1111
    //   0x08 -> 0xCCCC2222
    //   0x0C -> 0xDDDD3333
    // --------------------------------------------------------
    APB_READ(32'h0000_0000);    // Expect PRDATA = 0xAAAA0000
    APB_READ(32'h0000_0004);    // Expect PRDATA = 0xBBBB1111
    APB_READ(32'h0000_0008);    // Expect PRDATA = 0xCCCC2222
    APB_READ(32'h0000_000C);    // Expect PRDATA = 0xDDDD3333
    repeat(2) @(posedge PCLK);

    // --------------------------------------------------------
    // TEST 4 : REGISTER INDEPENDENCE
    // Write only REG0 with a new value.
    // REG1, REG2, REG3 must remain unchanged.
    // --------------------------------------------------------
    APB_WRITE(32'h0000_0000, 32'h1234_5678);   // REG0 = 0x12345678
    APB_READ(32'h0000_0000);    // Expect 0x12345678
    APB_READ(32'h0000_0004);    // Expect 0xBBBB1111 (unchanged)
    APB_READ(32'h0000_0008);    // Expect 0xCCCC2222 (unchanged)
    APB_READ(32'h0000_000C);    // Expect 0xDDDD3333 (unchanged)
    repeat(2) @(posedge PCLK);

    // --------------------------------------------------------
    // TEST 5 : OVERWRITE
    // --------------------------------------------------------
    APB_WRITE(32'h0000_0008, 32'h1463_2496);   // REG2 first write
    APB_WRITE(32'h0000_0008, 32'hAD27_8B3F);   // REG2 overwrite
    APB_READ(32'h0000_0008);    // Expect PRDATA = 0xCAFEBABE
    repeat(2) @(posedge PCLK);

    // --------------------------------------------------------
    // TEST 6 : RESET CLEARS ALL REGISTERS
    // --------------------------------------------------------
    PRESETn = 1'b0;
    repeat(2) @(posedge PCLK);
    PRESETn = 1'b1;
    APB_READ(32'h0000_0000);    // Expect 0x00000000
    APB_READ(32'h0000_0004);    // Expect 0x00000000
    APB_READ(32'h0000_0008);    // Expect 0x00000000
    APB_READ(32'h0000_000C);    // Expect 0x00000000
    repeat(2) @(posedge PCLK);

    // --------------------------------------------------------
    // END OF SIMULATION
    // --------------------------------------------------------
    $finish;

end

endmodule