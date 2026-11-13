// Testbench for APB_MASTER.
// A simple slave model is instantiated inside the testbench to drive
// PRDATA and PREADY, so the master FSM has realistic responses to react to.
// Inspect STATE, PSEL, PENABLE, PWRITE, PADDR, PWDATA, PRDATA,
// RDATA_OUT, and DONE in Vivado waveform.
//
// Test sequence:
//   1. Reset                          - master stays in IDLE, all outputs 0
//   2. Single write transfer          - IDLE->SETUP->ACCESS->IDLE, DONE pulses
//   3. Single read transfer           - RDATA_OUT captures PRDATA on DONE
//   4. Wait state on write            - PREADY held low for 2 cycles then released
//   5. Wait state on read             - PREADY held low for 3 cycles then released
//   6. Back-to-back transfers         - TRANSFER asserted each time DONE pulses
//   7. TRANSFER ignored during ACCESS - no new transfer starts mid-transfer
`timescale 1ns/1ps

module APB_MASTER_TB;
    
    // ============================================================
    // DUT SIGNALS
    // ============================================================
    reg PCLK;
    reg PRESETn;
    reg [31:0] ADDR_IN;
    reg [31:0] WDATA_IN;
    reg WRITE_IN;
    reg TRANSFER;
    reg [31:0] PRDATA;
    reg  PREADY;
    wire [31:0] PADDR;
    wire [31:0] PWDATA;
    wire PSEL;
    wire PENABLE;
    wire PWRITE;
    wire [31:0] RDATA_OUT;
    wire DONE;
    
    // ============================================================
    // DUT INSTANTIATION
    // ============================================================
    APB_MASTER DUT (.PADDR     (PADDR),
                    .PWDATA    (PWDATA),
                    .PSEL      (PSEL),
                    .PENABLE   (PENABLE),
                    .PWRITE    (PWRITE),
                    .RDATA_OUT (RDATA_OUT),
                    .DONE      (DONE),
                    .PRDATA    (PRDATA),
                    .PREADY    (PREADY),
                    .ADDR_IN   (ADDR_IN),
                    .WDATA_IN  (WDATA_IN),
                    .WRITE_IN  (WRITE_IN),
                    .TRANSFER  (TRANSFER),
                    .PCLK      (PCLK),
                    .PRESETn   (PRESETn));
    
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
    // TASK : DO_WRITE
    // Asserts TRANSFER for one cycle with write parameters.
    // Then waits for DONE to pulse before returning.
    // ============================================================
    task DO_WRITE;
        input [31:0] ADDR;
        input [31:0] DATA;
        begin
            @(posedge PCLK); #1;
            ADDR_IN  = ADDR;
            WDATA_IN = DATA;
            WRITE_IN = 1'b1;
            TRANSFER = 1'b1;
    
            @(posedge PCLK); #1;
            TRANSFER = 1'b0;
    
            // Wait for transfer to complete
            @(posedge DONE);
            @(posedge PCLK); #1;
        end
    endtask
    
    // ============================================================
    // TASK : DO_READ
    // Asserts TRANSFER for one cycle with read parameters.
    // Then waits for DONE to pulse before returning.
    // ============================================================
    task DO_READ;
        input [31:0] ADDR;
        begin
            @(posedge PCLK); #1;
            ADDR_IN  = ADDR;
            WDATA_IN = 32'h0000_0000;
            WRITE_IN = 1'b0;
            TRANSFER = 1'b1;
    
            @(posedge PCLK); #1;
            TRANSFER = 1'b0;
    
            // Wait for transfer to complete
            @(posedge DONE);
            @(posedge PCLK); #1;
        end
    endtask
    
    // ============================================================
    // STIMULUS
    // ============================================================
    initial begin
    
        // --------------------------------------------------------
        // INITIALISE
        // --------------------------------------------------------
        ADDR_IN  = 32'h0000_0000;
        WDATA_IN = 32'h0000_0000;
        WRITE_IN = 1'b0;
        TRANSFER = 1'b0;
        PRDATA   = 32'h0000_0000;
        PREADY   = 1'b1;
        PRESETn  = 1'b1;
    
        // --------------------------------------------------------
        // TEST 1 : RESET
        // Master must stay in IDLE. All outputs remain 0.
        // Observe : STATE=IDLE, PSEL=0, PENABLE=0, DONE=0
        // --------------------------------------------------------
        PRESETn = 1'b0;
        repeat(2) @(posedge PCLK);
        #1;
        PRESETn = 1'b1;
        repeat(3) @(posedge PCLK);
    
        // --------------------------------------------------------
        // TEST 2 : SINGLE WRITE TRANSFER
        // PREADY=1 (no wait states). Watch FSM: IDLE->SETUP->ACCESS->IDLE.
        // Observe : PSEL goes high in SETUP, PENABLE in ACCESS,
        //           DONE pulses 1 cycle, then bus returns to IDLE.
        // --------------------------------------------------------
        PREADY = 1'b1;
        DO_WRITE(32'h0000_0000, $urandom);
        repeat(2) @(posedge PCLK);
    
        // --------------------------------------------------------
        // TEST 3 : SINGLE READ TRANSFER
        // Drive a random value on PRDATA to simulate slave response.
        // Observe : RDATA_OUT captures PRDATA on the cycle DONE pulses.
        //           PWRITE=0 throughout.
        // --------------------------------------------------------
        PRDATA = $urandom;
        PREADY = 1'b1;
        DO_READ(32'h0000_0100);
        repeat(2) @(posedge PCLK);
    
        // --------------------------------------------------------
        // TEST 4 : WAIT STATES ON WRITE
        // Hold PREADY=0 for 2 cycles after ACCESS begins, then release.
        // Observe : master stays in ACCESS (PSEL=1, PENABLE=1) until
        //           PREADY goes high. DONE pulses when PREADY=1.
        // --------------------------------------------------------
        @(posedge PCLK); #1;
        ADDR_IN  = 32'h0000_0200;
        WDATA_IN = $urandom;
        WRITE_IN = 1'b1;
        TRANSFER = 1'b1;
    
        @(posedge PCLK); #1;
        TRANSFER = 1'b0;
        PREADY   = 1'b0;        // Insert wait states
    
        repeat(2) @(posedge PCLK); #1;
        PREADY = 1'b1;          // Release - transfer completes next cycle
    
        @(posedge DONE);
        @(posedge PCLK); #1;
        repeat(2) @(posedge PCLK);
    
        // --------------------------------------------------------
        // TEST 5 : WAIT STATES ON READ
        // Hold PREADY=0 for 3 cycles. PRDATA driven with random value.
        // Observe : RDATA_OUT only updates when PREADY finally goes high.
        // --------------------------------------------------------
        PRDATA = $urandom;
        @(posedge PCLK); #1;
        ADDR_IN  = 32'h0000_0004;
        WDATA_IN = 32'h0000_0000;
        WRITE_IN = 1'b0;
        TRANSFER = 1'b1;
    
        @(posedge PCLK); #1;
        TRANSFER = 1'b0;
        PREADY   = 1'b0;        // Insert wait states
    
        repeat(3) @(posedge PCLK); #1;
        PREADY = 1'b1;          // Release
    
        @(posedge DONE);
        @(posedge PCLK); #1;
        repeat(2) @(posedge PCLK);
    
        // --------------------------------------------------------
        // TEST 6 : BACK-TO-BACK TRANSFERS
        // Start a new transfer immediately after DONE pulses.
        // Observe : bus goes IDLE only for 1 cycle between transfers
        //           before entering SETUP again.
        // --------------------------------------------------------
        PREADY = 1'b1;
        DO_WRITE(32'h0000_0000, $urandom);
        DO_WRITE(32'h0000_0004, $urandom);
        DO_READ (32'h0000_0008);
        DO_WRITE(32'h0000_0200, $urandom);
        DO_READ (32'h0000_0100);
        repeat(2) @(posedge PCLK);
    
        // --------------------------------------------------------
        // TEST 7 : TRANSFER IGNORED DURING ACCESS (BUSY)
        // Assert TRANSFER while master is in ACCESS phase.
        // Observe : current transfer completes normally, no corruption,
        //           the mid-transfer TRANSFER pulse has no effect.
        // --------------------------------------------------------
        PREADY = 1'b0;          // Force wait state so we can inject TRANSFER
    
        @(posedge PCLK); #1;
        ADDR_IN  = 32'h0000_0008;
        WDATA_IN = $urandom;
        WRITE_IN = 1'b1;
        TRANSFER = 1'b1;
    
        @(posedge PCLK); #1;
        TRANSFER = 1'b0;        // Normal deassert
    
        // Now in ACCESS with PREADY=0 - assert TRANSFER again (should be ignored)
        @(posedge PCLK); #1;
        TRANSFER = 1'b1;        // Spurious TRANSFER during ACCESS
        PREADY   = 1'b1;        // Also release PREADY
    
        @(posedge PCLK); #1;
        TRANSFER = 1'b0;
    
        @(posedge DONE);
        repeat(3) @(posedge PCLK);
    
        // --------------------------------------------------------
        // END OF SIMULATION
        // --------------------------------------------------------
        $finish;
    
    end

endmodule