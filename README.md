# UART 16550 — Design & UVM Verification with Register Abstraction Layer

A register-compatible UART 16550 implementation in SystemVerilog featuring configurable frame formats, programmable baud rate generation, TX/RX FIFOs, and comprehensive error detection — verified using a full **UVM-based constrained-random testbench** with TX→RX loopback and a **UVM Register Abstraction Layer (RAL)** model with dual address maps for DLAB aliasing.

## Overview

The UART 16550 is the industry-standard serial communication controller found across embedded systems, SoCs, and microcontrollers. This project implements the core 16550 feature set — register file, baud rate generator, TX/RX datapaths with shift-register serialization, and 16-deep FIFOs — and pairs it with a structured UVM verification environment for functional validation.

The verification environment includes two independent testbenches: a **data-path testbench** that validates end-to-end TX→RX integrity through constrained-random stimulus, and a **RAL testbench** that validates register-level correctness through a dual-address-map register model handling DLAB-based address aliasing.

### Key Features

* **16550-compatible register set** — LCR, LSR, FCR, SCR, and divisor latch registers
* **Programmable baud rate** — 16-bit divisor latch with 16× oversampling
* **Configurable frame format** — 5/6/7/8-bit word length, even/odd/sticky parity, 1/1.5/2 stop bits
* **16-deep TX & RX FIFOs** — With programmable RX trigger levels (1, 4, 8, 14 bytes)
* **Error detection** — Parity error (PE), framing error (FE), break interrupt (BI), overrun/underrun
* **Set break** — Forced TX line low for break signaling
* **Full UVM 1.2 testbench** — Dual-monitor scoreboard, constrained-random sequences, self-checking with TX→RX serial loopback
* **UVM RAL model** — Dual address maps for DLAB aliasing, register adapter, bus predictor, and RAL-aware driver with read-back verification

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

This project contains two independent UVM testbenches sharing a common agent infrastructure:

1. **`uart_test`** — Data-path verification with constrained-random TX→RX loopback (500 frames)
2. **`uart_ral_test`** — Register-level verification using the UVM Register Abstraction Layer

Both tests are selectable at runtime via `+UVM_TESTNAME` without recompilation.

### Testbench Topology

#### Data-Path Testbench (`uart_test`)

```
tb_top
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

#### RAL Testbench (`uart_ral_test`)

```
tb_top
 └── uart_ral_test
      └── uart_ral_env
           ├── uart_agent (active)
           │    ├── uart_sequencer ─── uart_ral_sequence
           │    ├── uart_ral_driver (factory override of uart_driver)
           │    ├── uart_tx_monitor ──── tx_ap
           │    └── uart_rx_monitor ──── rx_ap
           ├── uart_scoreboard
           │    ├── tx_imp ◄── tx_ap
           │    └── rx_imp ◄── rx_ap
           ├── uart_reg_block (dual address maps)
           │    ├── map_dlab0 (THR, RBR, FCR, LCR, LSR, SCR)
           │    └── map_dlab1 (DLL, DLM, FCR, LCR, LSR, SCR)
           ├── uart_reg_adapter (reg2bus / bus2reg)
           ├── uart_reg_monitor ──► reg_predictor
           └── uvm_reg_predictor (auto-updates RAL mirror)
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

## UVM Register Abstraction Layer (RAL)

### Why RAL

The data-path testbench validates TX→RX integrity but treats register access as raw `addr/data/wr` transactions. The RAL adds structured register-level verification: are registers at the correct addresses, do they hold correct reset values, does DLAB aliasing route to the right physical registers, and do read-back values match what was written.

### Dual Address Map Architecture

The UART 16550's DLAB (Divisor Latch Access Bit) creates an address aliasing problem: addresses 0x0 and 0x1 map to different physical registers depending on `LCR[7]`. The RAL model solves this with two `uvm_reg_map` instances inside a single `uvm_reg_block`:

