# Verified Mandelbrot simulation

Run from the Gpu folder (requires Python 3, iverilog and vvp):

```sh
python3 tools/run_mandelbrot.py --resolution 16
python3 tools/run_mandelbrot.py --resolution 128
python3 tools/run_mandelbrot.py --resolution 320x240
python3 tools/run_mandelbrot.py --resolution all
```

Defaults: 16x16, seahorse, step 0, 128 iterations, Q16.16, 8 lanes and
4 warps. Optional --target neck|seahorse|elephant|triple and --step 0..32.
--timeout sets the wall-clock limit per RTL run (default 1800 seconds).

The row-based kernel distributes rows across warps and columns across lanes.
The runner substitutes width/height and iteration-buffer base into
software/kernels/mandelbrot.S.in, then assembles a generated program.S.
mandelbrot.S remains a directly assemblable 16x16 version. Edit the template
for changes that should apply to all presets. All requested widths are
multiples of 8; other resolutions are intentionally rejected.

Four launch arguments supply x_start, y_start, x_step, y_step. First
width*height RAM words contain 0x00RRGGBB pixels; the next equally sized
region contains raw iteration counts. Counts use a computed address, rather
than a short immediate offset, so large framebuffers are supported.
RAM is sized automatically to 8 bytes per pixel including iteration storage.
Nested saved masks restore escaped lanes before stores. No display/VGA needed.

Each run compares every pixel and iteration count across an independent
Python calculation, Python ISA model, and actual RTL execution. It also
checks model and RTL issued-instruction counts agree. Results live under:
output/mandelbrot/<width>x<height>/<target>_step<n>/

- program.S / program.hex: actual source and machine code used.
- reference.json / expected.hex: independent expected values.
- rtl_frame.hex: actual RTL RAM dump, including iteration counts.
- rtl_frame.png / rtl_frame.ppm: native resolution RGB image.
- rtl_preview.png: nearest-neighbor enlargement, at most about 512 pixels wide.
- simulation.log / verification.json: pass status, measurements and timings.

comparison_<target>_step<n>.md and .csv compare successfully completed presets
with matching target/step. Earlier outputs in the root Mandelbrot output folder
are retained as historical artifacts, not mixed into the new comparison.

Metrics: simulated cycles, cycles/pixel, issued instructions, issued-lane
utilization, issue occupancy, scheduler-idle cycles, memory-blocked cycles,
and wall times for reference/model/compile/simulation separately. Simulation
wall time includes vvp startup, frame comparison and dump; it is host dependent.
No hardware frequency or FPS is assumed. A future chosen clock can convert
cycles to estimated execution seconds, subject to actual timing closure.

Comparisons use the same center, horizontal view, palette and iteration limit.
320x240 covers a narrower vertical range to preserve square-pixel aspect ratio.
Q16.16 coordinate steps are integer-quantized, so total spans differ slightly.
Sampling and divergence change with resolution; cycles need not scale exactly
with pixel count. Current 16x16 kernel differs from the old linear-index demo;
all new baseline metrics use the same row-based algorithm.
