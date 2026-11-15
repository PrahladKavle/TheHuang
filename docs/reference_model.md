# Python GPU reference model

```sh
python3 model/gpu_model.py output/programs/lanes.hex --launch-all -o output/model.json
python3 -m unittest discover -s tests -v
```

Executes the implemented custom ISA, including masks/stacks, signed Q16.16,
ballot, barriers and spawning. PRESENT faults like the current core.
JSON includes registers, memory, PCs and masks. Uninitialized locations are
null; using undefined operands raises an error instead of guessing zero.
Registers and RAM are retained on relaunch, while masks/stacks/arguments reset.

This is a functional reference, not a timing simulator. Memory is atomic per
instruction, and spawn launches are immediate. Do not compare cycle counters,
racy stores or partial fault side effects with RTL. Compare race-free programs'
initialized register/RAM results. Currently add.S and lanes.S are compared
against actual RTL by test_gpu_model.py; other features have directed tests.
