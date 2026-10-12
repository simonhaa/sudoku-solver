`timescale 1ns/1ps
`default_nettype none

module reset_sync (
    input wire clk,
    input wire async_rst,           // Async input, active-high
    output wire sync_rst            // Asserts async, deasserts sync, active-high
);

    reg [1:0] sync_ff;

    always @(posedge clk or posedge async_rst) begin
        if (async_rst)                      // asserts immediately when reset is high
            sync_ff <= 2'b11;
        else 
            sync_ff <= {sync_ff[0], 1'b0};
    end

    assign sync_rst = sync_ff[1];           // releases on clock edge for two cycles after button is released
endmodule

`default_nettype wire