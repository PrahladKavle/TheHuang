# Minimal core memory interface

The core now executes aligned 32-bit LDR/STR. Addresses are byte addresses.
Each transaction is accepted when request_valid && request_ready. Both loads
and stores require exactly one response; stores need an acknowledgement.
A response must not be delivered in the request handshake cycle and must
remain valid with stable data/error until response_ready.
Reset must reset/flush both the core and the external memory responder.

The round-robin arbiter accepts one client request into a holding register,
then holds the external request stable until accepted. It tracks the owner
until the response is consumed. There is one external transaction in flight.
The core instantiates an LSU transaction context for each resident warp/lane
(WARPS * LANES), retaining one memory instruction per warp. These are extra
control/storage contexts, not extra ALUs or register files. A future area
optimization can share address-generation hardware with per-warp queues.

Each accepted memory instruction advances the PC and blocks only its warp.
Every lane contributes a completion, including masked lanes (local no-op).
The warp resumes only after all completions are consumed. Load writeback
uses the captured warp and register, and takes priority over new instruction
issue for that cycle. No completion uses the currently scheduled lane mask.

Alignment and bus errors latch a global fault at the original memory PC.
No failing load writes its destination. Successful earlier lane transactions
are not rolled back: faults are terminal until reset, not precise exceptions.
Outstanding external transactions may drain after a fault; reset the whole
memory path before restarting. Launch only inactive warps.

gpu_top connects minimal_core to data_memory. PROGRAM_INIT_FILE and
DATA_INIT_FILE optionally preload hexadecimal words; DATA_DEPTH is in words.
gpu_top_tb tests the real RAM system. core_memory_tb retains the delayed
memory model with request backpressure. minimal_core_tb is an arithmetic regression.
