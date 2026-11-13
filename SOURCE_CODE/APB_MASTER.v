// APB Master - 3-state FSM (IDLE -> SETUP -> ACCESS).
// Initiates APB transfers when TRANSFER is asserted.
// Supports both read and write transfers with PREADY-based wait states.
// DONE pulses high for one clock cycle when a transfer completes.
// On reads, RDATA_OUT captures PRDATA at the end of the ACCESS phase.
//
// State encoding:
//   IDLE   = 2'b00  Bus idle, no transfer in progress
//   SETUP  = 2'b01  PSEL asserted, PENABLE low, address/data driven
//   ACCESS = 2'b10  PENABLE asserted, waiting for PREADY from slave
module APB_MASTER (
    output reg [31:0] PADDR,       // APB address driven to decoder + slaves
    output reg [31:0] PWDATA,      // APB write data
    output reg PSEL,               // APB slave select (decoded by APB_DECODER)
    output reg PENABLE,            // APB enable - high in ACCESS phase only
    output reg PWRITE,             // Transfer direction: 1=Write 0=Read
    output reg [31:0] RDATA_OUT,   // Captured read data (valid when DONE=1)
    output reg DONE,               // Transfer complete pulse (1 clock cycle)
    input  wire [31:0] PRDATA,     // Read data from active slave (via decoder)
    input  wire PREADY,            // Slave ready - low inserts wait states
    input  wire [31:0] ADDR_IN,    // Address for next transfer
    input  wire [31:0] WDATA_IN,   // Write data for next transfer
    input  wire WRITE_IN,          // Direction for next transfer: 1=Write 0=Read
    input  wire TRANSFER,          // Pulse high for 1 cycle to start a transfer
    input  wire PCLK,              // APB clock
    input  wire PRESETn);          // Active-low asynchronous reset

    // --------------------------------------------------------
    // STATE ENCODING
    // --------------------------------------------------------
    localparam IDLE   = 2'b00;
    localparam SETUP  = 2'b01;
    localparam ACCESS = 2'b10;

    reg [1:0] STATE;
    reg [1:0] NEXT_STATE;

    // --------------------------------------------------------
    // STATE REGISTER - sequential
    // --------------------------------------------------------
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            STATE <= IDLE;
        end
        else begin
            STATE <= NEXT_STATE;
        end
    end

    // --------------------------------------------------------
    // NEXT STATE LOGIC - combinational
    // --------------------------------------------------------
    always @(*) begin
        case (STATE)
            IDLE : begin
                if (TRANSFER) begin
                    NEXT_STATE = SETUP;
                end
                else begin
                    NEXT_STATE = IDLE;
                end
            end
            SETUP : begin
                NEXT_STATE = ACCESS;
            end
            ACCESS : begin
                if (PREADY) begin
                    NEXT_STATE = IDLE;
                end
                else begin
                    NEXT_STATE = ACCESS;
                end
            end
            default : begin
                NEXT_STATE = IDLE;
            end
        endcase
    end

    // --------------------------------------------------------
    // OUTPUT LOGIC - sequential (registered outputs)
    // All APB outputs are registered to avoid glitches on bus.
    // --------------------------------------------------------
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            PADDR <= 32'h0000_0000;
            PWDATA <= 32'h0000_0000;
            PSEL <= 1'b0;
            PENABLE <= 1'b0;
            PWRITE <= 1'b0;
            RDATA_OUT <= 32'h0000_0000;
            DONE <= 1'b0;
        end
        else begin
            DONE <= 1'b0;   // Default: DONE is low every cycle
            case (STATE)

                IDLE : begin
                    PSEL <= 1'b0;
                    PENABLE <= 1'b0;
                    PWRITE <= 1'b0;
                    PADDR <= 32'h0000_0000;
                    PWDATA <= 32'h0000_0000;
                    if (TRANSFER) begin
                        // Latch transfer parameters on SETUP entry
                        PADDR <= ADDR_IN;
                        PWDATA <= WDATA_IN;
                        PWRITE <= WRITE_IN;
                        PSEL <= 1'b1;
                    end
                    else begin
                        PSEL <= 1'b0;
                    end
                end

                SETUP : begin
                    // PADDR, PWDATA, PWRITE already set from IDLE transition
                    // Raise PENABLE to enter ACCESS phase
                    PENABLE <= 1'b1;
                end

                ACCESS : begin
                    if (PREADY) begin
                        // Transfer complete
                        PSEL <= 1'b0;
                        PENABLE <= 1'b0;
                        PWRITE <= 1'b0;
                        DONE <= 1'b1;
                        // Capture read data if this was a read
                        if (!PWRITE) begin
                            RDATA_OUT <= PRDATA;
                        end
                        else begin
                            RDATA_OUT <= 32'h0000_0000;
                        end
                    end
                    else begin
                        // Wait state - hold all signals, slave not ready
                        PSEL <= 1'b1;
                        PENABLE <= 1'b1;
                    end
                end

                default : begin
                    PSEL <= 1'b0;
                    PENABLE <= 1'b0;
                    PWRITE <= 1'b0;
                    PADDR <= 32'h0000_0000;
                    PWDATA <= 32'h0000_0000;
                    DONE <= 1'b0;
                end

            endcase
        end
    end

endmodule