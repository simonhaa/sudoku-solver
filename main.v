module main (
    input clk,                          // System clock
    input rst,                          // Resets board (maybe make manual reset button?)
    input start,                        // Start signal
    input [81*4 - 1:0] puzzle,          // puzzle grid: 9 x 9 grid, each digit is 4 bits
    output done,                        // done signal
    output [81*4 - 1:0] solution        // solution grid
);

    parameter STATE_IDLE = 0;           // Waiting for start bit
    parameter STATE_START_BIT = 1;      // Signals start
    parameter STATE_CHECKING = 2;       // Checks rows and columns of the digit to make sure its valid
    parameter STATE_VALID = 3;          // Signals valid
    parameter STATE_DONE = 4;           // Signals done once the whole grid is solved

    reg [2:0] state;


endmodule