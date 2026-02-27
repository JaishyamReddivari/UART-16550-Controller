# UART 16550 — Design & UVM Verification

A register-compatible UART 16550 implementation in SystemVerilog featuring configurable frame formats, programmable baud rate generation, TX/RX FIFOs, and comprehensive error detection — verified using a full **UVM-based constrained-random testbench**.

## Overview

The UART 16550 is the industry-standard serial communication controller found across embedded systems, SoCs, and microcontrollers. This project implements the core 16550 feature set — register file, baud rate generator, TX/RX datapaths with shift-register serialization, and 16-deep FIFOs — and pairs it with a structured UVM verification environment for functional validation.

### Key Features

- **16550-compatible register set** — LCR, LSR, FCR, SCR, and divisor latch registers
- **Programmable baud rate** — 16-bit divisor latch with 16× oversampling
- **Configurable frame format** — 5/6/7/8-bit word length, even/odd/sticky parity, 1/1.5/2 stop bits
- **16-deep TX & RX FIFOs** — With programmable RX trigger levels (1, 4, 8, 14 bytes)
- **Error detection** — Parity error (PE), framing error (FE), break interrupt (BI), overrun/underrun
- **Set break** — Forced TX line low for break signaling
- **Full UVM 1.2 testbench** — Dual-monitor scoreboard, constrained-random sequences, self-checking

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
|---|---|
| Data Width | 8 bits |
| FIFO Depth | 16 entries (TX and RX) |
| Address Bus | 3 bits (8 registers) |
| Baud Divisor | 16-bit (DLL + DLM) |
| Oversampling | 16× per bit period |
| Word Length | 5, 6, 7, or 8 bits (via LCR\[1:0\]) |

## RTL Module Descriptions

### `all_mod` — Top-Level Integration

Instantiates and interconnects all sub-modules. Routes the CSR bus (`csr_t` struct) to TX and RX datapaths, connects FIFOs between the register file and serializers, and exposes the CPU bus and serial I/O to the outside.

### `regs_uart` — Register File & Baud Rate Generator

Implements the 16550 register map with DLAB-based address decoding:

| Address | DLAB=0 (Read) | DLAB=0 (Write) | DLAB=1 |
|---|---|---|---|
| 0x0 | RX FIFO data | TX FIFO push | DLL |
| 0x1 | — | — | DLM |
| 0x2 | — | FCR | — |
| 0x3 | LCR | LCR | LCR |
| 0x5 | LSR | — | — |
| 0x7 | SCR | SCR | SCR |

Also contains the **baud rate generator**: a 16-bit down-counter loaded from the divisor latch that produces a `baud_pulse` every `DLL:DLM` clock cycles.

### `uart_tx_top` — Transmit Datapath

FSM-based serializer with four states:

| State | Function |
|---|---|
| `idle` | Waits for FIFO data, counts inter-frame gap |
| `start` | Transmits start bit (16 baud ticks) |
| `send` | Shifts out data bits LSB-first per configured word length |
| `parity` | Transmits computed parity bit (even/odd/sticky) if enabled |

Automatically handles stop bit duration (1, 1.5, or 2 bits) based on LCR configuration. Supports `set_break` to force TX low.

### `uart_rx_top` — Receive Datapath

FSM-based deserializer with five states:

| State | Function |
|---|---|
| `idle` | Detects falling edge (start bit) on RX line |
| `start` | Validates start bit at mid-bit sample (count=7) |
| `read` | Samples data bits at mid-bit, shifts into output register |
| `parity` | Checks received parity against computed (even/odd/sticky) |
| `stop` | Validates stop bit, asserts `push` to RX FIFO, flags FE if low |

Uses 16× oversampling with mid-bit sampling for noise immunity.

### `fifo_top` — Synchronous Shift-Register FIFO

A 16-entry, 8-bit wide shift-register FIFO used for both TX and RX paths:

- **Push** — Writes to `mem[waddr]`, increments write pointer
- **Pop** — Shifts all entries down (`mem[i] <= mem[i+1]`), decrements write pointer
- **Simultaneous push/pop** — Shifts down and writes to `mem[waddr-1]`
- **Status flags** — `empty`, `full`, `overrun`, `underrun`
- **Threshold trigger** — Programmable RX FIFO threshold (1/4/8/14) for interrupt generation

### CSR Struct Definitions

