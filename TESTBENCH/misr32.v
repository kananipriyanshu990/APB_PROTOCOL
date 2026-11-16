module misr32 (input  wire clk,
   	       input  wire rst_n,
               input  wire en,
               input  wire [31:0] data_in,    // always 32-bit, pad upper bits with 0 if DUT output < 32 
               output wire [31:0] signature);

    reg [31:0] state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= 32'h0000_0000;
        else if (en)
            state <= {state[30:0], 1'b0}
                     ^ (state[31] ? 32'h8020_0003 : 32'h0)
                     ^ data_in;
    end

    assign signature = state;
endmodule