// 4-register APB slave. Instantiates four APB_SLAVE_REG modules.
// Register selection is driven by PADDR[3:2]; each register receives
// an individual PSEL gated with its address hit so only the addressed
// register captures PWDATA. PRDATA is a combinational mux of all four
// register outputs, selected by PADDR[3:2].
// PREADY is tied high - zero wait states.
//
// Register map (relative to this slave's base address):
//   PADDR[3:2] = 2'b00  ->  REG0  (offset 0x00)
//   PADDR[3:2] = 2'b01  ->  REG1  (offset 0x04)
//   PADDR[3:2] = 2'b10  ->  REG2  (offset 0x08)
//   PADDR[3:2] = 2'b11  ->  REG3  (offset 0x0C)
module APB_SLAVE (
    output wire [31:0] PRDATA,      // Read data back to master (mux of 4 regs)
    output wire PREADY,             // Always ready - tied high
    input  wire [31:0] PWDATA,      // APB write data
    input  wire [31:0] PADDR,       // APB address (only [3:2] used here)
    input  wire  PSEL,              // APB slave select from decoder
    input  wire  PENABLE,           // APB enable - ACCESS phase
    input  wire  PWRITE,            // Transfer direction: 1=Write 0=Read
    input  wire  PCLK,              // APB clock
    input  wire  PRESETn            // Active-low asynchronous reset
);

    // --------------------------------------------------------
    // PREADY - zero wait states
    // --------------------------------------------------------
    assign PREADY = 1'b1;

    // --------------------------------------------------------
    // PER-REGISTER PSEL - gated with address decode
    // Only the addressed register sees PSEL=1.
    // --------------------------------------------------------
    wire REG0_SEL = PSEL & (PADDR[3:2] == 2'b00);
    wire REG1_SEL = PSEL & (PADDR[3:2] == 2'b01);
    wire REG2_SEL = PSEL & (PADDR[3:2] == 2'b10);
    wire REG3_SEL = PSEL & (PADDR[3:2] == 2'b11);

    // --------------------------------------------------------
    // REGISTER DATA OUTPUTS
    // --------------------------------------------------------
    wire [31:0] REG0_DATA;
    wire [31:0] REG1_DATA;
    wire [31:0] REG2_DATA;
    wire [31:0] REG3_DATA;

    // --------------------------------------------------------
    // REGISTER INSTANTIATIONS
    // PENABLE and PWRITE are shared - REG_SEL differentiates.
    // --------------------------------------------------------
    APB_SLAVE_REG REG0 (.REG_DATA (REG0_DATA),
                                            .PWDATA   (PWDATA),
                                            .PSEL     (REG0_SEL),
                                            .PENABLE  (PENABLE),
                                            .PWRITE   (PWRITE),
                                            .PCLK     (PCLK),
                                            .PRESETn  (PRESETn) );

    APB_SLAVE_REG REG1 (.REG_DATA (REG1_DATA),
                                            .PWDATA   (PWDATA),
                                            .PSEL     (REG1_SEL),
                                            .PENABLE  (PENABLE),
                                            .PWRITE   (PWRITE),
                                            .PCLK     (PCLK),
                                            .PRESETn  (PRESETn));

    APB_SLAVE_REG REG2 (.REG_DATA (REG2_DATA),
                                            .PWDATA   (PWDATA),
                                            .PSEL     (REG2_SEL),
                                            .PENABLE  (PENABLE),
                                            .PWRITE   (PWRITE),
                                            .PCLK     (PCLK),
                                            .PRESETn  (PRESETn));

    APB_SLAVE_REG REG3 (
        .REG_DATA (REG3_DATA),
        .PWDATA   (PWDATA),
        .PSEL     (REG3_SEL),
        .PENABLE  (PENABLE),
        .PWRITE   (PWRITE),
        .PCLK     (PCLK),
        .PRESETn  (PRESETn)
    );

    // --------------------------------------------------------
    // PRDATA MUX - combinational, selects addressed register
    // --------------------------------------------------------
    reg [31:0] PRDATA_REG;

    always @(*) begin
        case (PADDR[3:2])
            2'b00 : begin PRDATA_REG = REG0_DATA; end
            2'b01 : begin PRDATA_REG = REG1_DATA; end
            2'b10 : begin PRDATA_REG = REG2_DATA; end
            2'b11 : begin PRDATA_REG = REG3_DATA; end
        endcase
    end

    assign PRDATA = PRDATA_REG;

endmodule