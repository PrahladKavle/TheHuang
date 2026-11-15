# Performance counters

performance_counters is connected inside minimal_core and exposed by gpu_top.
perf_clear and perf_enable control measurement, and all five values are outputs.
Counters freeze on a latched core fault; reset/clear still work. Start enable
after the launch setup cycles if only execution time is desired; deassert it
when busy drops. Otherwise enabled idle clocks intentionally remain counted.
Five 64-bit counters wrap on overflow. Synchronous reset or clear zeros all
counters, taking priority over enable. Clear works even when disabled.

- total_cycles: every enabled clock, including gaps with no running warps.
- instructions_issued: accepted instructions, including control instructions.
- active_lane_instructions: population count of issued_active_mask on accepted issues.
  This measures issued mask occupancy, not register writes or useful arithmetic.
- scheduler_idle_cycles: at least one running warp, with no running warp ready.
  Ready-but-unissued cycles (writeback, launch, or backpressure) are not included.
- memory_blocked_cycles: at least one running warp has memory_wait asserted.
  Counts a cycle once, regardless of how many warps wait; may overlap issue.

Caller chooses the measurement window explicitly using enable and clear.
Sample mask and events for the instruction accepted on the same rising edge.
Faulted execution should end the measurement window in the caller.
Issue occupancy = instructions_issued / total_cycles.
Issued-lane utilization = active_lane_instructions / (instructions_issued * LANES).
Treat zero denominators as undefined. Calculate ratios outside the hardware.
