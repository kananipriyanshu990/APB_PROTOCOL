// Single 32-bit APB-accessible register.
// Captures PWDATA on a valid APB write (PSEL & PENABLE & PWRITE active together).
// REG_DATA holds its value until the next write or reset.
// Resets to 0x00000000 on active-low async PRESETn.
module APB_SLAVE_REG (output reg  [31:0] REG_DATA,    // Current register value (read by parent slave)
                      input wire [31:0] PWDATA,      // APB write data
                      input wire PSEL,               // APB slave select (SETUP phase begins)
                      input wire PENABLE,            // APB enable (ACCESS phase - write commits here)
                      input wire PWRITE,             // Transfer direction: 1 = Write, 0 = Read
                      input wire PCLK,               // APB clock
                      input wire PRESETn);           // Active-low asynchronous reset


    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            REG_DATA <= 32'h0000_0000;
        end
        else begin
            if (PSEL && PENABLE && PWRITE) begin
                REG_DATA <= PWDATA;
            end
            else begin
                REG_DATA <= REG_DATA;
            end
        end
    end

endmodule