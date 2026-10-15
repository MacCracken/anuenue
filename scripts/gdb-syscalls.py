# scripts/gdb-syscalls.py — the set of syscalls one run makes (v1.4.4).
#
# Run by scripts/fault-check.sh as `gdb -q -batch -x scripts/gdb-syscalls.py BIN`
# with ANUENUE_RUN set to the gdb `run` argument string. Catches every
# syscall entry and prints "SYSCALLS <nr> <nr> ..." (sorted, distinct) for
# the caller to compare against an allowlist. x86_64 syscall numbers.
import gdb, os
gdb.execute("set pagination off"); gdb.execute("set confirm off")
gdb.execute("catch syscall", to_string=True)
gdb.execute("run " + os.environ["ANUENUE_RUN"], to_string=True)
seen, entry, stops = set(), True, 0
while gdb.selected_inferior().pid != 0 and stops < 400000:
    stops += 1
    if entry:
        seen.add(int(gdb.parse_and_eval("$orig_rax")))
    entry = not entry
    gdb.execute("continue", to_string=True)
print("SYSCALLS " + " ".join(str(n) for n in sorted(seen)))
