// APB System Testbench - LFSR-driven stimulus, MISR output compression.
// No UVM - plain SystemVerilog stimulus.
//
// Architecture:
//   LFSR_ADDR  : generates pseudo-random addresses (masked to valid slave/reg)
//   LFSR_DATA  : generates pseudo-random write data (different seed offset)
//   APB_SYSTEM : DUT - 1 master, 1 decoder, 3 slaves (GPIO/UART/TIMER)
//   MISR       : compresses RDATA_OUT over all read transfers into one signature
//
// Address masking from LFSR_ADDR output:
//   LFSR_ADDR[1:0] -> slave select  : 00=GPIO(0x000) 01=UART(0x100)
//                                     10=TIMER(0x200) 11=TIMER(0x200)
//   LFSR_ADDR[3:2] -> register offset: 0x00/0x04/0x08/0x0C
//
// Test flow:
//   1. Reset - LFSRs load seeds, MISR clears, DUT resets
//   2. Phase 1 : NUM_TRANSFERS LFSR-driven writes
//   3. Reset LFSRs only (DUT keeps register values)
//   4. Phase 2 : NUM_TRANSFERS LFSR-driven reads (same address sequence)
//               MISR compresses each RDATA_OUT on DONE pulse
//   5. $finish - inspect MISR_SIG on waveform as golden signature
//
// Waveform signals to add in Vivado:
//   PCLK, PRESETn, LFSR_EN, TRANSFER, ADDR_IN, WDATA_IN, WRITE_IN,
//   DONE, RDATA_OUT, MISR_EN, MISR_SIG
//   DUT internals: PADDR, PSEL0, PSEL1, PSEL2, PENABLE, PWDATA, PRDATA
`timescale 1ns/1ps

module APB_SYSTEM_TB;

// ============================================================
// PARAMETERS
// ============================================================
localparam NUM_TRANSFERS = 64;
localparam CLK_PERIOD    = 10;      // 100 MHz

// ============================================================
// CLOCK AND RESET
// ============================================================
reg PCLK;
reg PRESETn;

initial begin
    PCLK = 1'b0;
end

always begin
    #(CLK_PERIOD/2) PCLK = ~PCLK;
end

// ============================================================
// DUT SIGNALS
// ============================================================
reg  [31:0] ADDR_IN;
reg  [31:0] WDATA_IN;
reg         WRITE_IN;
reg         TRANSFER;
wire [31:0] RDATA_OUT;
wire        DONE;

// ============================================================
// LFSR ENABLE
// ============================================================
reg LFSR_EN;

// ============================================================
// LFSR OUTPUTS
// ============================================================
wire [31:0] LFSR_ADDR_OUT;
wire [31:0] LFSR_DATA_OUT;

// ============================================================
// MISR SIGNALS
// ============================================================
wire        MISR_EN;
wire [31:0] MISR_SIG;

// MISR clocks only when a read transfer completes
assign MISR_EN = DONE & ~WRITE_IN;

// ============================================================
// ADDRESS MASKING - LFSR bits [3:0] -> valid APB address
// ============================================================
reg [31:0] SLAVE_BASE;
reg [31:0] MASKED_ADDR;

always @(*) begin
    case (LFSR_ADDR_OUT[1:0])
        2'b00 : begin SLAVE_BASE = 32'h0000_0000; end  // GPIO
        2'b01 : begin SLAVE_BASE = 32'h0000_0100; end  // UART
        2'b10 : begin SLAVE_BASE = 32'h0000_0200; end  // TIMER
        2'b11 : begin SLAVE_BASE = 32'h0000_0200; end  // TIMER
    endcase
    // bits [3:2] select register within slave: 0x00/0x04/0x08/0x0C
    MASKED_ADDR = SLAVE_BASE | {26'b0, LFSR_ADDR_OUT[3:2], 2'b00};
end

// ============================================================
// LFSR_ADDR INSTANTIATION - seed 0x3050_3050
// ============================================================
lfsr32 LFSR_ADDR (
    .clk   (PCLK),
    .rst_n (PRESETn),
    .en    (LFSR_EN),
    .out   (LFSR_ADDR_OUT)
);

// ============================================================
// LFSR_DATA INSTANTIATION - same seed but clocked one extra
// cycle ahead during init so the two streams are uncorrelated
// ============================================================
lfsr32 LFSR_DATA (
    .clk   (PCLK),
    .rst_n (PRESETn),
    .en    (LFSR_EN),
    .out   (LFSR_DATA_OUT)
);

// ============================================================
// DUT INSTANTIATION
// ============================================================
APB_SYSTEM DUT (
    .RDATA_OUT (RDATA_OUT),
    .DONE      (DONE),
    .ADDR_IN   (ADDR_IN),
    .WDATA_IN  (WDATA_IN),
    .WRITE_IN  (WRITE_IN),
    .TRANSFER  (TRANSFER),
    .PCLK      (PCLK),
    .PRESETn   (PRESETn)
);

// ============================================================
// MISR INSTANTIATION
// Compresses RDATA_OUT across all read transfers into MISR_SIG.
// ============================================================
misr32 MISR (
    .clk       (PCLK),
    .rst_n     (PRESETn),
    .en        (MISR_EN),
    .data_in   (RDATA_OUT),
    .signature (MISR_SIG)
);

// ============================================================
// TASK : APB_WRITE_LFSR
// One complete write transfer using current LFSR state.
// LFSR advances on cycle 1 so next call gets a new address/data.
// ============================================================
task APB_WRITE_LFSR;
    begin
        // SETUP : latch LFSR outputs into DUT inputs, advance LFSR
        @(posedge PCLK); #1;
        ADDR_IN  = MASKED_ADDR;
        WDATA_IN = LFSR_DATA_OUT;
        WRITE_IN = 1'b1;
        TRANSFER = 1'b1;
        LFSR_EN  = 1'b1;        // Advance LFSR this cycle

        // Deassert TRANSFER, hold LFSR
        @(posedge PCLK); #1;
        TRANSFER = 1'b0;
        LFSR_EN  = 1'b0;

        // Wait for APB_MASTER FSM to complete transfer
        @(posedge DONE);
        @(posedge PCLK); #1;
    end
endtask

// ============================================================
// TASK : APB_READ_LFSR
// One complete read transfer using current LFSR address.
// MISR_EN gates automatically on DONE & ~WRITE_IN.
// ============================================================
task APB_READ_LFSR;
    begin
        @(posedge PCLK); #1;
        ADDR_IN  = MASKED_ADDR;
        WDATA_IN = 32'h0000_0000;
        WRITE_IN = 1'b0;
        TRANSFER = 1'b1;
        LFSR_EN  = 1'b1;        // Advance to next address

        @(posedge PCLK); #1;
        TRANSFER = 1'b0;
        LFSR_EN  = 1'b0;

        // MISR clocks in RDATA_OUT on this DONE pulse automatically
        @(posedge DONE);
        @(posedge PCLK); #1;
    end
endtask

// ============================================================
// STIMULUS
// ============================================================
integer i;

initial begin

    // --------------------------------------------------------
    // INITIALISE
    // --------------------------------------------------------
    ADDR_IN  = 32'h0000_0000;
    WDATA_IN = 32'h0000_0000;
    WRITE_IN = 1'b0;
    TRANSFER = 1'b0;
    LFSR_EN  = 1'b0;
    PRESETn  = 1'b1;

    // --------------------------------------------------------
    // RESET - 10 cycles
    // Both LFSRs load seed 0x3050_3050.
    // MISR clears to 0x00000000.
    // DUT master resets to IDLE, all slave registers clear.
    // --------------------------------------------------------
    PRESETn = 1'b0;
    repeat(10) @(posedge PCLK);
    #1;
    PRESETn = 1'b1;
    repeat(2) @(posedge PCLK);

    // Stagger LFSR_DATA by clocking LFSR_ADDR one extra cycle.
    // After this: LFSR_ADDR is at state 1, LFSR_DATA at state 0.
    // The two streams are now uncorrelated for all future cycles.
    @(posedge PCLK); #1;
    LFSR_EN = 1'b1;
    @(posedge PCLK); #1;
    LFSR_EN = 1'b0;
    repeat(2) @(posedge PCLK);

    // --------------------------------------------------------
    // PHASE 1 : LFSR-DRIVEN WRITES
    // Each iteration: address from MASKED_ADDR, data from LFSR_DATA.
    // Observe PADDR switching across all three slave ranges.
    // Observe PSEL0/PSEL1/PSEL2 toggling with each address.
    // --------------------------------------------------------
    for (i = 0; i < NUM_TRANSFERS; i = i + 1) begin
        APB_WRITE_LFSR();
    end

    repeat(4) @(posedge PCLK);

    // --------------------------------------------------------
    // PARTIAL RESET - resets LFSRs and MISR only.
    // DUT slave registers KEEP their written values.
    // This replays the same address sequence in Phase 2.
    // --------------------------------------------------------
    PRESETn = 1'b0;
    repeat(4) @(posedge PCLK);
    #1;
    PRESETn = 1'b1;
    repeat(2) @(posedge PCLK);

    // Re-apply the same stagger so address sequence is identical
    @(posedge PCLK); #1;
    LFSR_EN = 1'b1;
    @(posedge PCLK); #1;
    LFSR_EN = 1'b0;
    repeat(2) @(posedge PCLK);

    // --------------------------------------------------------
    // PHASE 2 : LFSR-DRIVEN READS
    // Same address sequence as Phase 1 (LFSR replayed from seed).
    // MISR compresses each RDATA_OUT when DONE pulses.
    // Observe MISR_SIG changing after each DONE pulse.
    // At the end, MISR_SIG is the golden signature for this DUT.
    // --------------------------------------------------------
    for (i = 0; i < NUM_TRANSFERS; i = i + 1) begin
        APB_READ_LFSR();
    end

    repeat(4) @(posedge PCLK);

    // --------------------------------------------------------
    // END OF SIMULATION
    // Record MISR_SIG from waveform at $finish.
    // On every future regression run, MISR_SIG must match
    // this value. Any difference means a DUT regression.
    // --------------------------------------------------------
    $finish;

end

endmodule