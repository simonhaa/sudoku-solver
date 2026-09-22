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

    // Element that tells the solver whether the cell came pre-filled or not (digits 1-9)
    reg given[80:0];

    reg [6:0] emptyCell = 6'd0;             // 
    reg [3:0] latestDigit = 4'd0;           // latest digit used in TRY_DIGIT state

    reg [1:0] check_state;
    reg [3:0] k;
    reg       conflict_found;
    reg       check_start;                  // main FSM pulses this to start the check process
    reg       check_done;                   // check pulses this when finished

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

            // Find empty: Checks if grid[i] == 0, moves onto possible candidate state
            // If all cells are not empty, check if done is signaled --> puzzle is solved
            STATE_FIND_EMPTY: begin
                latestDigit <= 4'd0;
                for (i = 0; i < 81; i = i + 1) begin
                    if (grid[i] == 0) begin
                        emptyCell = i;
                        state <= STATE_TRY_DIGIT;
                    end
                    state <= done ? STATE_DONE : STATE_FIND_EMPTY;
                end
            end
            // possible register to save the last "try_digit" and use that for the next candidate attempt to save time? (uses up resources)


            // Try digit: puts in a digit (1-9) and moves onto the checking state to see whether it is a valid attempt
            // if not valid, moves onto the next digit
            STATE_TRY_DIGIT: begin
                grid[emptyCell] <= latestDigit;
                check_start <= 1'b1;                    // Start signal for the checking sub FSM
                state <= STATE_CHECK;
            end

            // Checking: checks the cells in the same row/col/box if the candidate is valid
            // If it is valid, moves back into the FIND_EMPTY state to look for the next empty cell
            // If not valid, moves back into the TRY_DIGIT state and attempts the candidate + 1 value
            STATE_CHECK: begin
                check_start <= 1'b0;
                if (check_done) begin
                    state <= conflict_found ? STATE_TRY_DIGIT : STATE_FIND_EMPTY;
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
            check_state <= CHECK_ROW;
        end
    end

endmodule