```
uart_reg_block
├── map_dlab0 (normal operation — DLAB=0)
│    ├── 0x0 → THR (write-only) / RBR (read-only)
│    ├── 0x2 → FCR (write-only)
│    ├── 0x3 → LCR (read-write)
│    ├── 0x5 → LSR (read-only, volatile)
│    └── 0x7 → SCR (read-write)
│
├── map_dlab1 (divisor latch access — DLAB=1)
│    ├── 0x0 → DLL (read-write)
│    ├── 0x1 → DLM (read-write)
│    ├── 0x2 → FCR (write-only)
│    ├── 0x3 → LCR (read-write)
│    ├── 0x5 → LSR (read-only, volatile)
│    └── 0x7 → SCR (read-write)
│
└── get_active_map() → returns correct map based on LCR.DLAB mirror
```

Shared registers (LCR, LSR, SCR, FCR) appear in both maps so they remain accessible regardless of the DLAB state. The sequence selects the active map at runtime:

```systemverilog
// DLAB=1: access divisor latches through map_dlab1
reg_block.LCR.write(status, 8'h83, .map(reg_block.map_dlab0));  // set DLAB=1
reg_block.DLL.write(status, 8'h0A, .map(reg_block.map_dlab1));  // divisor LSB
reg_block.DLM.write(status, 8'h00, .map(reg_block.map_dlab1));  // divisor MSB

// DLAB=0: normal operation through map_dlab0
reg_block.LCR.write(status, 8'h03, .map(reg_block.map_dlab1));  // clear DLAB
reg_block.THR.write(status, 8'hA5, .map(reg_block.map_dlab0));  // transmit data
```

### RAL Register Definitions

| Register | Class | Fields | Access | Volatile | Reset |
| --- | --- | --- | --- | --- | --- |
| RBR | `uart_reg_rbr` | `data[7:0]` | RO | Yes | 0x00 |
| THR | `uart_reg_thr` | `data[7:0]` | WO | No | 0x00 |
| DLL | `uart_reg_dll` | `data[7:0]` | RW | No | 0x00 |
| DLM | `uart_reg_dlm` | `data[7:0]` | RW | No | 0x00 |
| FCR | `uart_reg_fcr` | `ena`, `rx_rst`, `tx_rst`, `dma_mode`, `reserved[1:0]`, `rx_trigger[1:0]` | WO | No | 0x00 |
| LCR | `uart_reg_lcr` | `wls[1:0]`, `stb`, `pen`, `eps`, `sticky_parity`, `set_break`, `dlab` | RW | No | 0x00 |
| LSR | `uart_reg_lsr` | `dr`, `oe`, `pe`, `fe`, `bi`, `thre`, `temt`, `rx_fifo_error` | RO | Yes | 0x60 |
| SCR | `uart_reg_scr` | `data[7:0]` | RW | No | 0x00 |

### RAL Component Descriptions

#### Register Adapter (`uart_reg_adapter`)

Converts between UVM RAL bus operations and the physical `uart_reg_txn` transaction format:

* **`reg2bus`** — Translates `uvm_reg_bus_op` (addr, data, kind) into `uart_reg_txn` (addr, wdata, wr, rd) for the driver
* **`bus2reg`** — Translates observed transactions back into RAL format for the predictor. Distinguishes reads from writes: reads return `txn.data` (captured from `vif.dout`), writes return `txn.wdata`

#### Register Bus Monitor (`uart_reg_monitor`)

Observes every register read/write on the bus interface and broadcasts `uart_reg_txn` items to the RAL predictor. Unlike `uart_tx_monitor` (which only captures THR writes), this monitor captures all register activity so the RAL mirror stays synchronized with hardware.

#### RAL-Aware Driver (`uart_ral_driver`)

Extends `uart_driver` with proper read-back support. The RTL uses a two-stage pipeline for certain registers (LCR, LSR, SCR are latched into temp registers before appearing on `dout_o`), so the driver waits 2 clock cycles after asserting `rd` before sampling `vif.dout`:

