# UART UVM Verification Project

## Overview
This project implements a complete UVM-based verification environment for a UART controller
with FIFO buffering and register interface.

## Design Under Test
- UART Transmitter
- UART Receiver
- FIFO Buffer
- UART Register Block

## Verification Environment
- UVM agent with driver, monitor, and sequencer
- Transaction-level stimulus generation
- Self-checking scoreboard
- Multiple directed and constrained-random tests

## Test Scenarios
- Smoke test for basic TX/RX
- FIFO full and empty conditions
- Back-to-back UART transactions
- Error injection tests

## Tools
- SystemVerilog
- UVM
- Questa / ModelSim
- Xilinx Vivado