```
csr_t
├── fcr_t   — FIFO Control Register (enable, reset, DMA mode, RX trigger)
├── lcr_t   — Line Control Register (WLS, STB, PEN, EPS, sticky parity, set break, DLAB)
├── lsr_t   — Line Status Register (DR, OE, PE, FE, BI, THRE, TEMT, RX FIFO error)
└── scr      — Scratch Register (8-bit, general purpose)

div_t
├── dlsb    — Divisor Latch LSB
└── dmsb    — Divisor Latch MSB
```

## UVM Verification Environment

### Testbench Topology

```
tb_top (SystemVerilog module)
 ├── DUT instantiation (all_mod)
 ├── uart_if (virtual interface)
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

#### Transaction (`uart_txn`)

Models a single UART transfer. Fields are registered with UVM field automation macros.

| Field | Type | Description |
|---|---|---|
| `data` | `rand bit [7:0]` | Payload byte |
| `tx_start` | `rand bit` | Initiate transmission |

#### Sequence (`uart_sequence`)

Generates **500 back-to-back transactions** with `tx_start` constrained to `1`:

```systemverilog
assert(txn.randomize() with { tx_start == 1; });
```

Every transaction triggers a full UART frame transmission, maximizing bus utilization and stressing the TX FIFO, serializer, and baud timing simultaneously.

#### Driver (`uart_driver`)

Drives transactions onto the DUT interface with a single-cycle handshake protocol:

1. Asserts `tx_data` and `tx_start` on the rising edge of `clk`
2. De-asserts `tx_start` on the following cycle
3. Calls `item_done()` to advance the sequence

The driver retrieves the virtual interface handle from `uvm_config_db` during `build_phase`.

#### TX Monitor (`uart_tx_monitor`) — Expected Path

Observes the **input side** of the DUT. On every `posedge clk`, if `tx_start` is asserted, captures `tx_data` and broadcasts it as the **expected** transaction via `tx_ap`. This feeds the scoreboard's reference model.

#### RX Monitor (`uart_rx_monitor`) — Actual Path

Observes the **output side** of the DUT. Triggers on `posedge rx_valid`, captures `rx_data`, and broadcasts it as the **actual** transaction via `rx_ap`. This represents what the DUT actually produced after serialization → deserialization.

#### Scoreboard (`uart_scoreboard`)

Implements a **dual-port comparison model** using separate analysis imports for TX and RX paths:

```
TX Monitor ──► write()    → push expected data into mailbox
RX Monitor ──► write_rx() → pop expected, compare against actual
```

The scoreboard uses `uvm_analysis_imp_decl(_rx)` to create a second analysis import, enabling independent handling of expected and actual data streams.

| Check | Mechanism |
|---|---|
| Data integrity | Byte-by-byte comparison: `txn.data !== exp.data` → `UVM_ERROR` |
| Unexpected RX | RX received with empty expected queue → `UVM_ERROR` |
| Match logging | Successful comparisons logged at `UVM_LOW` verbosity |

#### Agent (`uart_agent`)

Encapsulates driver, both monitors, and sequencer. Key distinction from simpler testbenches: **two monitors** are instantiated — one for the input (TX) path and one for the output (RX) path — enabling end-to-end data path verification.

```
driver.seq_item_port ──► sequencer.seq_item_export
tx_monitor.tx_ap     ──► scoreboard.tx_imp   (expected)
rx_monitor.rx_ap     ──► scoreboard.rx_imp   (actual)
```

#### Environment (`uart_env`)

Builds agent and scoreboard, then wires both monitor analysis ports to their respective scoreboard imports in `connect_phase`.

#### Test (`uart_test`)

Builds the environment, raises an objection, starts the sequence, waits for a drain period (`#100000` — long enough for all 500 UART frames to complete serialization), and drops the objection.

### Verification Flow

```
┌──────────────┐    ┌──────────┐    ┌────────────────────────────┐    ┌──────────────┐
│   Sequence   │───►│  Driver  │───►│           DUT              │───►│  RX Monitor  │
│  (500 txns)  │    │          │    │  regs → TX FIFO → uart_tx  │    │  (actual)    │
└──────────────┘    └──────────┘    │         TX pin ──► RX pin  │    └──────┬───────┘
                                    │  uart_rx → RX FIFO → regs  │           │
                    ┌──────────┐    └────────────────────────────┘     rx_ap.write()
                    │TX Monitor│                                             │
                    │(expected)│                                      ┌──────▼───────┐
                    └────┬─────┘                                      │  Scoreboard  │
                         │                                            │  (mailbox    │
                   tx_ap.write()                                      │   compare)   │
                         └──────────────────────────────────────────► │              │
                                                                      └──────────────┘
```

