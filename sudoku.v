`default_nettype none

module sudoku 
#(
    parameter DELAY_FRAMES = 868
    // However many clock cycles that make up one bit period
    // 100 MHz / 115200 Baud Rate = ~868
)

(
    input wire clk,                         // System clock
    input wire btn1,                        // Asynchronous reset, active-high (adjust if needed)
    input wire start,                       // Start signal
    input wire [81*4 - 1:0] puzzle,         // Puzzle grid: 9 x 9 grid, each digit is 4 bits
    output reg checking,                    // Checking signal
    output reg done,                        // Done signal
    output reg [81*4 - 1:0] solution        // Solution grid
);

    // States
    parameter STATE_IDLE = 0;               // Waiting for start bit
    parameter STATE_LOAD = 1;               // Unpacks the puzzle --> grid, marks the givens
    parameter STATE_FIND_EMPTY = 2;         // Finds the next non-given cell to try
    parameter STATE_TRY_DIGIT = 3;          // Attempts next candidate digit
    parameter STATE_CHECKING = 4;           // Validates the row/col/box
    parameter STATE_BACKTRACK = 5;          // Undo and retry previous cell
    parameter STATE_DONE = 6;               // Signals done once the whole grid is solved

    reg [2:0] state;
    
    // Internal grid storage

    // Unpacked grid with 81 elements (indices 0 to 80),
    // where each element is a 4-bit register holding a digit (0-9)
    reg [3:0] grid [80:0];

    // Element that tells the solver whether the cell came pre-filled or not
    reg       given[80:0]; 

    integer i; // loop variable

    always @(posedge clk) begin
        if (btn1) begin
            state <= STATE_IDLE;
            checking <= 1'b0;
            done <= 1'b0;
        end

        case(state)

            // Idle: watches the line for the start bit
            STATE_IDLE: begin
                checking <= 1'b0;
                done <= 1'b0;
                state <= start ? STATE_LOAD ; STATE_IDLE;
            end

            // Load: unpacks the 324-bit puzzle into grid and records which cells are givens
            STATE_LOAD: begin
                checking <= 1'b1;
                for (i = 0; i < 81; i = i + 1) begin
                    grid[i] = <= puzzle[i*4 +: 4];
                end
            end
        endcase
    end

endmodule