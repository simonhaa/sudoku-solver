`timescale 1ns/1ps
`default_nettype none

module sudoku
(
    input wire clk,                         // System clock
    input wire button_1,                    // Asynchronous reset, active-high (adjust if needed)
    input wire start,                       // Start signal
    input wire [81*4 - 1:0] puzzle,         // Puzzle grid: 9 x 9 grid, each digit is 4 bits
    output reg done,                        // Done signal
    output reg [81*4 - 1:0] solution,        // Solution grid
    output reg solved
);

    // Main FSM states
    parameter STATE_IDLE = 0;               // Waiting for start bit
    parameter STATE_LOAD = 1;               // Unpacks the puzzle --> grid, marks the givens
    parameter STATE_FIND_EMPTY = 2;         // Finds the next non-given cell to try
    parameter STATE_TRY_DIGIT = 3;          // Attempts next candidate digit
    parameter STATE_CHECK = 4;              // Validates the row/col/box
    parameter STATE_BACKTRACK = 5;          // Undo and retry previous cell
    parameter STATE_BACKTRACK_SKIP = 6;     // Skips over the givens when backtracking
    parameter STATE_DONE = 7;               // Signals done once the whole grid is solved

    // Sub FSM states for checker
    parameter CHECK_IDLE = 0;
    parameter CHECK_START = 1;
    parameter CHECK_DONE = 2;

    reg [2:0] state;
    reg [2:0] check_state;

    // Internal grid storage
    reg [3:0] grid [80:0];
    reg given [80:0];

    reg [6:0] cell = 7'd0;                  // Index of an empty cell
    reg [3:0] latestDigit = 4'd0;           // latest digit used in TRY_DIGIT state
    reg [3:0] k = 4'd0;                     // Index that walks across the 9 cells in the row we check
    
    reg       conflict_found;               // Pulses high once a matching digit is found
    reg       check_start;                  // Main FSM pulses this to start the checking process
    reg       check_done;                   // Sub FSM pulses this once the checking process is completed

    integer i; // loop variable; 32 bits wide

    always @(posedge clk or posedge button_1) begin
        if (button_1) begin
            state <= STATE_IDLE;
            done <= 1'b0;
            solved <= 1'b0;
            check_start <= 1'b0;
        end else begin
            case(state)
                // Idle: watches the line for the start bit
                STATE_IDLE: begin
                    done <= 1'b0;
                    state <= start ? STATE_LOAD : STATE_IDLE;
                end

                // Load: unpacks the 324-bit puzzle into grid and records which cells are givens
                STATE_LOAD: begin
                    for (i = 0; i < 81; i = i + 1) begin
                        grid[i] <= puzzle[i*4 +: 4];
                        given[i] <= (puzzle[i*4 +: 4] != 4'd0);
                    end
                    solved <= 1'b0;
                    state <= STATE_FIND_EMPTY;
                end

                // Find empty: checks every single cell if it is empty (equals 0)
                // If the cell is empty, assigns the index to cell and moves onto the TRY_DIGIT state
                // If all cells are not empty and no conflicting candidates, move into DONE state
                // Loop counts down such that the lowest empty index wins
                STATE_FIND_EMPTY: begin
                    latestDigit <= 4'd1;
                    solved      <= 1'b1;
                    state       <= STATE_DONE;
                    for (i = 80; i >= 0; i = i - 1) begin
                        if (grid[i] == 4'd0) begin
                            cell <= i[6:0];
                            solved <= 1'b0;
                            state <= STATE_TRY_DIGIT;
                        end
                    end
                end

                // Try digit: puts in a candidate (1-9) and moves onto the CHECK state to see whether it is a valid candidate
                STATE_TRY_DIGIT: begin
                    if (latestDigit > 4'd9) begin
                        state <= STATE_BACKTRACK;
                    end else begin
                        grid[cell] <= latestDigit;
                        latestDigit <= latestDigit + 1'b1;
                        // fix: because everything updates in the next clock edge, this doesn't make 
                        // grid[cell] = (latestDigit + 1) until the next clock edge
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

                // Backtrack: sets the current cell to 0 and decrements the cell's index
                // Easier to split the logic into two states
                // Skip handles the logic for both the givens and the candidate cells
                STATE_BACKTRACK: begin
                    grid[cell] <= 4'd0;
                    if (cell == 7'd0) begin
                        state <= STATE_DONE;            // puzzle is unsolvable
                    end else begin
                        cell <= cell - 1'b1;
                        state <= STATE_BACKTRACK_SKIP;
                    end
                end

                // Backtrack Skip: handles the backtracking logic for the givens and valid cells
                STATE_BACKTRACK_SKIP: begin
                    if (given[cell]) begin
                        if (cell == 7'd0)   state <= STATE_DONE;    // unsolvable because iterates past 0
                        else                cell <= cell - 1'b1;
                    end else begin
                        latestDigit <= grid[cell] + 1'b1;           // if it's 10, tries again
                        state <= STATE_TRY_DIGIT;
                    end
                end

                // Done: sets the solution equal to the grid once the board is solved
                STATE_DONE: begin
                    for (i = 0; i < 81; i = i + 1) begin
                        solution[i*4 +: 4] <= grid[i];
                    end
                    done <= 1'b1;
                    state <= STATE_IDLE;
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

    // Cell row, column, and box indexes
    wire [3:0] row, col, box_row_start, box_col_start;
    wire [6:0] box_cell_index;
    wire check_row, check_col, check_box;

    assign row = cell / 9;
    assign col = cell % 9;
    assign box_row_start = (row / 3) * 3;
    assign box_col_start = (col / 3) * 3;
    assign box_cell_index = (box_row_start + (k / 3)) * 9 + (box_col_start + (k % 3));

    assign check_row = (k != col && (grid[cell] == grid[row*9 + k]));
    assign check_col = (k != row && (grid[cell] == grid[col + k*9]));
    assign check_box = (box_cell_index != cell && (grid[cell] == grid[box_cell_index]));

    // Checker sub-FSM block
    always @(posedge clk or posedge button_1) begin
        if (button_1) begin
            check_state     <= CHECK_IDLE;
            check_done      <= 1'b0;
            k               <= 4'd0;
            conflict_found  <= 1'b0;
        end else begin
            case (check_state)
            CHECK_IDLE: begin
                check_done <= 1'b0;
                if (check_start) begin
                    k               <= 4'd0;
                    conflict_found  <= 1'b0;
                    check_state     <= CHECK_START;
                end
            end

            CHECK_START: begin
                if (check_row | check_col | check_box) begin
                    conflict_found <= 1'b1;
                    check_done <= 1'b1;
                    check_state <= CHECK_IDLE;
                end else if (k == 8) begin
                    check_state <= CHECK_DONE;
                    k <= 4'd0;
                end else begin
                    k <= k + 1'b1;
                end
            end

            CHECK_DONE: begin
                check_done <= 1'b1;
                check_state <= CHECK_IDLE;
            end

            default: begin 
                check_state     <= CHECK_IDLE;
                check_done      <= 1'b0;
                k               <= 4'd0;
                conflict_found  <= 1'b0;
            end
            endcase
        end
    end

endmodule