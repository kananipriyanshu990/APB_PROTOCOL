// Testbench for APB_DECODER.
// Since the decoder is purely combinational, stimulus is applied directly
// with #delays rather than clock-aligned tasks. PRDATA0/1/2 are driven
// with $urandom values to verify the mux routes the correct one.
// Inspect PSEL0/PSEL1/PSEL2 and PRDATA in Vivado waveform.
//
// Test sequence:
//   1. Slave 0 address range   - PSEL0=1, PSEL1=0, PSEL2=0, PRDATA=PRDATA0
//   2. Slave 1 address range   - PSEL0=0, PSEL1=1, PSEL2=0, PRDATA=PRDATA1
//   3. Slave 2 address range   - PSEL0=0, PSEL1=0, PSEL2=1, PRDATA=PRDATA2
//   4. Out-of-range address    - all PSEL=0, PRDATA=0x00000000
//   5. Address sweep           - walks through all three ranges in sequence
//   6. PRDATA mux isolation    - unique random data per slave, verify routing
`timescale 1ns/1ps

module APB_DECODER_TB;

// ============================================================
// DUT SIGNALS
// ============================================================
reg [31:0] PADDR;
reg [31:0] PRDATA0;
reg [31:0] PRDATA1;
reg [31:0] PRDATA2;
wire [31:0] PRDATA;
wire PSEL0;
wire PSEL1;
wire PSEL2;

// ============================================================
// DUT INSTANTIATION
// ============================================================
APB_DECODER DUT (.PRDATA  (PRDATA),
                 .PSEL0   (PSEL0),
                 .PSEL1   (PSEL1),
                 .PSEL2   (PSEL2),
                 .PADDR   (PADDR),
                 .PRDATA0 (PRDATA0),
                 .PRDATA1 (PRDATA1),
                 .PRDATA2 (PRDATA2));

// ============================================================
// STIMULUS
// No clock needed - purely combinational DUT.
// #20 delay between cases gives clean separation on waveform.
// ============================================================
integer i;

initial begin

    // --------------------------------------------------------
    // INITIALISE
    // --------------------------------------------------------
    PADDR   = 32'h0000_0000;
    PRDATA0 = 32'h0000_0000;
    PRDATA1 = 32'h0000_0000;
    PRDATA2 = 32'h0000_0000;
    #20;

    // --------------------------------------------------------
    // TEST 1 : SLAVE 0 ADDRESS RANGE (0x0000_0000 - 0x0000_00FF)
    // Apply random data to all three slave PRDATA inputs.
    // Observe : PSEL0=1, PSEL1=0, PSEL2=0, PRDATA=PRDATA0
    // --------------------------------------------------------
    PRDATA0 = $urandom;
    PRDATA1 = $urandom;
    PRDATA2 = $urandom;
    PADDR   = 32'h0000_0000;
    #20;
    PADDR   = 32'h0000_0040;   // Mid-range of Slave 0
    #20;
    PADDR   = 32'h0000_00FC;   // Near end of Slave 0
    #20;

    // --------------------------------------------------------
    // TEST 2 : SLAVE 1 ADDRESS RANGE (0x0000_0100 - 0x0000_01FF)
    // Observe : PSEL0=0, PSEL1=1, PSEL2=0, PRDATA=PRDATA1
    // --------------------------------------------------------
    PRDATA0 = $urandom;
    PRDATA1 = $urandom;
    PRDATA2 = $urandom;
    PADDR   = 32'h0000_0100;
    #20;
    PADDR   = 32'h0000_0140;   // Mid-range of Slave 1
    #20;
    PADDR   = 32'h0000_01FC;   // Near end of Slave 1
    #20;

    // --------------------------------------------------------
    // TEST 3 : SLAVE 2 ADDRESS RANGE (0x0000_0200 - 0x0000_02FF)
    // Observe : PSEL0=0, PSEL1=0, PSEL2=1, PRDATA=PRDATA2
    // --------------------------------------------------------
    PRDATA0 = $urandom;
    PRDATA1 = $urandom;
    PRDATA2 = $urandom;
    PADDR   = 32'h0000_0200;
    #20;
    PADDR   = 32'h0000_0240;   // Mid-range of Slave 2
    #20;
    PADDR   = 32'h0000_02FC;   // Near end of Slave 2
    #20;

    // --------------------------------------------------------
    // TEST 4 : OUT-OF-RANGE ADDRESS
    // Addresses beyond all three slaves.
    // Observe : PSEL0=0, PSEL1=0, PSEL2=0, PRDATA=0x00000000
    // --------------------------------------------------------
    PRDATA0 = $urandom;
    PRDATA1 = $urandom;
    PRDATA2 = $urandom;
    PADDR   = 32'h0000_0300;   // Just outside Slave 2 range
    #20;
    PADDR   = 32'hFFFF_FFFF;   // Far out of range
    #20;
    PADDR   = 32'h0000_0400;
    #20;

    // --------------------------------------------------------
    // TEST 5 : ADDRESS SWEEP
    // Rapidly switch across all three slave ranges.
    // Observe : PSEL and PRDATA switch cleanly with each address
    // --------------------------------------------------------
    PRDATA0 = $urandom;
    PRDATA1 = $urandom;
    PRDATA2 = $urandom;
    for (i = 0; i < 4; i = i + 1) begin
        PADDR = 32'h0000_0000 | (i * 4);   // Slave 0 registers
        #20;
    end
    for (i = 0; i < 4; i = i + 1) begin
        PADDR = 32'h0000_0100 | (i * 4);   // Slave 1 registers
        #20;
    end
    for (i = 0; i < 4; i = i + 1) begin
        PADDR = 32'h0000_0200 | (i * 4);   // Slave 2 registers
        #20;
    end

    // --------------------------------------------------------
    // TEST 6 : PRDATA MUX ISOLATION
    // Give each slave a distinct random value. Apply each slave's
    // address and confirm only that slave's PRDATA appears.
    // Repeat with fresh random values to cover more scenarios.
    // --------------------------------------------------------
    repeat(6) begin
        PRDATA0 = $urandom;
        PRDATA1 = $urandom;
        PRDATA2 = $urandom;

        PADDR = 32'h0000_0000;   // Should see PRDATA0
        #20;
        PADDR = 32'h0000_0100;   // Should see PRDATA1
        #20;
        PADDR = 32'h0000_0200;   // Should see PRDATA2
        #20;
    end

    // --------------------------------------------------------
    // END OF SIMULATION
    // --------------------------------------------------------
    #20;
    $finish;

end

endmodule