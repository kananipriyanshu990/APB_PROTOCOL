# APB Protocol — RTL Implementation & Verification

## Overview

This project implements the **AMBA APB (Advanced Peripheral Bus)** protocol from scratch in Verilog, with a fully modular, bottom-up design and a layered verification strategy. It is part of a three-protocol AMBA learning series (APB → AHB → AXI), built to develop both RTL design and verification skills in a hands-on, industry-aligned way.

The system consists of one APB master, an address decoder, and three peripheral slaves — a GPIO register bank, a UART register bank, and a TIMER register bank — wired together in a single top-level structural module. Each peripheral slave contains four 32-bit readable and writable registers. The design is fully synchronous to a 100 MHz clock with active-low asynchronous reset throughout.

Verification is two-tier. Each RTL module has its own plain SystemVerilog unit testbench for focused, signal-level inspection in Vivado. The top-level system is verified by a structural testbench that uses an LFSR to generate pseudo-random stimulus and a MISR to compress all read-back data into a single deterministic signature for regression comparison.

**Tools:** Xilinx Vivado (simulation and waveform analysis) **Language:** Verilog RTL + SystemVerilog testbenches **Target:** Functional simulation only (no synthesis constraints)

## APB Protocol — Theory

### Why APB Exists

AMBA (Advanced Microcontroller Bus Architecture) defines a family of on-chip buses. High-speed blocks — CPU core, DMA, DDR controller — connect on a fast bus (AXI or AHB). Slow peripherals — GPIO, UART, timers, I2C — do not need that bandwidth and would waste power and logic running at full speed. APB solves this by sitting behind a bridge on the slow side of the system, purpose-built for low-power, low-complexity register access.

```
CPU ── AXI/AHB (fast) ── APB Bridge ── APB (slow) ── peripherals
```

### Signal Dictionary

| Signal | Direction | Description |
| --- | --- | --- |
| PCLK | — | Bus clock. All transfers synchronous to rising edge. |
| PRESETn | — | Active-low async reset. Resets the entire bus. |
| PADDR \[31:0\] | M → S | Address bus. Selects the target register. |
| PSEL | M → S | Slave select. Asserted for both SETUP and ACCESS phases. |
| PENABLE | M → S | Enable. Marks the ACCESS phase only. |
| PWRITE | M → S | Direction. 1 = Write, 0 = Read. |
| PWDATA \[31:0\] | M → S | Write data from master to slave. |
| PRDATA \[31:0\] | S → M | Read data from slave to master. |
| PREADY | S → M | Slave ready. Low inserts wait states. |

### Two-Phase Transfer

Every APB transaction — read or write — takes exactly two clock cycles when PREADY is high (no wait states).

**SETUP phase (cycle 1):** Master drives PADDR, PWDATA, PWRITE. Asserts PSEL. PENABLE is LOW.

**ACCESS phase (cycle 2):** Master raises PENABLE. On a write, the slave latches PWDATA on the rising clock edge where PSEL & PENABLE & PWRITE are all high. On a read, the slave drives PRDATA and the master samples it at the end of this cycle.

### Wait States

A slave holds PREADY low to stretch the ACCESS phase across as many cycles as it needs. The master holds all signals stable. When PREADY goes high the transfer completes normally. This design ties PREADY permanently high — zero wait states throughout.

### Address Decoding

One master talks to three slaves by address range. The decoder inspects PADDR\[9:8\] to assert the correct slave select:

| PADDR\[9:8\] | Slave | Base Address |
| --- | --- | --- |
| 2'b00 | GPIO (Slave 0) | 0x0000\_0000 |
| 2'b01 | UART (Slave 1) | 0x0000\_0100 |
| 2'b10 | TIMER (Slave 2) | 0x0000\_0200 |

Within each slave, PADDR\[3:2\] selects one of four 32-bit registers at word-aligned offsets 0x00, 0x04, 0x08, 0x0C.

## RTL Module Descriptions

### APB\_SLAVE\_REG.v — Single 32-bit Register

