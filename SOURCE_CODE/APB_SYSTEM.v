// Top-level APB system. Purely structural - no logic, only wiring.
// Instantiates one APB_MASTER, one APB_DECODER, and three APB_SLAVE
// modules (Slave 0: GPIO, Slave 1: UART, Slave 2: TIMER).
//
// Address map:
//   Slave 0 GPIO  : 0x0000_0000 - 0x0000_00FF
//   Slave 1 UART  : 0x0000_0100 - 0x0000_01FF
//   Slave 2 TIMER : 0x0000_0200 - 0x0000_02FF
//
// External ports expose the master control interface so the
// system testbench can initiate transfers without reaching
// inside the hierarchy.
module APB_SYSTEM (
    output wire [31:0] RDATA_OUT,   // Read data captured by master
    output wire DONE,               // Transfer complete pulse (1 cycle)
    input  wire [31:0] ADDR_IN,     // Transfer address from testbench
    input  wire [31:0] WDATA_IN,    // Transfer write data from testbench
    input  wire WRITE_IN,           // Transfer direction: 1=Write 0=Read
    input  wire TRANSFER,           // Initiate transfer (1-cycle pulse)
    input  wire PCLK,               // System clock
    input  wire PRESETn);           // Active-low asynchronous reset

    // --------------------------------------------------------
    // INTERNAL BUS WIRES - master to decoder and slaves
    // --------------------------------------------------------
    wire [31:0] PADDR;          // Address bus
    wire [31:0] PWDATA;         // Write data bus
    wire MASTER_PSEL;    // Master PSEL to decoder
    wire PENABLE;        // Enable (ACCESS phase)
    wire PWRITE;         // Direction

    // --------------------------------------------------------
    // INTERNAL BUS WIRES - decoder to slaves
    // --------------------------------------------------------
    wire PSEL0;          // Slave 0 select
    wire PSEL1;          // Slave 1 select
    wire PSEL2;          // Slave 2 select

    // --------------------------------------------------------
    // INTERNAL BUS WIRES - slaves to decoder (read data)
    // --------------------------------------------------------
    wire [31:0] PRDATA0;        // Slave 0 read data
    wire [31:0] PRDATA1;        // Slave 1 read data
    wire [31:0] PRDATA2;        // Slave 2 read data

    // --------------------------------------------------------
    // INTERNAL BUS WIRES - decoder to master (muxed read data)
    // --------------------------------------------------------
    wire [31:0] PRDATA;         // Muxed read data back to master

    // --------------------------------------------------------
    // INTERNAL BUS WIRES - slaves to master (ready)
    // All slaves have PREADY tied high internally.
    // We OR all three here - only the selected slave's PREADY
    // matters but since all are tied high, result is always 1.
    // --------------------------------------------------------
    wire PREADY0;
    wire PREADY1;
    wire PREADY2;
    wire PREADY;
    assign PREADY = PREADY0 | PREADY1 | PREADY2;

    // --------------------------------------------------------
    // MASTER INSTANTIATION
    // --------------------------------------------------------
    APB_MASTER MASTER (.PADDR     (PADDR),
                       .PWDATA    (PWDATA),
                       .PSEL      (MASTER_PSEL),
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

    // --------------------------------------------------------
    // DECODER INSTANTIATION
    // --------------------------------------------------------
    APB_DECODER DECODER (.PRDATA      (PRDATA),
                         .PSEL0       (PSEL0),
                         .PSEL1       (PSEL1),
                         .PSEL2       (PSEL2),
                         .PADDR       (PADDR),
                         .MASTER_PSEL (MASTER_PSEL),
                         .PRDATA0     (PRDATA0),
                         .PRDATA1     (PRDATA1),
                         .PRDATA2     (PRDATA2));

    // --------------------------------------------------------
    // SLAVE 0 - GPIO (0x0000_0000 - 0x0000_00FF)
    // --------------------------------------------------------
    APB_SLAVE SLAVE0 (.PRDATA  (PRDATA0),
                      .PREADY  (PREADY0),
                      .PWDATA  (PWDATA),
                      .PADDR   (PADDR),
                      .PSEL    (PSEL0),
                      .PENABLE (PENABLE),
                      .PWRITE  (PWRITE),
                      .PCLK    (PCLK),
                      .PRESETn (PRESETn));

    // --------------------------------------------------------
    // SLAVE 1 - UART (0x0000_0100 - 0x0000_01FF)
    // --------------------------------------------------------
    APB_SLAVE SLAVE1 (.PRDATA  (PRDATA1),
                      .PREADY  (PREADY1),
                      .PWDATA  (PWDATA),
                      .PADDR   (PADDR),
                      .PSEL    (PSEL1),
                      .PENABLE (PENABLE),
                      .PWRITE  (PWRITE),
                      .PCLK    (PCLK),
                      .PRESETn (PRESETn));

    // --------------------------------------------------------
    // SLAVE 2 - TIMER (0x0000_0200 - 0x0000_02FF)
    // --------------------------------------------------------
    APB_SLAVE SLAVE2 (.PRDATA  (PRDATA2),
                      .PREADY  (PREADY2),
                      .PWDATA  (PWDATA),
                      .PADDR   (PADDR),
                      .PSEL    (PSEL2),
                      .PENABLE (PENABLE),
                      .PWRITE  (PWRITE),
                      .PCLK    (PCLK),
                      .PRESETn (PRESETn));

endmodule