#!/usr/bin/env python3
"""Independent resource-boundary run; keeps results separate from 32-case selection evaluation."""
import pathlib, subprocess, sys
script=pathlib.Path(__file__).with_name('evaluate.py')
subprocess.run([sys.executable,str(script),'--stress',*sys.argv[1:]],check=True)