The atom of the design. A single 32-bit register that captures PWDATA on a valid APB write and holds its value until the next write or reset. Write condition: `PSEL & PENABLE & PWRITE` all high simultaneously on the rising clock edge. This is the exact condition defined by the APB spec — PSEL alone is the SETUP phase, PENABLE going high marks the ACCESS phase where the write commits. Reset to `0x00000000` on active-low async PRESETn.

**Ports:** REG\_DATA (out), PWDATA, PSEL, PENABLE, PWRITE, PCLK, PRESETn

---

### APB\_SLAVE.v — 4-Register File

Instantiates four `APB_SLAVE_REG` modules and adds two things: register selection and PRDATA multiplexing. Each register gets its own gated PSEL — `PSEL & (PADDR[3:2] == n)` — so only the addressed register can capture a write. PENABLE and PWRITE are shared across all four. PRDATA is a combinational mux that selects the addressed register's output based on `PADDR[3:2]`. PREADY is tied permanently high.

**Key idea:** The gated PSEL is what makes registers independent. Without it, all four would latch every write simultaneously.

**Ports:** PRDATA (out), PREADY (out), PWDATA, PADDR, PSEL, PENABLE, PWRITE, PCLK, PRESETn

---

### APB\_DECODER.v — Address Decoder + PRDATA Mux

Purely combinational — no clock, no register, no state. Two jobs: assert the correct one-hot slave select from PADDR\[9:8\] gated with MASTER\_PSEL, and mux the active slave's PRDATA back to the master. Without the MASTER\_PSEL gate, the decoder would assert a slave select any time PADDR points at a slave's range — even during IDLE when no transfer is in progress.

**Ports:** PRDATA (out), PSEL0/1/2 (out), PADDR, MASTER\_PSEL, PRDATA0/1/2

---

### APB\_MASTER.v — 3-State FSM

The only active driver on the bus. Implements a three-state FSM:

| State | PSEL | PENABLE | Description |
| --- | --- | --- | --- |
| IDLE | 0 | 0 | Bus idle, waiting for TRANSFER pulse |
| SETUP | 1 | 0 | Address and data driven, PENABLE not yet asserted |
| ACCESS | 1 | 1 | Transfer in progress, waits for PREADY |

Transition IDLE → SETUP on `TRANSFER` pulse. SETUP → ACCESS unconditionally after one cycle. ACCESS → IDLE when `PREADY` is high. DONE pulses for exactly one cycle on the ACCESS → IDLE transition. On reads, RDATA\_OUT captures PRDATA on the same cycle DONE pulses.

**Key idea:** All outputs are registered to prevent combinational glitches on the bus. DONE defaults to 0 every cycle and is only overridden by the ACCESS → IDLE transition.

**Ports:** PADDR, PWDATA, PSEL, PENABLE, PWRITE, RDATA\_OUT, DONE (all out); PRDATA, PREADY, ADDR\_IN, WDATA\_IN, WRITE\_IN, TRANSFER, PCLK, PRESETn

---

### APB\_SYSTEM.v — Top-Level Structural Module

Contains zero logic. Instantiates one APB\_MASTER, one APB\_DECODER, and three APB\_SLAVE instances (GPIO, UART, TIMER) and connects all wires. PREADY is OR'd from all three slaves — valid because all three are tied high internally. The external ports expose only the master control interface (ADDR\_IN, WDATA\_IN, WRITE\_IN, TRANSFER, DONE, RDATA\_OUT) so the testbench drives the system without reaching inside the hierarchy.

**Ports:** RDATA\_OUT, DONE (out); ADDR\_IN, WDATA\_IN, WRITE\_IN, TRANSFER, PCLK, PRESETn

### System Testbench — LFSR + MISR

**APB\_SYSTEM\_TB.sv**

The system testbench connects two `lfsr32` instances and one `misr32` instance alongside the DUT. It runs in two phases:

**Phase 1 — LFSR-driven writes (64 transfers):** LFSR\_ADDR generates addresses (bits \[1:0\] select the slave, bits \[3:2\] select the register within that slave). LFSR\_DATA generates write data (full 32-bit output). Both LFSRs are staggered by one cycle during initialisation so their output streams are uncorrelated. LFSR\_EN advances both LFSRs only on the first cycle of each transfer.

