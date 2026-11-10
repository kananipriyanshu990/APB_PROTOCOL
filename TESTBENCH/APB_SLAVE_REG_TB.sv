// Testbench for APB_SLAVE_REG.
// Drives all meaningful APB stimulus combinations.
// Inspect REG_DATA behaviour on Vivado waveform.
//
// Test sequence:
//   1. Reset asserted                  - REG_DATA must be 0x00000000
//   2. Single write (0xDEADBEEF)       - REG_DATA must capture written value
//   3. Read cycle                      - REG_DATA must remain unchanged
//   4. Write then read (0xA5A5A5A5)    - REG_DATA must hold written value across read
//   5. Back-to-back writes             - REG_DATA must reflect last write
//   6. Reset clears written value      - REG_DATA must return to 0x00000000
`timescale 1ns/1ps

module APB_SLAVE_REG_TB;

// ============================================================
// DUT SIGNALS
// ============================================================
reg [31:0] PWDATA;
reg PSEL;
reg PENABLE;
reg PWRITE;
reg PCLK;
reg PRESETn;
wire [31:0] REG_DATA;

// ============================================================
// DUT INSTANTIATION
// ============================================================
APB_SLAVE_REG DUT (.REG_DATA(REG_DATA),
                   .PWDATA(PWDATA),
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
// Drives one complete SETUP + ACCESS write transaction.
// SETUP  : PSEL=1, PENABLE=0, PWRITE=1, PWDATA=DATA
// ACCESS : PSEL=1, PENABLE=1, PWRITE=1  (write commits on PCLK rising edge)
// IDLE   : all deasserted
// ============================================================
task APB_WRITE;
    input [31:0] DATA;
    begin
        // SETUP phase
        @(posedge PCLK); #1;
        PSEL = 1'b1;
        PENABLE = 1'b0;
        PWRITE = 1'b1;
        PWDATA = DATA;

        // ACCESS phase
        @(posedge PCLK); #1;
        PENABLE = 1'b1;

        // Return to IDLE
        @(posedge PCLK); #1;
        PSEL = 1'b0;
        PENABLE = 1'b0;
        PWRITE = 1'b0;
        PWDATA = 32'h0000_0000;
    end
endtask

// ============================================================
// TASK : APB_READ
// Drives one complete SETUP + ACCESS read transaction.
// PWRITE=0 so no write occurs; REG_DATA should be unchanged.
// ============================================================
task APB_READ;
    begin
        // SETUP phase
        @(posedge PCLK); #1;
        PSEL    = 1'b1;
        PENABLE = 1'b0;
        PWRITE  = 1'b0;

        // ACCESS phase
        @(posedge PCLK); #1;
        PENABLE = 1'b1;

        // Return to IDLE
        @(posedge PCLK); #1;
        PSEL = 1'b0;
        PENABLE = 1'b0;
    end
endtask

// ============================================================
// STIMULUS
// ============================================================
initial begin

    // --------------------------------------------------------
    // INITIALISE
    // --------------------------------------------------------
    PWDATA = 32'h0000_0000;
    PSEL = 1'b0;
    PENABLE = 1'b0;
    PWRITE = 1'b0;
    PRESETn = 1'b1;

    // --------------------------------------------------------
    // TEST 1 : RESET
    // --------------------------------------------------------
    PRESETn = 1'b0;
    repeat(2) @(posedge PCLK);
    #1;
    PRESETn = 1'b1;
    repeat(2) @(posedge PCLK);

    // --------------------------------------------------------
    // TEST 2 : SINGLE WRITE
    // --------------------------------------------------------
    APB_WRITE(32'hD0EB_EF57);
    repeat(2) @(posedge PCLK);

    // --------------------------------------------------------
    // TEST 3 : READ DOES NOT CHANGE REGISTER
    // --------------------------------------------------------
    APB_READ();
    repeat(2) @(posedge PCLK);

    // --------------------------------------------------------
    // TEST 4 : WRITE THEN READ
    // --------------------------------------------------------
    APB_WRITE(32'hA6C2_E18F);
    APB_READ();
    repeat(2) @(posedge PCLK);

    // --------------------------------------------------------
    // TEST 5 : BACK-TO-BACK WRITES
    // --------------------------------------------------------
    APB_WRITE(32'h3051_589D);
    APB_WRITE(32'h2E36_2858);
    repeat(2) @(posedge PCLK);

    // --------------------------------------------------------
    // TEST 6 : RESET CLEARS WRITTEN VALUE
    // --------------------------------------------------------
    APB_WRITE(32'hAC48_F83C);
    repeat(2) @(posedge PCLK);
    PRESETn = 1'b0;
    repeat(2) @(posedge PCLK);
    PRESETn = 1'b1;
    repeat(2) @(posedge PCLK);

    // --------------------------------------------------------
    // END OF SIMULATION
    // --------------------------------------------------------
    $finish;

end

endmodule