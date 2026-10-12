import random
import cocotb

from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge

PUZZLE = (
    "530070000" "600195000" "098000060"
    "800060003" "400803001" "700020006"
    "060000280" "000419005" "000080079"
)
SOLUTION = (
    "534678912" "672195348" "198342567"
    "859761423" "426853791" "713924856"
    "961537284" "287419635" "345286179"
)

# Helper functions
def to_digits(s):
    return [int(c) for c in s]

def pack(digits):
    # 81 digits --> 324 bit int. Cell i occupies bits [4*i +: 4]
    return sum(d << (4 * i) for i, d in enumerate(digits))

def unpack(val):
    return [(val >> (4 * i)) & 0xF for i in range(81)]

def is_valid_solution(sol, puzzle):
    """Complete, every row/col/box has 1-9 once, and givens are preserved."""
    if any(s not in range(1, 10) for s in sol):
        return False
    if any(p != 0 and p != s for p, s in zip(puzzle, sol)):
        return False
    full = set(range(1, 10))
    for r in range(9):
        if set(sol[r * 9:(r + 1) * 9]) != full:
            return False
    for c in range(9):
        if set(sol[c::9]) != full:
            return False
    for br in range(0, 9, 3):
        for bc in range(0, 9, 3):
            box = [sol[(br + dr) * 9 + bc + dc] for dr in range(3) for dc in range(3)]
            if set(box) != full:
                return False
    return True


async def reset(dut):
    dut.start.value = 0
    dut.puzzle.value = 0
    dut.button_1.value = 1
    await ClockCycles(dut.clk, 3)
    dut.button_1.value = 0
    await ClockCycles(dut.clk, 2)

async def setup(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

async def run_solver(dut, digits, max_cycles=1_000_000):
    """Pulse start for one cycle; return (solved, solution_digits, cycles)."""
    dut.puzzle.value = pack(digits)
    await FallingEdge(dut.clk)
    dut.start.value = 1
    await FallingEdge(dut.clk)
    dut.start.value = 0
    for n in range(max_cycles):
        await FallingEdge(dut.clk)
        if int(dut.done.value) == 1:
            return int(dut.solved.value), unpack(int(dut.solution.value)), n
    raise AssertionError(f"timeout: no done after {max_cycles} cycles")