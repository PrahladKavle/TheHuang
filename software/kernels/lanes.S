# Each lane stores its ID at its own RAM address.
# Each warp gets a separate region.

RDSR r1, LANE_ID
RDSR r2, WARP_ID
RDSR r3, LANE_COUNT

# Calculate warp_id * lane_count using integer addition.
LDI r4, 0
LDI r5, 1

PUSHM
loop:
    SETM r2
    BRANY add_offset
    BR offset_done

add_offset:
    ADD r4, r4, r3
    SUB r2, r2, r5
    BR loop

offset_done:
POPM

# Global index = warp offset + lane ID.
ADD r4, r4, r1

# Convert word index to byte address.
SHL r4, r4, 2

# Store lane ID, then load it back into r6.
STR r1, 0(r4)
LDR r6, 0(r4)
RET