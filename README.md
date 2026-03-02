# UART 16550 — Design & UVM Verification

A register-compatible UART 16550 implementation in SystemVerilog featuring configurable frame formats, programmable baud rate generation, TX/RX FIFOs, and comprehensive error detection — verified using a full **UVM-based constrained-random testbench** with TX→RX loopback.

## Overview

The UART 16550 is the industry-standard serial communication controller found across embedded systems, SoCs, and microcontrollers. This project implements the core 16550 feature set — register file, baud rate generator, TX/RX datapaths with shift-register serialization, and 16-deep FIFOs — and pairs it with a structured UVM verification environment for functional validation.

### Key Features

* **16550-compatible register set** — LCR, LSR, FCR, SCR, and divisor latch registers
* **Programmable baud rate** — 16-bit divisor latch with 16× oversampling
* **Configurable frame format** — 5/6/7/8-bit word length, even/odd/sticky parity, 1/1.5/2 stop bits
* **16-deep TX & RX FIFOs** — With programmable RX trigger levels (1, 4, 8, 14 bytes)
* **Error detection** — Parity error (PE), framing error (FE), break interrupt (BI), overrun/underrun
* **Set break** — Forced TX line low for break signaling
* **Full UVM 1.2 testbench** — Dual-monitor scoreboard, constrained-random sequences, self-checking with TX→RX serial loopback

## Architecture

### Block Diagram

```
                          ┌──────────────────────────────────┐
                          │           all_mod (Top)          │
    ┌─────────────┐       │                                  │
    │  CPU / Bus  │◄─────►│  regs_uart                       │
    │  Interface  │ addr  │  ┌────────────────────────┐      │
    │             │ din   │  │ Register File          │      │
    │             │ dout  │  │  • LCR (frame config)  │      │
    │             │ wr/rd │  │  • FCR (FIFO control)  │      │
    │             │       │  │  • LSR (line status)   │      │
    └─────────────┘       │  │  • SCR (scratch)       │      │
                          │  │  • DLL/DLM (baud div)  │      │
                          │  └────────┬───────────────┘      │
                          │           │ csr bus              │
                          │     ┌─────┴─────┐                │
                          │     ▼           ▼                │
                          │  ┌────────┐  ┌────────┐          │
                          │  │TX FIFO │  │RX FIFO │          │
                          │  │ (16×8) │  │ (16×8) │          │
                          │  └───┬────┘  └────▲───┘          │
                          │      ▼            │              │
                          │  ┌────────┐  ┌────────┐          │
                          │  │uart_tx │  │uart_rx │          │     ┌──────────┐
                          │  │ _top   │  │ _top   │          │     │  Serial  │
                          │  │        ├──►  TX pin├──────────┼────►│  Device  │
                          │  │        │  │        ◄──────────┼─────┤          │
                          │  └────────┘  └────────┘  RX pin  │     └──────────┘
                          └──────────────────────────────────┘
```

### Design Parameters

| Parameter | Value |
| --- | --- |
| Data Width | 8 bits |
| FIFO Depth | 16 entries (TX and RX) |
| Address Bus | 3 bits (8 registers) |
| Baud Divisor | 16-bit (DLL + DLM) |
| Oversampling | 16× per bit period |
| Word Length | 5, 6, 7, or 8 bits (via LCR\[1:0\]) |

## RTL Module Descriptions

### `all_mod` — Top-Level Integration

Instantiates and interconnects all sub-modules. Routes the CSR bus (`csr_t` struct) to TX and RX datapaths, connects FIFOs between the register file and serializers, and exposes the CPU bus and serial I/O to the outside. The TX FIFO `empty` signal drives the transmitter's `thre` input so the TX FSM only starts when data is available. Both FIFO reset inputs are OR'd with the corresponding FCR software-reset bits (`rst | tx_rst` and `rst | rx_rst`).

### `regs_uart` — Register File & Baud Rate Generator

Implements the 16550 register map with DLAB-based address decoding:

| Address | DLAB=0 (Read) | DLAB=0 (Write) | DLAB=1 |
| --- | --- | --- | --- |
| 0x0 | RX FIFO data | TX FIFO push | DLL |
| 0x1 | — | — | DLM |
| 0x2 | — | FCR | FCR |
| 0x3 | LCR | LCR | LCR |
| 0x5 | LSR | — | — |
| 0x7 | SCR | SCR | SCR |

Also contains the **baud rate generator**: a 16-bit down-counter loaded from the divisor latch (`{dl_msb, dl_lsb}`) that produces a `baud_pulse` when the counter reaches 1. The divisor latch is implemented as two independent `reg [7:0]` variables (`dl_lsb`, `dl_msb`) written from a single `always` block to avoid packed-struct NBA race conditions.

