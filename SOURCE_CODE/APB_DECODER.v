// Purely combinational APB address decoder and PRDATA multiplexer.
// Decodes PADDR[9:8] to generate one-hot slave selects PSEL0/PSEL1/PSEL2,
// gated with MASTER_PSEL so slaves are never selected when bus is idle.
// Multiplexes PRDATA from the active slave back to the master.
// No clock or reset needed - this module contains no state.
//
// Address map:
//   PADDR[9:8] = 2'b00  ->  PSEL0  Slave 0 : GPIO  (0x0000_0000 - 0x0000_00FF)
//   PADDR[9:8] = 2'b01  ->  PSEL1  Slave 1 : UART  (0x0000_0100 - 0x0000_01FF)
//   PADDR[9:8] = 2'b10  ->  PSEL2  Slave 2 : TIMER (0x0000_0200 - 0x0000_02FF)
//   anything else       ->  no slave selected, PRDATA = 0x00000000

module APB_DECODER (output reg [31:0] PRDATA,         // Muxed read data back to master
                    output reg PSEL0,                 // Slave 0 select - GPIO  (gated)
                    output reg PSEL1,                 // Slave 1 select - UART  (gated)
                    output reg PSEL2,                 // Slave 2 select - TIMER (gated)
                    input  wire [31:0] PADDR,         // APB address from master
                    input  wire MASTER_PSEL,          // Master PSEL - gates all slave selects
                    input  wire [31:0] PRDATA0,       // Read data from Slave 0
                    input  wire [31:0] PRDATA1,       // Read data from Slave 1
                    input  wire [31:0] PRDATA2);      // Read data from Slave 2


    // --------------------------------------------------------
    // ADDRESS DECODE - PSEL generation (one-hot, gated)
    // PSELx is only asserted when MASTER_PSEL is high AND the
    // address falls within that slave's range.
    // --------------------------------------------------------
    always @(*) begin
        PSEL0 = 1'b0;
        PSEL1 = 1'b0;
        PSEL2 = 1'b0;
        if (MASTER_PSEL) begin
            case (PADDR[9:8])
                2'b00 : begin PSEL0 = 1'b1; end
                2'b01 : begin PSEL1 = 1'b1; end
                2'b10 : begin PSEL2 = 1'b1; end
                default : begin
                    PSEL0 = 1'b0;
                    PSEL1 = 1'b0;
                    PSEL2 = 1'b0;
                end
            endcase
        end
        else begin
            PSEL0 = 1'b0;
            PSEL1 = 1'b0;
            PSEL2 = 1'b0;
        end
    end

    // --------------------------------------------------------
    // PRDATA MUX - routes active slave's read data to master.
    // Uses PADDR[9:8] directly; MASTER_PSEL does not gate this
    // because PRDATA is a don't-care when bus is idle anyway.
    // --------------------------------------------------------
    always @(*) begin
        case (PADDR[9:8])
            2'b00 : begin PRDATA = PRDATA0; end
            2'b01 : begin PRDATA = PRDATA1; end
            2'b10 : begin PRDATA = PRDATA2; end
            default : begin PRDATA = 32'h0000_0000; end
        endcase
    end

endmodule