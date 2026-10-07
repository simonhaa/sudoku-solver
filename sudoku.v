`timescale 1ns/1ps
`default_nettype none

module sudoku
(
    input wire clk,                         // System clock
    input wire button_1,                    // Asynchronous reset, active-high (adjust if needed)
    input wire start,                       // Start signal
    input wire [81*4 - 1:0] puzzle,         // Puzzle grid: 9 x 9 grid, each digit is 4 bits
    output reg done,                        // Done signal
    output reg [81*4 - 1:0] solution        // Solution grid
);

    // Main FSM states
    parameter STATE_IDLE = 0;               // Waiting for start bit
    parameter STATE_LOAD = 1;               // Unpacks the puzzle --> grid, marks the givens
    parameter STATE_FIND_EMPTY = 2;         // Finds the next non-given cell to try
    parameter STATE_TRY_DIGIT = 3;          // Attempts next candidate digit
    parameter STATE_CHECK = 4;              // Validates the row/col/box
    parameter STATE_BACKTRACK = 5;          // Undo and retry previous cell
    parameter STATE_DONE = 6;               // Signals done once the whole grid is solved

    reg [2:0] state;
    reg [16:0] count; 
    // Internal grid storage

        // Unpacked grid with 81 elements (indices 0 to 80),
        // where each element is a 4-bit register holding a digit (0-9, 0 represents an empty cell)
    reg [3:0] grid [80:0];
        // grid[0-8] represents rows 1-9; grid[9-17] represents rows 10-18; and so on
        // 4'b0000 = 0, 4'b0001 = 1, ..., 4'b1001 = 9
    reg given [80:0];

    reg [6:0] emptyCell = 7'd0;             // Index of an empty cell
    reg [3:0] latestDigit = 4'd0;           // latest digit used in TRY_DIGIT state

    reg [1:0] check_state;
    reg [3:0] k;                            // Index that walks across the 9 cells in the row we check
    reg       conflict_found;               // Pulses high once a matching digit is found
    reg       check_start;                  // Main FSM pulses this to start the checking process
    reg       check_done;                   // Sub FSM pulses this once the checking process is completed
    reg       backtracking;                 // Main FSM pulses this to start the backtracking process

    // Sub FSM states for checker
    parameter CHECK_IDLE = 0;
    parameter CHECK_ROW = 1;
    parameter CHECK_COL = 2;
    parameter CHECK_BOX = 3;
    parameter CHECK_DONE = 4;

    // Empty Cell row, column, and box indexes
    wire [3:0] row, col, box_row_start, box_col_start;
    assign row = emptyCell / 9;
    assign col = emptyCell % 9;
    assign box_row_start = (row / 3) * 3;
    assign box_col_start = (col / 3) * 3;
    
    wire [6:0] box_cell_index;
    assign box_cell_index = (box_row_start + (k / 3)) * 9 + (box_col_start + (k % 3));

    integer i; // loop variable

    always @(posedge clk) begin
        if (button_1) begin
            state <= STATE_IDLE;
            check_state <= CHECK_IDLE;
            done <= 1'b0;
            backtracking <= 1'b0;
        end else begin
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

                // Find empty: checks every single cell if it is empty (equals 0)
                // If the cell is empty, assigns the index to emptyCell and moves onto the TRY_DIGIT state
                // If all cells are not empty and no conflicting candidates, move into DONE state
                // This state should ignore the givens in the puzzle, but be sure to incorporate the givens in the backtracking state
                STATE_FIND_EMPTY: begin
                    latestDigit <= 4'd1;
                    state <= STATE_DONE;                    // fix: Assumes done until loop says otherwise
                    for (i = 0; i < 81; i = i + 1) begin
                        if (grid[i] == 0) begin
                            emptyCell <= i;
                            state <= STATE_TRY_DIGIT;
                        end
                    end
                end

                // Try digit: puts in a candidate (1-9) and moves onto the CHECK state to see whether it is a valid candidate
                STATE_TRY_DIGIT: begin
                    if (latestDigit > 4'd9) begin
                        state <= STATE_BACKTRACK;
                    end else begin
                        if (backtracking) begin
                            if (grid[emptyCell] == 4'd9) begin
                                // If emptyCell is decremented (which it is once backtracking is high), and grid[emptyCell] == 9
                                // Decrement emptyCell again
                                state <= STATE_BACKTRACK;
                            end else if (!conflict_found) begin
                                backtracking <= 1'b0;
                            end else begin
                            grid[emptyCell] <= grid[emptyCell] + 1'b1;
                            check_start <= 1'b1;
                            state <= STATE_CHECK;
                            end
                        end
                        grid[emptyCell] <= latestDigit;
                        latestDigit <= latestDigit + 1'b1;
                        // fix: because everything updates in the next clock edge, this doesn't make 
                        // grid[emptyCell] = (latestDigit + 1) until the next clock edge
                        check_start <= 1'b1;                // Start signal for the checking sub FSM
                        state <= STATE_CHECK;
                    end
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

                // Backtrack: if the base case is reached (when emptyCell reaches 0), the board is invalid
                // Invalid board: moves to STATE_DONE and asserts done signal
                // Backtracking process: makes sure emptyCell (index) is not equal to a given (index)
                // If equal: emptyCell decrements again
                // If not equal: 
                STATE_BACKTRACK: begin
                    if (emptyCell == 7'd0) begin
                        state <= STATE_DONE; 
                    end else begin
                        grid[emptyCell] <= 4'd0;
                        emptyCell <= (emptyCell != given[emptyCell]) ? emptyCell - 1'b1 : emptyCell - 1'b1;
                        backtracking <= 1'b1;
                        state <= TRY_DIGIT;
                    end
                end

                // Done: signals done if board is either solved or board is invalid (which just signals done if its in this state lol)
                // Also displays "Board is Unsolvable" on the interface
                STATE_DONE: begin
                    solution <= puzzle;
                    done <= 1'b1;
                    state <= STATE_IDLE;
                end
            endcase
        end
    end

    // Checker sub-FSM block
    always @(posedge clk) begin
        if (button_1) begin
            check_state <= CHECK_IDLE;
            check_done <= 1'b0;
        end else begin
            case (check_state)
            CHECK_IDLE: begin
                if (check_start) begin
                    check_start <= 1'b1;
                    check_state <= CHECK_ROW
                end
            end

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
                    k <= 4'd0;
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
                if (box_cell_index != emptyCell && (grid[emptyCell] == grid[box_cell_index])) begin
                    conflict_found <= 1'b1;
                    check_done <= 1'b1;
                end else if (k == 8) begin
                    check_state <= CHECK_DONE;
                    k <= 4'd0;
                end else begin
                    k <= k + 1'b1;
                end
            end

            CHECK_DONE: begin
                check_state <= CHECK_ROW;
                k <= 4'd0;
                conflict_found <= 1'b0;
                check_done <= 1'b1;
            end
            endcase
        end
    end

endmodule