### `uart_tx_top` — Transmit Datapath

FSM-based serializer with four states:

| State | Function |
| --- | --- |
| `IDLE` | Waits for FIFO data (`thre=0`), counts inter-frame gap |
| `START` | Transmits start bit (16 baud ticks) |
| `SEND` | Shifts out data bits LSB-first per configured word length |
| `PARITY` | Transmits computed parity bit (even/odd/sticky) if enabled |

Automatically handles stop bit duration (1, 1.5, or 2 bits) based on LCR configuration. Supports `set_break` to force TX low. The `pop` signal is a single-cycle pulse (default-cleared every clock, overridden to 1 only on the IDLE→START transition) to ensure exactly one FIFO pop per frame.

### `uart_rx_top` — Receive Datapath

FSM-based deserializer with five states:

| State | Function |
| --- | --- |
| `IDLE` | Detects falling edge on RX line via latched `start_detected` flag |
| `START` | Validates start bit at mid-bit sample (count=8) |
| `READ` | Samples data bits at mid-bit, shifts into output register, accumulates parity |
| `PARITY` | Compares received parity bit against accumulated data parity (even/odd/sticky) |
| `STOP` | Validates stop bit, asserts `push` to RX FIFO, flags FE if low, flags BI if all-zero break |

Uses 16× oversampling with mid-bit sampling for noise immunity. Start-bit detection uses a latched edge detector (`start_detected` is set on any `rx_d1 & ~rx` falling edge and held until the FSM leaves IDLE) so that start bits are never missed between baud pulses.

### `fifo_top` — Synchronous Shift-Register FIFO

A 16-entry, 8-bit wide shift-register FIFO used for both TX and RX paths:

* **Push** — Writes to `mem[waddr]`, increments write pointer
* **Pop** — Shifts all entries down (`mem[i] <= mem[i+1]` for i=0..14), decrements write pointer
* **Simultaneous push/pop** — Shifts down and writes to `mem[waddr-1]`
* **Status flags** — `empty` (resets to 1), `full`, `overrun`, `underrun`
* **Write pointer** — 5-bit `waddr` to distinguish full (16) from empty (0)
* **Threshold trigger** — Programmable RX FIFO threshold (1/4/8/14) for interrupt generation

### CSR Struct Definitions

All struct typedefs (`fcr_t`, `lcr_t`, `lsr_t`, `csr_t`) are defined at the top of `all_mod.sv`. The `csr_t` struct is unpacked to allow its fields to be driven from separate `always` blocks without NBA race conditions.

```
csr_t (unpacked)
├── fcr_t   — FIFO Control Register (enable, reset, DMA mode, RX trigger)
├── lcr_t   — Line Control Register (WLS, STB, PEN, EPS, sticky parity, set break, DLAB)
├── lsr_t   — Line Status Register (DR, OE, PE, FE, BI, THRE, TEMT, RX FIFO error)
└── scr      — Scratch Register (8-bit, general purpose)

Divisor Latch (separate registers)
├── dl_lsb  — Divisor Latch LSB (reg [7:0])
└── dl_msb  — Divisor Latch MSB (reg [7:0])
```

## UVM Verification Environment

### Testbench Topology

```
tb_top (SystemVerilog module)
 ├── DUT instantiation (all_mod)
 ├── TX→RX loopback (assign vif.rx = vif.tx)
 ├── uart_if (virtual interface: wr, rd, addr, din, dout, tx, rx)
 └── UVM Test
      └── uart_test
           └── uart_env
                ├── uart_agent (active)
                │    ├── uart_sequencer ─── uart_sequence
                │    ├── uart_driver
                │    ├── uart_tx_monitor ──── tx_ap (expected data)
                │    └── uart_rx_monitor ──── rx_ap (actual data)
                └── uart_scoreboard
                     ├── tx_imp ◄── tx_ap  (expected)
                     └── rx_imp ◄── rx_ap  (actual)
```

### Component Breakdown

#### Transaction (`uart_txn` / `uart_reg_txn`)

`uart_txn` is the base transaction with `data` and `tx_start` fields. `uart_reg_txn` extends it with register bus fields:

| Field | Type | Description |
| --- | --- | --- |
| `data` | `rand bit [7:0]` | Payload byte (base class) |
| `tx_start` | `rand bit` | Legacy start flag (base class) |
| `addr` | `rand bit [2:0]` | Register address (extended) |
| `wdata` | `rand bit [7:0]` | Write data (extended) |
| `wr` | `rand bit` | Write enable (extended) |
| `rd` | `rand bit` | Read enable (extended) |

#### Sequence (`uart_sequence`)

Performs two phases:

