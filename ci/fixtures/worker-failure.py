#!/usr/bin/python3
"""Logic-test fixture: crash a child after receiving a snapshot, or simulate a hang."""
import os
import pathlib
import signal
import sys
import time

state = pathlib.Path(os.environ['TYPAD_WORKER_TEST_STATE'])
count = int(state.read_text()) if state.exists() else 0
state.write_text(str(count + 1))
mode = os.environ.get('TYPAD_WORKER_TEST_MODE', 'once')
if mode == 'hang':
    sys.stdin.readline()
    time.sleep(30)
elif count == 0 or mode == 'always':
    sys.stdin.readline()
    os.kill(os.getpid(), signal.SIGKILL)
else:
    executable = os.environ['TYPAD_WORKER_TEST_BINARY']
    os.execv(executable, [executable])
