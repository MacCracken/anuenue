# scripts/gdb-inject.py — one syscall fault, injected under gdb (v1.4.4).
#
# Run by scripts/fault-check.sh as `gdb -q -batch -x scripts/gdb-inject.py BIN`.
# Reaches branches nothing outside the process can: write(2) returning 0
# for a non-zero length (E-01's zero-byte branch), and EINTR on read or
# write (anuenue installs no handlers, so no real signal produces it).
#
#   ANUENUE_INJECT = "<read|write|fcntl>:<fd|*>:<zero|eintr|fail<errno>>"
#   ANUENUE_RUN    = the gdb `run` argument string (args + redirections)
#
# Every syscall is caught, so entry and exit stops pair up exactly; only
# the FIRST matching call is touched (fd `*` matches any), and the
# program then runs untouched.
#   zero        — set the length argument to 0, so the kernel itself
#                 returns 0.
#   eintr       — turn the call into getpid(2) at entry (nothing happens)
#                 and rewrite its return value to -4 at exit.
#   fail<errno> — the same, returning -<errno> (fail22 = EINVAL).
# Prints "INJECTED <0|1> EXIT <code>"; INJECTED 0 means the premise
# failed (no matching call) and the caller must not count the run.
# x86_64 only: it names $rdi / $rdx / $orig_rax / $rax.
import gdb, os
SYS, FD, MODE = os.environ["ANUENUE_INJECT"].split(":")
NR = {"read": 0, "write": 1, "fcntl": 72}[SYS]
FD = None if FD == "*" else int(FD)
RET = -4 if MODE == "eintr" else (-int(MODE[4:]) if MODE.startswith("fail") else None)
gdb.execute("set pagination off"); gdb.execute("set confirm off")
gdb.execute("catch syscall", to_string=True)
gdb.execute("run " + os.environ["ANUENUE_RUN"], to_string=True)
entry, armed, fix_ret, injected, stops = True, True, False, 0, 0
while gdb.selected_inferior().pid != 0 and stops < 400000:
    stops += 1
    if entry:
        if armed and int(gdb.parse_and_eval("$orig_rax")) == NR \
                and (FD is None or int(gdb.parse_and_eval("$rdi")) == FD):
            armed = False; injected = 1
            if MODE == "zero":
                gdb.execute("set $rdx = 0")
            else:
                gdb.execute("set $orig_rax = 39"); fix_ret = True
    elif fix_ret:
        gdb.execute("set $rax = %d" % RET); fix_ret = False
    entry = not entry
    gdb.execute("continue", to_string=True)
print("INJECTED %d EXIT %s" % (injected, gdb.parse_and_eval("$_exitcode")))