```
Cycle N   : assert addr + rd
Cycle N+1 : deassert rd (RTL latches temp register)
Cycle N+2 : sample vif.dout (#1 delta delay for NBA settlement)
```

Integrated via UVM factory override (`uart_driver` → `uart_ral_driver`) so the original `uart_test` remains untouched.

#### RAL Predictor (`uvm_reg_predictor`)

Auto-updates the RAL mirror from observed bus transactions. Connected to `uart_reg_monitor.ap` so every register write updates the mirror, and every register read is checked against the mirror's expected value.

### RAL Test Sequence (`uart_ral_sequence`)

The RAL sequence exercises all register access paths:

| Phase | Operations | What It Validates |
| --- | --- | --- |
| 1. Baud config | LCR write (DLAB=1), DLL/DLM write via `map_dlab1`, DLL read-back | DLAB aliasing routes address 0x0 to DLL, not THR |
| 2. Normal mode | LCR write (DLAB=0), LCR read-back via `map_dlab0`, FCR write | Map switching, LCR read-back correctness |
| 3. SCR test | SCR write 0xA5, SCR read-back | Simple RW register round-trip |
| 4. LSR read | LSR read via `map_dlab0` | Volatile read-only register, verifies reset state (0x60: thre=1, temt=1) |
| 5. TX data | 10 THR writes via `map_dlab0` | Data-path through RAL, scoreboard still validates TX→RX |

### RAL Environment (`uart_ral_env`)

Extends the base environment with RAL infrastructure while preserving the original scoreboard:

```
uart_ral_env
├── uart_agent          ← reused (driver factory-overridden)
├── uart_scoreboard     ← reused (still validates TX→RX)
├── uart_reg_block      ← NEW: register model with dual maps
├── uart_reg_adapter    ← NEW: reg2bus / bus2reg conversion
├── uart_reg_monitor    ← NEW: observes all register activity
└── uvm_reg_predictor   ← NEW: auto-updates RAL mirror
```

Both address maps are connected to the same sequencer and adapter. The register block is published via `uvm_config_db` so sequences can retrieve it at runtime.

## Verification Flow

### Data-Path Flow (`uart_test`)

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

### RAL Flow (`uart_ral_test`)

```
┌──────────────┐    ┌──────────────┐    ┌───────────────┐    ┌─────────────┐
│  RAL         │───►│  RAL Driver  │───►│     DUT       │    │  Reg Monitor│
│  Sequence    │    │  (captures   │    │  (register    │    │  (observes  │
│  (dual-map   │    │   dout on    │    │   file +      │    │   all r/w)  │
│   reg ops)   │    │   reads)     │    │   datapaths)  │    └─────┬───────┘
└──────────────┘    └──────────────┘    └───────────────┘          │
                                                               bus_in.write()
       ┌──────────────────┐                                        │
       │  uart_reg_block  │◄───────────────────────────────────────┘
       │  ┌─────────────┐ │         uvm_reg_predictor
       │  │  map_dlab0  │ │         (auto-updates mirror
       │  │  map_dlab1  │ │          from observed txns)
       │  └─────────────┘ │
       │  RAL Mirror      │  ← write values stored, read values compared
       └──────────────────┘
```

## What the Testbenches Validate

### Data-Path Test (`uart_test`)

| Scenario | How It's Covered |
| --- | --- |
| TX → RX data integrity | Scoreboard compares every transmitted byte against received byte (500 frames, 0 mismatches) |
| Full serial frame correctness | 500 constrained-random frames exercising start/data/stop serialization and deserialization |
| FIFO buffering | Paced writes exercise TX FIFO queuing and pop timing |
| Baud rate timing | 16× oversampling with mid-bit sampling validated across all frames |
| Register configuration | Sequence programs LCR, DLL, DLM, FCR in correct order with DLAB toggling |
| Unexpected data | Scoreboard flags `UVM_ERROR` if RX data arrives with no matching TX entry |

