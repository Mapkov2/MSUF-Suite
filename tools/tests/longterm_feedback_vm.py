"""Independent Lua 5.1 VM probe: TEST of a secret native result raises.

The stock Lua VM cannot represent WoW's secret booleans. This executes the
actual compiled product function using its own bytecode, with synthetic
native methods and the client's documented prohibition on testing secrets.
It is conditional defensive evidence, not a proven live reachable bug.
The private product curve has public stops; the mirror does not prove that
its evaluated native result can become secret.
"""
import struct
import sys
from pathlib import Path

DATA = Path(sys.argv[1]).read_bytes()
assert DATA[:6] == b'\x1bLuaQ\0'
endian, int_size, size_t, instruction_size, number_size, integral = DATA[6:12]
assert endian in (0, 1) and int_size == 4 and size_t in (4, 8)
assert instruction_size == 4 and number_size == 8 and integral == 0
order = '<' if endian else '>'
pos = 12
def raw(n):
    global pos
    assert n >= 0 and pos+n <= len(DATA), 'truncated bytecode'
    out = DATA[pos:pos+n]
    pos += n
    return out
def integer(): return struct.unpack(order+'I', raw(4))[0]
def string():
    n = struct.unpack(order+('I' if size_t == 4 else 'Q'), raw(size_t))[0]
    return raw(n)[:-1].decode('utf-8') if n else None
source = string()
integer(); integer(); raw(4)
code = [integer() for _ in range(integer())]
constants = []
for _ in range(integer()):
    tag = raw(1)[0]
    if tag == 0: value = None
    elif tag == 1: value = raw(1)[0] != 0
    elif tag == 3: value = struct.unpack(order+'d', raw(8))[0]
    elif tag == 4: value = string()
    else: raise AssertionError(tag)
    constants.append(value)
assert integer() == 0, 'nested prototype unsupported; fail closed'
raw(4*integer()) # line info
for _ in range(integer()):
    string();integer();integer()
upnames = [string() for _ in range(integer())]
assert set(upnames) in ({'M','api','AB'}, {'feedbackDesaturate','feedbackAlpha','api','AB'}), upnames
assert pos == len(DATA), 'unparsed bytecode tail'
assert source and 'MSUF_Suite_ActionBars/Paint.lua' in source, source

class Secret:
    pass
SECRET = Secret()
class SecretTestError(RuntimeError):
    pass
def public(value):
    if isinstance(value, Secret):
        raise SecretTestError('attempt to perform boolean test on a secret value')
    return value is not None and value is not False

def run(desaturate=True, cooldown_alpha=100, result=SECRET, active=True, duration=True, feedback=None):
    writes = []
    icon = {'SetDesaturation': lambda self, v: writes.append(('desaturation', v))}
    button = {'icon': icon, 'SetAlpha': lambda self, v: writes.append(('alpha', v))}
    obj = {'EvaluateRemainingDuration': lambda self, curve: result}
    config = {'desaturateCooldown': desaturate, 'cooldownAlpha': cooldown_alpha}
    # The real compiled function's upvalue ordering, as verified by luac -l.
    byname = {'M': {'config': config}, 'api': {'CooldownDuration': lambda slot, ignore: obj if duration else None},
           'AB': {'desatCurve': 'desat', 'alphaCurve': 'alpha'},
           'feedbackDesaturate': desaturate, 'feedbackAlpha': cooldown_alpha < 100}
    ups = [byname[name] for name in upnames]
    registers = {0: {'button': button, 'slot': 1, 'feedback':feedback}, 1: active}
    pc, top, steps = 0, 2, 0
    def rk(value): return constants[value-256] if value >= 256 else registers.get(value)
    while pc < len(code):
        steps += 1
        assert steps <= 10000, 'bytecode execution limit'
        ins = code[pc]
        pc += 1
        op, a, b, c = ins & 63, (ins >> 6) & 255, (ins >> 23) & 511, (ins >> 14) & 511
        bx = (ins >> 14) & 262143
        if op == 0: registers[a] = registers.get(b) # MOVE
        elif op == 1: registers[a] = constants[bx] # LOADK
        elif op == 2: # LOADBOOL
            registers[a] = bool(b)
            if c: pc += 1
        elif op == 3: # LOADNIL
            for i in range(a,b+1): registers[i]=None
        elif op == 4: registers[a] = ups[b] # GETUPVAL
        elif op == 6: registers[a] = registers[b].get(rk(c)) # GETTABLE
        elif op == 9: registers[a][rk(b)] = rk(c) # SETTABLE
        elif op == 11: # SELF
            registers[a+1] = registers[b]
            registers[a] = registers[b][rk(c)]
        elif op == 22: pc += bx - 131071 # JMP
        elif op == 23: # EQ
            assert not isinstance(rk(b), Secret) and not isinstance(rk(c), Secret)
            if (rk(b) == rk(c)) != bool(a): pc += 1
        elif op == 24: # LT
            assert not isinstance(rk(b), Secret) and not isinstance(rk(c), Secret)
            if (rk(b) < rk(c)) != bool(a): pc += 1
        elif op == 26: # TEST: VM truth test of register A.
            try: condition = public(registers.get(a))
            except SecretTestError as exc:
                raise SecretTestError(f'{exc}; product bytecode pc={pc}, TEST r{a}') from exc
            if condition != bool(c): pc += 1
        elif op == 27: # TESTSET
            condition=public(registers.get(b))
            if condition==bool(c): registers[a]=registers.get(b)
            else: pc+=1
        elif op == 28: # CALL
            end = a+b if b else top
            value = registers[a](*[registers.get(i) for i in range(a+1, end)])
            if c == 0:
                registers[a], top = value, a+1
            elif c > 1:
                registers[a] = value
                top = a+c-1
        elif op == 30: return writes # RETURN
        else: raise AssertionError(f'unimplemented opcode {op} at {pc}')
    return writes

cases = [
    ('plain result', {},1,[('desaturation',1),('alpha',1)]),
    ('plain zero', {},0,[('desaturation',0),('alpha',1)]),
    ('flags off cold', {'desaturate':False},SECRET,[]),
    ('flags off restore', {'desaturate':False,'feedback':True},SECRET,[('desaturation',0),('alpha',1)]),
    ('active false', {'active':False},SECRET,[('desaturation',0),('alpha',1)]),
    ('duration nil', {'duration':False},SECRET,[('desaturation',0),('alpha',1)]),
    ('alpha only secret', {'desaturate':False,'cooldown_alpha':50},SECRET,[('desaturation',0),('alpha',SECRET)]),
    ('desaturation secret', {},SECRET,[('desaturation',SECRET),('alpha',1)]),
    ('both secret', {'cooldown_alpha':50},SECRET,[('desaturation',SECRET),('alpha',SECRET)]),
]
failures=[]
for name,args,result,expected in cases:
    try:
        writes=run(result=result,**args)
        assert writes==expected,(name,writes,expected)
        print('PASS:',name)
    except SecretTestError as exc:
        failures.append(name)
        print('FAIL:',name,exc)
print('source:',source,'cases',len(cases),'failed',len(failures))
raise SystemExit(bool(failures))
