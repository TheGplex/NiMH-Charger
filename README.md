# NiMH-Charger

Firmware for a NiMH battery charger built around a **PIC12F683** microcontroller and an **MCP1630** PWM controller, extended to three selectable charge currents: **0.8 A, 0.9 A and 1.0 A**.

## Background

The firmware is based on Microchip's reference design `0810Nimh.asm` (v1.0, 2006), which charges with one fixed current.

The MCP1630 is a **peak-current-mode** controller. The PWM signal from the PIC feeds its `OSC_IN` pin and sets the **switching frequency**, not the duty cycle. Changing the PIC's duty bits therefore does not change the charge current in a useful way.

My version changes the PWM **period** instead (the `PR2` register) and keeps `CCPR1L` and `CCP1CON` as in the original. A lower switching frequency transfers almost linearly less current.

## Measurements

With `CCPR1L = 0x83` and `CCP1CON = 0x0C` constant:

| PR2  | Charge current | |
|------|----------------|---|
| 0x03 | 1.20 A | measured |
| 0x04 | ~1.00 A | interpolated |
| 0x05 | 0.89 A | measured |
| 0x06 | 0.80 A | measured |
| 0x07 | 0.63 A | measured |

## Usage

At the top of `0810Nimh_3levels_v3.asm`, enable exactly one `CHARGE_LEVEL` line:

| `CHARGE_LEVEL` | Current | PR2 |
|---|---|---|
| 0 | 0.8 A | 0x06 |
| 1 | 0.9 A | 0x05 (default) |
| 2 | 1.0 A | 0x04 (only with active cooling) |

Then assemble with MPLAB (MPASM) for the PIC12F683 and program the chip.

## Credits and license

Based on the Microchip reference design by Scott Dearborn, Terry Cleveland and Brian Chu. The original Microchip software license agreement still applies to this derived code. The unmodified original firmware is not included here; it is available from Microchip.