### RAL Test (`uart_ral_test`)

| Scenario | How It's Covered |
| --- | --- |
| DLAB address aliasing | DLL write/read-back via `map_dlab1` at address 0x0 (same address as THR in `map_dlab0`) |
| Register read-back | LCR, DLL, SCR written then read back — values compared against expected |
| Volatile status registers | LSR read verifies reset state (0x60: thre=1, temt=1) |
| RW register integrity | SCR write 0xA5 / read-back 0xA5 round-trip |
| Write-only registers | FCR write (no read-back — addr 0x2 reads return 0x00 in hardware) |
| RAL mirror consistency | Predictor auto-checks that every observed read matches the mirror's expected value |
| Data-path through RAL | 10 THR writes via `map_dlab0` validated end-to-end by the scoreboard (10/10 matches) |

> **Note:** The following RTL features are structurally implemented but require additional test sequences to exercise: parity computation (PEN/EPS/sticky), framing error detection (FE), break interrupt (BI), overrun/underrun flags, and multi-configuration regression across word lengths, parity modes, and stop bit settings. These are listed under Possible Extensions.

## File Structure

```
UART-16550-Controller/
├── design/
│   ├── all_mod.sv           # Combined: typedefs + top-level + all sub-modules
│   ├── fifo_top.sv          # 16×8 shift-register FIFO with threshold trigger
│   ├── regs_uart.sv         # Register file, DLAB decoding, baud rate generator
│   ├── uart_tx_top.sv       # TX FSM serializer
│   └── uart_rx_top.sv       # RX FSM deserializer
├── verification/
│   ├── all_mod_tb.sv        # Base UVM testbench (interface, txn, seq, drv, monitors, sb, agent, env, test, tb_top)
│   ├── uart_ral_pkg.sv      # RAL register model (8 registers, dual address maps)
│   ├── uart_reg_adapter.sv  # RAL adapter (reg2bus / bus2reg)
│   ├── uart_reg_monitor.sv  # Register bus monitor (feeds predictor)
│   ├── uart_ral_driver.sv   # RAL-aware driver (captures dout on reads)
│   ├── uart_ral_env.sv      # RAL environment (reg_block + adapter + predictor)
│   ├── uart_ral_sequence.sv # RAL test sequence (dual-map register access)
│   ├── uart_ral_test.sv     # RAL test (selectable via +UVM_TESTNAME)
│   └── uart_ral_includes.sv # Include file (compilation order for RAL files)
├── bugs.md
└── README.md
```

> **Note:** `all_mod.sv` is the self-contained compilation unit — it includes all struct typedefs and all modules. The standalone `.sv` files in `design/` contain the same individual modules for reference. When compiling, use **either** `all_mod.sv` alone **or** the individual files — not both, to avoid duplicate module definitions.

## Getting Started

### Prerequisites

A Verilog/SystemVerilog simulator with **UVM 1.2** support:

* Synopsys VCS
* Cadence Xcelium
* Mentor Questa / ModelSim

### Running the Data-Path Test

**VCS:**

```bash
vcs -full64 -sverilog -ntb_opts uvm-1.2 \
    design/all_mod.sv verification/all_mod_tb.sv \
    -o simv -timescale=1ns/1ps

./simv +UVM_TESTNAME=uart_test +UVM_VERBOSITY=UVM_LOW
```

**Questa:**

```bash
vlog -sv +incdir+$UVM_HOME/src design/all_mod.sv verification/all_mod_tb.sv
vsim -c tb_top +UVM_TESTNAME=uart_test -do "run -all; quit"
```

**Xcelium:**

```bash
xrun -sv -uvm -uvmhome CDNS-1.2 \
    design/all_mod.sv verification/all_mod_tb.sv \
    -timescale 1ns/1ps +UVM_TESTNAME=uart_test
```

### Running the RAL Test

