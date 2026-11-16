// TAP POINTS: 32,22,2,1
// TAP POINTS IN HEX: 32'h8020_0003
// SEED: 3050_3050

module lfsr32 (input  wire clk,
  	       input  wire rst_n,
    	       input  wire en,
               output wire [31:0] out);
    reg [31:0] state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= 32'h3050_3050;        // any nonzero seed, this is memorable
        else if (en)
            state <= {state[30:0], 1'b0} ^ (state[31] ? 32'h8020_0003 : 32'h0);
    end

    assign out = state;
endmodule