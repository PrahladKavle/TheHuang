"""Two-pass assembler for the custom GPU ISA. No external dependencies."""
import argparse
import re
from pathlib import Path

OPS = {name: i for i, name in enumerate(
    "ADD SUB AND OR XOR SLT MUL SHL SHR SEQ MIN MAX LDI LUI RDSR SETM PUSHM POPM TMC BALLOT BRANY BR RET WSPAWN BARRIER LDR STR PRESENT".split())}
SPECIAL = dict(LANE_ID=0, WARP_ID=1, LANE_COUNT=2, WARP_COUNT=3,
               ARG0=16, ARG1=17, ARG2=18, ARG3=19)

class AssemblyError(ValueError):
    pass

def number(token):
    try:
        return int(token, 0) if not re.fullmatch(r"[+-]?[0-9]+", token) else int(token, 10)
    except ValueError:
        raise AssemblyError(f"expected integer, got {token!r}") from None

def bounded(token, low, high):
    value = number(token)
    if not low <= value <= high:
        raise AssemblyError(f"{token}: expected {low}..{high}")
    return value

def reg(token):
    if not re.fullmatch(r"[rR](?:[0-9]|1[0-5])", token):
        raise AssemblyError(f"invalid register {token!r}; use r0..r15")
    return int(token[1:])

def assemble(source):
    labels, records, pc = {}, [], 0
    for lineno, original in enumerate(source.splitlines(), 1):
        line = re.split(r"#|;|//", original, maxsplit=1)[0].strip()
        while ':' in line:
            label, line = line.split(':', 1)
            label = label.strip()
            if not re.fullmatch(r"[A-Za-z_][A-Za-z_0-9]*", label) or label in labels:
                raise AssemblyError(f"line {lineno}: invalid or duplicate label {label!r}")
            labels[label] = pc
            line = line.strip()
        if not line:
            continue
        parts = line.split(None, 1)
        op = parts[0].upper()
        args = [a.strip() for a in parts[1].split(',')] if len(parts) > 1 else []
        records.append((lineno, pc, op, args))
        pc += 12 if op == 'LI' else 4
    words = []
    for lineno, pc, op, args in records:
        def arity(n):
            if len(args) != n:
                raise AssemblyError(f"{op} expects {n} operands, got {len(args)}")
        def target(token):
            value = (labels[token] - (pc + 4)) // 4 if token in labels else number(token)
            if not -8192 <= value <= 8191:
                raise AssemblyError("branch offset outside signed 14-bit range")
            return value & 0x3fff
        def encode(name, d=0, a=0, b=0, imm=0):
            return (OPS[name] << 26) | (d << 22) | (a << 18) | (b << 14) | imm
        try:
            if op == '.WORD':
                arity(1); words.append(bounded(args[0], 0, 0xffffffff)); continue
            if op == 'LI':
                arity(3)
                d, tmp = reg(args[0]), reg(args[2])
                value = bounded(args[1], -0x80000000, 0xffffffff) & 0xffffffff
                if not d or not tmp or d == tmp:
                    raise AssemblyError("LI requires distinct nonzero destination and scratch registers")
                words += [encode('LUI', d, imm=value >> 14),
                          encode('LDI', tmp, imm=value & 0x3fff), encode('OR', d, d, tmp)]
                continue
            if op not in OPS:
                raise AssemblyError(f"unknown instruction {op!r}")
            d = a = b = imm = 0
            if op in 'ADD SUB AND OR XOR SLT MUL SEQ MIN MAX'.split():
                arity(3); d, a, b = map(reg, args)
            elif op in ('SHL', 'SHR'):
                arity(3); d, a = map(reg, args[:2]); imm = bounded(args[2], 0, 31)
            elif op in ('LDI', 'LUI'):
                arity(2); d = reg(args[0]); imm = bounded(args[1], 0, (1 << (18 if op == 'LUI' else 14)) - 1)
            elif op == 'RDSR':
                arity(2); d = reg(args[0]); imm = SPECIAL.get(args[1].upper())
                if imm is None: imm = bounded(args[1], 0, 16383)
                if imm not in SPECIAL.values(): raise AssemblyError("unsupported special register")
            elif op in ('SETM', 'TMC'):
                arity(1); a = reg(args[0])
            elif op == 'BALLOT':
                arity(2); d, a = map(reg, args)
            elif op in ('BR', 'BRANY'):
                arity(1); imm = target(args[0])
            elif op == 'WSPAWN':
                arity(2); a = reg(args[0]); imm = target(args[1])
            elif op in ('LDR', 'STR'):
                arity(2)
                match = re.fullmatch(r"([^()]*)\(\s*([rR][0-9]+)\s*\)", args[1])
                if not match: raise AssemblyError("memory operand must be offset(rBase)")
                a = reg(match[2]); imm = bounded(match[1].strip() or '0', -8192, 8191) & 0x3fff
                if op == 'LDR': d = reg(args[0])
                else: b = reg(args[0])
            else:
                arity(0)
            words.append(encode(op, d, a, b, imm))
        except AssemblyError as error:
            raise AssemblyError(f"line {lineno}: {error}") from None
    return words

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('-o', '--output', type=Path, required=True)
    args = parser.parse_args()
    try:
        words = assemble(args.source.read_text())
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(''.join(f'{word:08x}\n' for word in words))
    except (AssemblyError, OSError) as error:
        parser.exit(1, f'{args.source}: {error}\n')
    print(f'Assembled {len(words)} instructions/words -> {args.output}')

if __name__ == '__main__':
    main()