1. **Configuration** — Programs the UART registers in order: LCR (DLAB=1, 8N1) → DLL → DLM → LCR (DLAB=0) → FCR (FIFO enable). Uses the `write_reg()` helper task.
2. **Data transmission** — Generates **500 constrained-random transactions** with `addr == 0, wr == 1`, each pushing a random byte into the TX FIFO.

#### Driver (`uart_driver`)

Drives transactions onto the DUT's register bus interface using `$cast` to distinguish `uart_reg_txn` from base `uart_txn`:

1. **Waits for reset deassertion** (`@(negedge vif.rst)` + settling delay) before driving any transactions
2. Asserts `addr`, `din`, and `wr` on the rising edge of `clk`
3. De-asserts `wr` on the following cycle
4. **Paces data writes** — After each TX FIFO write (`addr=0`), waits `FRAME_WAIT` clock cycles (≈1 full frame duration) to prevent FIFO overflow
5. Calls `item_done()` to advance the sequence

#### TX Monitor (`uart_tx_monitor`) — Expected Path

Observes the **register bus input side** of the DUT. Waits for a `config_done` flag (set when it sees a write to FCR at `addr=2`), then captures `din` on every `posedge clk` where `wr=1` and `addr=0`. Broadcasts captured data as the **expected** transaction via `tx_ap`.

#### RX Monitor (`uart_rx_monitor`) — Actual Path

Deserializes complete UART frames directly from the serial `rx` line using bit-period timing:

1. Waits for falling edge on `rx` (start bit)
2. Moves to mid-start-bit (half bit period), validates `rx` is still low
3. Samples 8 data bits LSB-first at mid-bit points
4. Skips the stop bit
5. Broadcasts the deserialized byte via `rx_ap`

Timing is parameterized: `BIT_CLKS = 16 × (DLL + 1)`, `HALF_BIT = BIT_CLKS / 2`.

#### Scoreboard (`uart_scoreboard`)

Implements a **dual-port comparison model** using separate analysis imports for TX and RX paths:

```
TX Monitor ──► write()    → try_put expected data into mailbox
RX Monitor ──► write_rx() → try_get expected, compare against actual
```

The scoreboard uses `uvm_analysis_imp_decl(_rx)` to create a second analysis import. The `write` function uses `try_put` (non-blocking) instead of `put` since analysis port callbacks must be functions, not tasks.

| Check | Mechanism |
| --- | --- |
| Data integrity | Byte-by-byte comparison: `txn.data !== exp.data` → `UVM_ERROR` |
| Unexpected RX | RX received with empty expected queue → `UVM_ERROR` |
| Match logging | Successful comparisons logged at `UVM_LOW` verbosity |
| Final report | `report_phase` prints match/mismatch totals and warns about unmatched TX items |

#### Agent (`uart_agent`)

Encapsulates driver, both monitors, and sequencer. Two monitors are instantiated — one for the input (TX) path and one for the output (RX) path — enabling end-to-end data path verification.

```
driver.seq_item_port ──► sequencer.seq_item_export
tx_monitor.tx_ap     ──► scoreboard.tx_imp   (expected)
rx_monitor.rx_ap     ──► scoreboard.rx_imp   (actual)
```

#### Environment (`uart_env`)

Builds agent and scoreboard, then wires both monitor analysis ports to their respective scoreboard imports in `connect_phase`.

#### Test (`uart_test`)

Builds the environment, raises an objection, starts the sequence, waits for a drain period (`#10_000_000` — long enough for all 500 paced UART frames to complete serialization and loopback), and drops the objection.

### Verification Flow

```
┌──────────────┐    ┌──────────┐    ┌────────────────────────────┐    ┌──────────────┐
│   Sequence   │───►│  Driver  │───►│           DUT              │───►│  RX Monitor  │
│  (config +   │    │ (reg bus │    │  regs → TX FIFO → uart_tx  │    │ (deserialize │
│   500 txns)  │    │  writes) │    │         TX pin ──► RX pin  │    │  from serial)│
└──────────────┘    └──────────┘    │  uart_rx → RX FIFO → regs  │    └──────┬───────┘
                                    └────────────────────────────┘           │
                    ┌──────────┐           loopback wire              rx_ap.write()
                    │TX Monitor│                                             │
                    │(captures │                                      ┌──────▼───────┐
                    │ bus din) │                                      │  Scoreboard  │
                    └────┬─────┘                                      │  (mailbox    │
                         │                                            │   compare)   │
                   tx_ap.write()                                      │              │
                         └──────────────────────────────────────────► │              │
                                                                      └──────────────┘
```

### What the Testbench Validates

