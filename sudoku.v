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
    parameter STATE_CHECK = 4;           // Validates the row/col/box
    parameter STATE_BACKTRACK = 5;          // Undo and retry previous cell
    parameter STATE_DONE = 6;               // Signals done once the whole grid is solved

    reg [2:0] state;
    reg [16:0] count; 
    // 115200 baud rate = 115200 bits per second --> max timer before reset is ~1 second (tentative)
    // each bit takes 868 clock cycles (because 100 MHz oscillator)
    
    // Internal grid storage

        // Unpacked grid with 81 elements (indices 0 to 80),
        // where each element is a 4-bit register holding a digit (0-9, 0 represents an empty cell)
    reg [3:0] grid [80:0];
        // grid[0-8] represents rows 1-9; grid[9-17] represents rows 10-18; and so on
        // 4'b0000 = 0, 4'b0001 = 1, ..., 4'b1001 = 9
    reg given[80:0];

    reg [6:0] emptyCell = 6'd0;             // Index of an empty cell
    reg [3:0] latestDigit = 4'd0;           // latest digit used in TRY_DIGIT state

    reg [1:0] check_state;
    reg [3:0] k;                            // Index that walks across the 9 cells in the row we check
    reg       conflict_found;               // Pulses high once a matching digit is found
    reg       check_start;                  // Main FSM pulses this to start the checking process
    reg       check_done;                   // Sub FSM pulses this once the checking process is completed

    // Sub states for checker
    parameter CHECK_ROW = 0;
    parameter CHECK_COL = 1;
    parameter CHECK_BOX = 2;
    parameter CHECK_DONE = 3;

    reg [3:0] row, cell, box;

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
                state <= start ? STATE_LOAD : STATE_IDLE;
            end

            // Load: unpacks the 324-bit puzzle into grid and records which cells are givens
            STATE_LOAD: begin
                checking <= 1'b1;
                for (i = 0; i < 81; i = i + 1) begin
                    grid[i] <= puzzle[i*4 +: 4];
                    given[i] <= (puzzle[i*4 +: 4] != 4'd0);
                end
                state <= STATE_FIND_EMPTY;
            end

            // Find empty: Checks every single cell if it is empty (equals 0)
            // If the cell is empty, assigns the index to emptyCell and moves onto the TRY_DIGIT state
            // If all cells are not empty and no conflicting candidates, move into DONE state
            STATE_FIND_EMPTY: begin
                latestDigit <= 4'd1;
                for (i = 0; i < 81; i = i + 1) begin
                    if (grid[i] == 0) begin
                        emptyCell <= i;
                        state <= STATE_TRY_DIGIT;
                    end
                    state <= done ? STATE_DONE : STATE_FIND_EMPTY;
                end
            end

            // Try digit: puts in a candidate (1-9) and moves onto the CHECK state to see whether it is a valid candidate
            STATE_TRY_DIGIT: begin
                grid[emptyCell] <= latestDigit;
                check_start <= 1'b1;                    // Start signal for the checking sub FSM
                state <= STATE_CHECK;
            end

            // Check: checks the cells in the same row/col/box if the candidate is valid
            // If it is valid, moves back into the FIND_EMPTY state to look for the next empty cell
            // If it is not valid, moves back into the TRY_DIGIT state and attempts the candidate + 1 value
            STATE_CHECK: begin
                check_start <= 1'b0;
                if (check_done) begin
                    state <= conflict_found ? STATE_TRY_DIGIT : STATE_FIND_EMPTY;
                end else begin
                    state <= STATE_CHECK;
                    // Stays in check until check_done is pulsed, then moves onto next state
                end
            end

            STATE_BACKTRACK: begin

            end

            STATE_DONE: begin

            end
        endcase
    end

    // Checker sub-FSM block
    always @(posedge clk) begin
        if (btn1) begin
            check_state <= CHECK_ROW; // not sure if this makes sense, check_state, by default (reset), is CHECK_ROW?
            check_done <= 1'b0;
        end else begin
            // emptyCell is saved when FSM gets to this state --> emptyCell returns the index of the grid
            // emptyCell = 20 = bottom right of top left box; row = 2; col = 2; box = 0
            row <= emptyCell / 9; // 2: Row 2
            col <= emptyCell % 9; // 2: Col 2
            box <= (row / 3) * 3 + (col / 3); // 0: Box 0

            case (check_state)
            CHECK_ROW: begin
                if (check_start) begin
                    k <= 4'd0;
                    conflict_found <= 1'b0;
                    check_done <= 1'b0;                 // pulses high after successful CHECK_BOX
                end

                // Comparison logic for row:
                if (k != col && (grid[emptyCell] == grid[row*9 + k])) begin
                    conflict_found <= 1'b1;
                    check_done <= 1'b1;
                end else if (k == 8) begin              // successfully iterated to the end of the row without any conflicts
                    check_state <= CHECK_COL;
                    check_start <= 1'b1;                // pulse start for next sub-check
                    k <= 4'd0;
                end else begin
                    k <= k + 1'b1;
                end
            end
                
            CHECK_COL: begin
                if (check_start) begin
                    k <= 4'd0;
                    conflict_found <= 1'b0;
                    check_done <= 1'b0;
                end

                // Comparison logic for col:
                if (k != row && (grid[emptyCell] == grid[col + k*9])) begin
                    conflict_found <= 1'b1;
                    check_done <= 1'b1;
                end else if (k == 8) begin
                    check_state <= CHECK_BOX;
                    check_start <= 1'b1;                // pulse start for next sub-check
                end else begin
                    k <= k + 1'b1;
                end
            end

            CHECK_BOX: begin
                if (check_start) begin
                    k <= 4'd0;
                    conflict_found <= 1'b0;
                    check_done <= 1'b0;
                end

                // Comparison logic for box:

            end
            endcase
        end
    end

endmodule