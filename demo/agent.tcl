# Shared by the handoff scenes. expect only passes the agent's output to the
# recording while it waits in an expect command, so every pause here waits in
# expect rather than sleeping; otherwise typing only shows up at the end.
proc fail {why} { puts stderr "demo: $why"; exit 1 }
proc pause {secs} { # expect timeouts are whole seconds, so poll in small steps
    set until [expr {[clock milliseconds] + int($secs * 1000)}]
    while {[clock milliseconds] < $until} {
        expect -timeout 0 -re {\x00never\x00} {} timeout {} eof { fail "the agent exited early" }
        after 10
    }
}
proc wait_for {re} {
    expect -timeout 120 -re $re {} timeout { fail "timed out waiting for $re" } eof { fail "the agent exited before $re" }
}
proc type {text} { foreach ch [split $text ""] { send -- $ch; pause 0.05 } }
proc settle {secs} { # until the agent has drawn nothing for secs
    expect -timeout $secs -re {.+} { exp_continue } timeout {} eof { fail "the agent exited early" }
}