| Scenario | How It's Covered |
| --- | --- |
| TX → RX data integrity | Scoreboard compares every transmitted byte against received byte (500 frames, 0 mismatches) |
| Full serial frame correctness | 500 constrained-random frames exercising start/data/stop serialization and deserialization |
| FIFO buffering | Paced writes exercise TX FIFO queuing and pop timing |
| Baud rate timing | 16× oversampling with mid-bit sampling validated across all frames |
| Register configuration | Sequence programs LCR, DLL, DLM, FCR in correct order with DLAB toggling |
| Unexpected data | Scoreboard flags `UVM_ERROR` if RX data arrives with no matching TX entry |

> **Note:** The following RTL features are structurally implemented but require additional test sequences to exercise: parity computation (PEN/EPS/sticky), framing error detection (FE), break interrupt (BI), overrun/underrun flags, and multi-configuration regression across word lengths, parity modes, and stop bit settings. These are listed under Possible Extensions.

## File Structure

```
UART-16550-Controller/
├── all_mod.sv         # Combined file: typedefs + top-level + all sub-modules
├── all_mod_tb.sv      # Full UVM testbench (interface, txn, seq, drv, monitors, sb, agent, env, test, tb_top)
├── regs_uart.sv       # Register file, DLAB decoding, baud rate generator (standalone)
├── uart_tx_top.sv     # TX FSM serializer (standalone)
├── uart_rx_top.sv     # RX FSM deserializer (standalone)
├── fifo_top.sv        # 16×8 shift-register FIFO with threshold trigger (standalone)
├── bugs.md            # List of bugs found and fixed during verification
└── README.md
```

> **Note:** `all_mod.sv` is the self-contained compilation unit — it includes all struct typedefs and all modules (`all_mod`, `fifo_top`, `regs_uart`, `uart_tx_top`, `uart_rx_top`). The standalone `.sv` files contain the same individual modules for reference. When compiling, use **either** `all_mod.sv` alone **or** the individual files — not both, to avoid duplicate module definitions.

## Getting Started

### Prerequisites

A Verilog/SystemVerilog simulator with **UVM 1.2** support:

* Synopsys VCS
* Cadence Xcelium
* Mentor Questa / ModelSim

### Running the Simulation

**VCS:**

```bash
vcs -full64 -sverilog -ntb_opts uvm-1.2 \
    all_mod.sv all_mod_tb.sv \
    -o simv -timescale=1ns/1ps

./simv +UVM_TESTNAME=uart_test +UVM_VERBOSITY=UVM_LOW
```

**Questa:**

```bash
vlog -sv +incdir+$UVM_HOME/src all_mod.sv all_mod_tb.sv
vsim -c tb_top +UVM_TESTNAME=uart_test -do "run -all; quit"
```

**Xcelium:**

```bash
xrun -sv -uvm -uvmhome CDNS-1.2 \
    all_mod.sv all_mod_tb.sv \
    -timescale 1ns/1ps +UVM_TESTNAME=uart_test
```

### Expected Output

A passing simulation completes with no `UVM_ERROR` or `UVM_FATAL`:

```
UVM_INFO  ... [RNTST] Running test uart_test...
UVM_INFO  ... [SB] MATCH 0xa5
UVM_INFO  ... [SB] MATCH 0x3c
...
UVM_INFO  ... [SB] ========== Matches: 500  Mismatches: 0 ==========
UVM_INFO  ... [TEST] All frames transmitted — drain complete

--- UVM Report Summary ---
** Report counts by severity
UVM_INFO    :    XXXX
UVM_WARNING :    0
UVM_ERROR   :    0
UVM_FATAL   :    0
```

Any `MISMATCH` or `RX received with no matching TX` errors indicate a functional failure.

## Possible Extensions

* **Functional coverage** — Covergroups for LCR configurations (all WLS × parity × stop bit combinations), FIFO occupancy bins, LSR flag transitions, and baud divisor ranges
* **SVA assertions** — Protocol-level checks on frame timing, start/stop bit positions, parity correctness, and FIFO pointer invariants
* **Parity verification** — Enable PEN/EPS in LCR and add scoreboard checks for parity bit correctness and PE flag assertion on corrupted frames
* **Error injection** — Corrupt RX line mid-frame to validate PE, FE, and BI flag assertion and LSR reporting
* **Register access sequences** — Dedicated sequences for register read/write, DLAB toggling, FCR reset commands, and divisor latch programming with readback verification
* **Multi-config regression** — Sweep all 4 word lengths × 3 parity modes × 2 stop bit settings across multiple baud rates
* **Interrupt verification** — Add IER/IIR logic and verify interrupt prioritization and clearing behavior
* **FIFO stress testing** — Back-to-back writes without pacing to exercise overrun flag assertion and recovery

## References

* [National Semiconductor PC16550D Datasheet](https://www.ti.com/lit/ds/symlink/pc16550d.pdf) — Original 16550 UART specification