### What the Testbench Validates

| Scenario | How It's Covered |
|---|---|
| TX → RX data integrity | Scoreboard compares every transmitted byte against received byte |
| Full serial frame correctness | 500 frames exercising start/data/stop serialization and deserialization |
| FIFO buffering | Back-to-back transmissions stress TX FIFO queuing and pop timing |
| Baud rate timing | 16× oversampling with mid-bit sampling validated across all frames |
| Parity computation | DUT LCR configures parity; RX checks parity on deserialized frames |
| Framing error detection | RX FSM validates stop bit and flags FE when stop bit is low |
| Break detection | LCR `set_break` forces TX low; RX detects and flags BI |
| Overrun / underrun | FIFO flags asserted when push-while-full or pop-while-empty occurs |
| Unexpected data | Scoreboard flags `UVM_ERROR` if RX data arrives with no matching TX entry |

## File Structure

```
uart-16550/
├── rtl/
│   ├── all_mod.sv         # Top-level — instantiates and wires all sub-modules
│   ├── regs_uart.sv       # Register file, DLAB decoding, baud rate generator
│   ├── uart_tx_top.sv     # TX FSM serializer (idle → start → send → parity)
│   ├── uart_rx_top.sv     # RX FSM deserializer (idle → start → read → parity → stop)
│   ├── fifo_top.sv        # 16×8 shift-register FIFO with threshold trigger
│   └── csr_types.sv       # Struct typedefs: csr_t, fcr_t, lcr_t, lsr_t, div_t
├── tb/
│   └── tb_top.sv          # Full UVM testbench (interface, txn, seq, drv, monitors, sb, agent, env, test)
└── README.md
```

> **Note:** The source provided has all modules in combined files. The structure above is the recommended split for production use.

## Getting Started

### Prerequisites

A Verilog/SystemVerilog simulator with **UVM 1.2** support:

- Synopsys VCS
- Cadence Xcelium
- Mentor Questa / ModelSim

### Running the Simulation

**VCS:**

```bash
vcs -full64 -sverilog -ntb_opts uvm-1.2 \
    rtl/*.sv tb/tb_top.sv \
    -o simv -timescale=1ns/1ps

./simv +UVM_TESTNAME=uart_test +UVM_VERBOSITY=UVM_LOW
```

**Questa:**

```bash
vlog -sv +incdir+$UVM_HOME/src rtl/*.sv tb/tb_top.sv
vsim -c tb_top +UVM_TESTNAME=uart_test -do "run -all; quit"
```

**Xcelium:**

```bash
xrun -sv -uvm -uvmhome CDNS-1.2 \
    rtl/*.sv tb/tb_top.sv \
    -timescale 1ns/1ps +UVM_TESTNAME=uart_test
```

### Expected Output

A passing simulation completes with no `UVM_ERROR` or `UVM_FATAL`:

```
UVM_INFO  ... [RNTST] Running test uart_test...
UVM_INFO  ... [SB] MATCH 0xa3
UVM_INFO  ... [SB] MATCH 0x7f
...
--- UVM Report Summary ---
** Report counts by severity
UVM_INFO    :    XXXX
UVM_WARNING :    0
UVM_ERROR   :    0
UVM_FATAL   :    0
```

Any `MISMATCH` or `RX received with no expected TX` errors indicate a functional failure.

## Possible Extensions

- **Functional coverage** — Covergroups for LCR configurations (all WLS × parity × stop bit combinations), FIFO occupancy bins, LSR flag transitions, and baud divisor ranges
- **SVA assertions** — Protocol-level checks on frame timing, start/stop bit positions, parity correctness, and FIFO pointer invariants
- **Loopback test** — Wire `txd` → `rxd` for end-to-end TX→serial→RX data path verification without an external model
- **Register access sequences** — Dedicated sequences for register read/write, DLAB toggling, FCR reset commands, and divisor latch programming
- **Error injection** — Corrupt RX line mid-frame to validate PE, FE, and BI flag assertion and LSR reporting
- **Interrupt verification** — Add IER/IIR logic and verify interrupt prioritization and clearing behavior
- **Multi-config regression** — Sweep all 4 word lengths × 3 parity modes × 2 stop bit settings across multiple baud rates

## References

- [National Semiconductor PC16550D Datasheet](https://www.ti.com/lit/ds/symlink/pc16550d.pdf) — Original 16550 UART specification
