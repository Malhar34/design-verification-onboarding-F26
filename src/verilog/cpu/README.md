# Member CPU

Copy only your SystemVerilog CPU RTL into this directory. Do not copy another project's build,
memory-image, or simulation files. Keep the required `cpu_top` interface unchanged, and update
`sim/behav/Include/member.include` if your implementation uses additional or differently named
source files.

The encrypted final-stage CPU is selected by `make bug_hunt`; do not copy it into this directory.