The RAL files are pulled in via `uart_ral_includes.sv` which is included in `all_mod_tb.sv`. Use the same compile commands, just change the test name:

**VCS:**

```bash
./simv +UVM_TESTNAME=uart_ral_test +UVM_VERBOSITY=UVM_LOW
```

**Questa:**

```bash
vlog -sv +incdir+$UVM_HOME/src +incdir+verification/ \
    design/all_mod.sv verification/all_mod_tb.sv
vsim -c tb_top +UVM_TESTNAME=uart_ral_test -do "run -all; quit"
```

**Xcelium:**

```bash
xrun -sv -uvm -uvmhome CDNS-1.2 +incdir+verification/ \
    design/all_mod.sv verification/all_mod_tb.sv \
    -timescale 1ns/1ps +UVM_TESTNAME=uart_ral_test
```

### Expected Output — Data-Path Test

```
UVM_INFO  ... [RNTST] Running test uart_test...
UVM_INFO  ... [SCO] MATCH 0xa5
UVM_INFO  ... [SCO] MATCH 0x3c
...
UVM_INFO  ... [SCO] ========== Matches: 500  Mismatches: 0 ==========
UVM_INFO  ... [TEST] All frames transmitted — drain complete
--- UVM Report Summary ---
  UVM_ERROR   :    0
  UVM_FATAL   :    0
```

### Expected Output — RAL Test

```
UVM_INFO  ... [RNTST] Running test uart_ral_test...
UVM_INFO  ... [RAL_SEQ] === Starting RAL-based UART configuration ===
UVM_INFO  ... [RAL_SEQ] Setting DLAB=1 for baud rate configuration
UVM_INFO  ... [RAL_SEQ] Writing DLL=0x0A, DLM=0x00 via map_dlab1
UVM_INFO  ... [RAL_SEQ] DLL read-back OK: 0xa
UVM_INFO  ... [RAL_SEQ] Clearing DLAB, switching to map_dlab0
UVM_INFO  ... [RAL_SEQ] LCR read-back OK: 0x3
UVM_INFO  ... [RAL_SEQ] SCR read-back OK: 0xa5
UVM_INFO  ... [RAL_SEQ] LSR = 0x60 (thre=1 temt=1 dr=0)
UVM_INFO  ... [RAL_SEQ] Transmitting 10 bytes via THR (RAL writes)
UVM_INFO  ... [SCO] ========== Matches: 10  Mismatches: 0 ==========
UVM_INFO  ... [RAL_TEST] Drain complete — dropping objection
--- UVM Report Summary ---
  UVM_ERROR   :    0
  UVM_FATAL   :    0
```

## Possible Extensions

* **Functional coverage** — Covergroups for LCR configurations (all WLS × parity × stop bit combinations), FIFO occupancy bins, LSR flag transitions, and baud divisor ranges
* **SVA assertions** — Protocol-level checks on frame timing, start/stop bit positions, parity correctness, and FIFO pointer invariants
* **Parity verification** — Enable PEN/EPS in LCR and add scoreboard checks for parity bit correctness and PE flag assertion on corrupted frames
* **Error injection** — Corrupt RX line mid-frame to validate PE, FE, and BI flag assertion and LSR reporting
* **Built-in RAL sequences** — `uvm_reg_hw_reset_seq` for automated reset value checking and `uvm_reg_bit_bash_seq` for walking-1/walking-0 field testing
* **RAL functional coverage** — Covergroups on register access patterns, DLAB transitions, and field-level value ranges
* **Multi-config regression** — Sweep all 4 word lengths × 3 parity modes × 2 stop bit settings across multiple baud rates
* **Interrupt verification** — Add IER/IIR logic and verify interrupt prioritization and clearing behavior
* **FIFO stress testing** — Back-to-back writes without pacing to exercise overrun flag assertion and recovery

## References

* [National Semiconductor PC16550D Datasheet](https://www.ti.com/lit/ds/symlink/pc16550d.pdf) — Original 16550 UART specification
