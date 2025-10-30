# Video Scaler IP (VHDL)

FPGA-ready, synthesizable VHDL video scaler IP. It supports upscaling and downscaling of RGB video streams over AXI4-Stream and is configurable at runtime via AXI4-Lite.

## Features

- Upscaling and downscaling of RGB video streams
- AXI4-Stream interface for input/output video
- AXI4-Lite interface for runtime configuration
- Runtime-configurable horizontal and vertical interpolation ratios
- Designed for synchronous clocked video systems
- Modular and synthesizable VHDL implementation

## Directory structure

```
.
├── rtl/           # Core VHDL source code for the scaler
├── tb/            # VHDL testbenches
├── sim/           # Simulation scripts (GHDL/VUnit)
├── support/       # Octave/MATLAB support scripts
├── LICENSE        # CERN-OHL-P v2 (permissive)
└── README.md      # This file
```

## Theory of operation

The scaler uses a two-stage interpolation pipeline based on a truncated ideal interpolator (sinc). Scaling is performed horizontally first and then vertically, allowing the design to remain streaming and pipelined.

### Horizontal scaling

The horizontal scaling engine:

- Receives an AXI4-Stream RGB video input
- Uses an FSM to handle edge mirroring for boundary conditions (avoids artifacts near frame edges)
- Feeds input pixels to the interpolation core to compute resampled pixel values
    - The interpolation step depends on the horizontal scaling ratio set via AXI4-Lite
    - Each line is terminated with the TLAST signal
- Produces a scaled output line that’s passed directly to the vertical engine via AXI4-Stream

The horizontal engine is fully streaming and does not buffer entire lines.

### Vertical scaling

The vertical scaling engine:

- Receives horizontally scaled lines from the horizontal scaler
- Buffers input lines (vertical interpolation needs multiple neighboring lines)
    - The maximum supported output width is constrained by the available line buffer size
- Uses a vertical FSM to handle mirroring at the top/bottom edges
- Feeds pixels to the vertical interpolation core to compute resampled pixel values
    - The interpolation step depends on the vertical scaling ratio (AXI4-Lite)
    - New frame is indicated by the TUSER signal
    - Input vertical resolution is set via AXI4-Lite
        - This enables preemptive flush of buffered lines at frame end, without relying solely on TUSER
- Outputs the scaled video frame over AXI4-Stream

### Interpolation method

Both stages use truncated sinc interpolation for high-quality resampling. The kernel is symmetric, and coefficients are precomputed using the provided Octave scripts. The current implementation supports 6-tap or 8-tap kernels with a 32‑phase polyphase structure, enabling fine-grained ratios with efficient hardware utilization.

### Block diagram

<pre>
                   +-------------------------+     +-------------------+     +-------------------------+     +-------------------+                           
                   |                         |     |                   |     |                         |     |                   |                            
AXI4-Stream In --> | Horizontal Scaling      | --> | AXI4-Stream FIFO  | --> | Vertical Scaling        | --> | AXI4-Stream FIFO  | --------> AXI4-Stream Out 
                   | Engine                  |     | (Line Buffer)     |     | Engine                  |     | (Output Buffer)   |                          
                   | - H Interpolation       |     |                   |     | - V Interpolation       |     |                   |                           
                   | - Edge Mirroring        |     |                   |     | - Line Mirroring        |     |                   |                             
                   | - Scaling FSM           |     |                   |     | - Frame Control FSM     |     |                   |                            
                   +-----------+-------------+     +-------------------+     +------------+------------+     +-------------------+                           
                               ^                                                          ^
                               |                                                          |
                               |                                                          |
                               |        +-------------------------------------------------+-------------------+
                               |        |                                                                     |
                               |        |        AXI4-Lite Configuration Register Block                       |
                               |        |          - Horizontal Scaling Ratio                                 |
                               +------- |          - Vertical Scaling Ratio                                   |
                                        |          - Vertical Input Resolution                                |
                                        |          - Status / Control Registers                               |
                                        +---------------------------------------------------------------------+
</pre>


### Register map

| Offset | Register Name    | Index  | Description                  | Writable | Value after reset |
|--------|------------------|--------|------------------------------|----------|-------------------|
| 0x00   | `REG_SC_INFO`    | 0      | Scaler information/status    | No       | TBD               |
| 0x04   | `REG_SC_CONF`    | 1      | Scaler configuration         | Yes      | TBD               |
| 0x08   | `REG_SC_HCOEF`   | 2      | Horizontal scaling ratio     | Yes      | 1.0*              |
| 0x0C   | `REG_SC_VCOEF`   | 3      | Vertical scaling ratio       | Yes      | 1.0*              |
| 0x10   | `REG_SC_VRES`    | 4      | Vertical input resolution    | Yes      | 1920              |

*Scaling ratios are fixed‑point values with 22 fractional bits. Thus, 4194304 (2^22) represents a scaling factor of 1.0. To configure, compute input_size/output_size and multiply by 2^22 (for upscale the ratio is < 1.0; for downscale it is > 1.0). See the testbench and Octave scripts for examples.*

## Getting started

### Configuring the core

The following items can be parameterized (set at compile time in *scale_pkg.vhd*):
- Number of scaling engines (ENG_NUM): 1 or 2
    - Determines pixels/clock for both horizontal and vertical engines
- Number of taps (TAP_NUM): 6 or 8
    - Selects interpolation kernel size. More taps improve quality but require more vertical line buffering and larger mirrored borders (possible pauses while handling mirroring). Coefficients are precomputed via `support/generate_coef_table_vhdl.m`.
- Line buffer size (LINE_SIZE)
    - Limits the maximum output horizontal resolution

### Simulation

The testbench uses VUnit for automated simulation and checking. Required tools:

- VUnit framework: controls simulation, logging, and reporting. Run with `sim/run.py` or integrate into CI
- Xilinx simulation libraries (UNISIM): must be compiled and available
- A simulator: GHDL (or Questa/ModelSim, etc.)

#### Simulation flow

1) Compile Xilinx libraries (GHDL)

```bash
cd sim && ./ghdl_compile.sh
```

2) Prepare input image CSV

- The testbench reads frames from CSV: one file line = one image row.
- Use the provided Octave script to convert images to CSV before simulation.

```bash
cd support && octave image_scaler.m
```
- Copy csv file to testbench folder

```bash
cp support/in_image.csv tb/
```

3) Run VUnit simulation

```bash
python sim/run.py
```

- Line-by-line streaming: the testbench streams CSV lines as image rows over AXI4‑Stream

- Frame repetition: after all lines are sent, the testbench can resend to simulate multiple frames

- Output capture: scaled frames are written to CSV files. Multiple frames are suffixed (e.g., name0.csv, name1.csv, ...). Use `support/output_check.m` to visualize outputs.

- File configuration via generics: input/output filenames are VHDL generics in `tb/tb_scale.vhd` (adjust as needed)

#### Octave support scripts

- `support/image_scaler.m`: convert images ⇄ CSV and run image scaling in Octave
- `support/generate_coef_table_vhdl.m`: regenerate VHDL coefficient packages
- `support/output_check.m`: load CSV outputs and display images
- `support/write_array_to_csv.m`: CSV utilities
- `support/scale_image.m`: Octave scaling engine prototype

## License

This project is licensed under the CERN Open Hardware Licence Version 2 – Permissive (CERN‑OHL‑P v2).

- See the `LICENSE` file in this repository for full terms
- Reference: https://ohwr.org/cern_ohl_p_v2.txt
