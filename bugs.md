### RTL Bugs

| # | Module | Bug | Fix |
|---|--------|-----|-----|
| 1 | `all_mod` | `rx_out`, `rx_fifo_out`, `tx_rst`, `rx_rst`, `rx_fifo_threshold` used but never declared | Added `wire` declarations |
| 2 | `all_mod` | `rx_fifo_empty_i` port left floating (unconnected) | Connected to RX FIFO `empty` output |
| 3 | `all_mod` | `rx_oe` port left floating (unconnected) | Connected to RX FIFO `overrun` output |
| 4 | `all_mod` | `thre` hardcoded to `1'b0` — TX runs regardless of FIFO state | Driven by `tx_fifo_empty` signal |
| 5 | `all_mod` | TX/RX FIFO `rst` not connected to FCR software reset bits | Changed to `rst \| tx_rst` and `rst \| rx_rst` |
| 6 | `fifo_top` | `empty_t` resets to `1'b0` — FIFO starts "not empty" | Reset to `1'b1` (FIFO starts empty) |
| 7 | `fifo_top` | Shift loop `i < 14` skips entry 14→15 copy | Changed to `i < 15` |
| 8 | `fifo_top` | `waddr` was 4 bits — can't distinguish 16 (full) from 0 (empty) | Widened to 5 bits |
| 9 | `regs_uart` | Divisor latch used `div_t` packed struct with two `always` blocks — NBA race condition clobbers writes | Replaced with separate `reg [7:0] dl_lsb, dl_msb` in a single `always` block |
| 10 | `regs_uart` | Divisor latch had no reset | Added reset for `dl_lsb` and `dl_msb` |
| 11 | `regs_uart` | Baud pulse condition `\|divisor & ~\|baud_cnt` fires when counter IS zero but reload also happens that cycle, causing ambiguity | Changed to `(\|divisor) & (baud_cnt == 16'h1)` — pulse when counter is about to reach zero |
| 12 | `uart_rx_top` | `fall_edge` was `assign fall_edge = rx_reg` (level, not edge) | Replaced with latched `start_detected` flag set on `rx_d1 & ~rx`, cleared when FSM leaves IDLE |
| 13 | `uart_rx_top` | `bitcnt` declared 3-bit but assigned `8'h00` (width mismatch) | Changed to `3'd0` |
| 14 | `uart_rx_top` | Parity checked against last data bit in `READ` state instead of actual parity bit | Moved check to `PARITY` state; accumulated data parity with `parity_accum` during `READ` |
| 15 | `uart_rx_top` | Break detection missing | Added `bi <= ~rx & ~\|dout` in `STOP` state |
| 16 | `uart_tx_top` | `pop` stayed high between baud pulses (multi-cycle pulse) causing double FIFO pops | Added `pop <= 1'b0` as default at top of non-reset block |
| 17 | `uart_tx_top` | `sreg_empty` reset to `1'b0` (shift register starts "not empty") | Reset to `1'b1` |

### Testbench Bugs

| # | Component | Bug | Fix |
|---|-----------|-----|-----|
| 18 | `tb_top` | DUT instantiated with non-existent ports (`tx_data`, `tx_start`, `txd`, `rxd`, `rx_data`, `rx_valid`) | Rewired to actual ports: `wr`, `rd`, `addr`, `din`, `dout`, `tx`, `rx` |
| 19 | `uart_if` | Interface signals don't match DUT | Redesigned with `wr`, `rd`, `addr[2:0]`, `din[7:0]`, `dout[7:0]`, `tx`, `rx` |
| 20 | `tb_top` | No TX→RX loopback — `rx` was floating | Added `assign vif.rx = vif.tx` |
| 21 | `tb_top` | No register configuration — baud rate, LCR, FCR never programmed | Sequence now writes LCR→DLL→DLM→LCR→FCR before sending data |
| 22 | `uart_env` | Missing constructor (`new` function) | Added `function new(string name, uvm_component parent)` |
| 23 | `uart_sequence` | Used `uart_reg_txn` before it was declared (forward reference) | Moved `uart_reg_txn` class definition before `uart_sequence` |
| 24 | `uart_scoreboard` | `exp_q.put()` — blocking task called from `function void write()` | Changed to `void'(exp_q.try_put())` |
| 25 | `uart_driver` | Driver started writing config registers before reset deasserted at 100ns — all config writes ignored | Added `@(negedge vif.rst)` + settling delay before first transaction |
| 26 | `uart_driver` | Single-cycle `tx_start` protocol doesn't match DUT's register bus interface | Rewrote to perform `wr`/`addr`/`din` register bus writes with `$cast` to `uart_reg_txn` |
| 27 | `uart_driver` | 500 writes at full speed overflow 16-deep FIFO — data silently lost | Added `FRAME_WAIT` pacing delay after each TX FIFO write |
| 28 | `uart_rx_monitor` | Triggered on non-existent `rx_valid` signal | Rewrote to deserialize UART frames directly from serial `rx` line |
| 29 | `uart_rx_monitor` | Bit timing assumed 16 clocks/bit regardless of divisor | Parameterized with `BIT_CLKS = 16 × (DLL+1)` |
| 30 | `uart_tx_monitor` | Captured DLL config writes (addr=0 during DLAB=1) as TX data | Added `config_done` flag triggered by FCR write |

### RAL Bugs

| # | Component | Bug | Fix |
|---|-----------|-----|-----|
| 31 | `uart_ral_test` | `UVM_FATAL [INVTST]` — test class not found by factory at `run_test()` | RAL files were compiled as separate files but never imported into the `tb_top` compilation unit. Added `uart_ral_includes.sv` with correct dependency-ordered `include` and `import` statements, placed before `tb_top` in the testbench file |
| 32 | `uart_driver` | All register read-backs returned `0x00` — driver asserted `rd` but never sampled `vif.dout` | Created `uart_ral_driver` (extends `uart_driver`) that waits 2 clock cycles after `rd` assertion to account for the RTL's temp-register pipeline (`lcr_temp`, `lsr_temp`, `scr_temp`), then captures `vif.dout` with a `#1` delta delay for NBA settlement. Integrated via factory override in `uart_ral_env` |
| 33 | `uart_reg_adapter` | `bus2reg` always returned `txn.wdata` regardless of read/write — RAL mirror never received actual read data | Added read/write distinction: writes return `txn.wdata`, reads return `txn.data` (populated by the driver from `vif.dout`) |

---