**Phase 2 — LFSR-driven reads (64 transfers):** LFSRs are reset to replay the same address sequence as Phase 1. On each transfer, MISR\_EN (= DONE & \~WRITE\_IN) gates the MISR to clock in RDATA\_OUT. After all 64 reads, MISR\_SIG holds the compressed signature of the entire DUT response.

The final MISR\_SIG is the **golden signature** for regression testing. Any RTL change that alters the behaviour of any register in any slave will produce a different signature on the next run.

## LFSR and MISR — Theory and Role

### LFSR — Linear Feedback Shift Register

An LFSR is a shift register whose input bit is a XOR function of some of its current bits (the **tap points**). Starting from a non-zero seed, it produces a deterministic pseudo-random sequence of length `2^N - 1` before repeating — called the **maximal-length sequence**.

This implementation is a 32-bit Galois LFSR with tap polynomial `x^32 + x^22 + x^2 + x^1 + 1` (tap mask `0x8020_0003`), seed `0x3050_3050`.

**Update rule each clock cycle (when EN=1):**

```
state = {state[30:0], 1'b0} ^ (state[31] ? 32'h80200003 : 32'h0)
```

If the outgoing MSB is 1, XOR the entire register with the tap mask. If 0, just shift left. This generates a full 2^32 - 1 length sequence before repeating.

**In this testbench:** Two `lfsr32` instances share the same module. `LFSR_ADDR` drives the address (bits \[3:0\] masked to 12 valid register addresses). `LFSR_DATA` drives write data (all 32 bits used). They are staggered by one cycle during initialisation so their output sequences are uncorrelated — otherwise the same LFSR value would appear on both ADDR and DATA simultaneously, producing a very specific (and unrealistic) pattern.

---

### MISR — Multiple Input Signature Register

A MISR is an LFSR with an additional XOR input at each clock cycle. Instead of running freely, it folds external data into its state:

```
state = {state[30:0], 1'b0} ^ (state[31] ? POLY : 32'h0) ^ data_in
```

This compresses an arbitrarily long sequence of 32-bit values into a single 32-bit **signature**. The same sequence of inputs always produces the same signature.

**Why use a MISR for output checking?**

- **Compression:** 64 read-back values (2048 bits) are compressed into one 32-bit number
- **Regression testing:** Run once, record the signature. On every future run, compare the signature. Any difference — from any register, from any slave, on any transfer — changes the signature
- **No golden model needed:** The first correct run defines the golden signature. No reference model is required
- **Fault coverage:** A MISR with a maximal-length polynomial has very high probability of detecting any single stuck-at fault in the DUT outputs

**In this testbench:** The MISR clocks in `RDATA_OUT` only on cycles where `DONE & ~WRITE_IN` — exactly the cycles where a valid read has completed. After 64 read transfers, `MISR_SIG` holds the compressed signature of the entire DUT response across all three slaves and all four registers per slave.

**Golden signature workflow:**

1. Run `APB_SYSTEM_TB` once on a known-good DUT
2. Record `MISR_SIG` from the waveform at `$finish`
3. Add a `CHECK` assertion to the testbench: `if (MISR_SIG !== GOLDEN) $error(...)`
4. Any future RTL change that breaks any register's behaviour will produce a mismatch

### What This Project Covers

| Concept | Where demonstrated |
| --- | --- |
| APB two-phase timing | APB\_MASTER FSM, all unit TBs |
| Synchronous register design | APB\_SLAVE\_REG |
| Address decoding | APB\_DECODER |
| Structural RTL hierarchy | APB\_SYSTEM |
| FSM design (Mealy outputs) | APB\_MASTER |
| Combinational mux | APB\_DECODER, APB\_SLAVE PRDATA |
| LFSR pseudo-random generation | UNIVERSAL\_LFSR, APB\_SYSTEM\_TB |
| MISR signature compression | UNIVERSAL\_MISR, APB\_SYSTEM\_TB |
| Bottom-up verification strategy | Full testbench suite |
| Vivado waveform-based debug | All testbenches |
