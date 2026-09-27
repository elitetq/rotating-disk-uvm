#!/usr/bin/env python3

# Regression script created by Jonart Bajraktari
# Run --help for more info on use.

# CONFIG ---------------

DEFAULT_START_SEED = 0
DEFAULT_SEEDS = 1
DEFAULT_QUITLIMIT = 1000

# ----------------------

import argparse, re, subprocess, sys, time
from pathlib import Path

CUR_DIR = Path(__file__).resolve().parent

TESTS = {"pwm": ["pwm_smoke_test","pwm_base_test","pwm_corner_test","pwm_duty_change_test","pwm_random_test","pwm_reset_test"]}

SEV = re.compile(r"^UVM_(INFO|WARNING|ERROR|FATAL)\s*:\s*(\d+)", re.M) # filtering constructor for UVM numbers

def run_once(phase, test, seed = 0, cov = 0, quit_count = 20):
    cmd = ['make','-s',f'PHASE={phase}',f'TEST={test}',f'SEED={seed}',f'COV={cov}',f'ERROR_CAP={quit_count}','run']
    t0 = time.time()
    process = subprocess.run(cmd,cwd=CUR_DIR,capture_output=True,text=True)
    elapsed_time = time.time() - t0
    out = process.stdout + process.stderr

    counts = {k: int(v) for k, v in SEV.findall(out)}

    if process.returncode: status = "TOOLFAIL"
    elif not "UVM Report Summary" in out: status = "NOREPORT"
    elif "Quit count reached!" in out: status = "LIMITFAIL"
    elif counts.get("ERROR",0) or counts.get("FATAL",0) != 0: status = "FAIL"
    else: status = "PASS"

    return status, counts, elapsed_time, out

def get_time(time_s) -> str:
    ret = ''
    if(int(time_s/60)): ret += f'{int(time_s/60)}m '
    ret += f'{int(time_s)%60}s'
    return ret

def main():
    argp = argparse.ArgumentParser()
    argp.add_argument('--phase',choices=list(TESTS),action='append', \
        help='Choose the UVM phase(s) you want to run (default: all)')
    argp.add_argument('--test', \
        help='Choose the test you want to run (default: all)')
    argp.add_argument('--cov',action='store_true', \
        help='Coverage db (default: False)')
    argp.add_argument('--start_seed',type=int,default=DEFAULT_START_SEED, \
        help=f'Start of randomization seed, inclusive (default: {DEFAULT_START_SEED})')
    argp.add_argument('--seeds',type=int,default=DEFAULT_SEEDS, \
        help=f'Number of randomization seeds to run (default: {DEFAULT_SEEDS})')
    argp.add_argument('--clear',action='store_true', \
        help='Clear logs folder (default: False)')
    argp.add_argument('--quitlimit',type=int,default=DEFAULT_QUITLIMIT, \
        help=f'Max amount of UVM_ERROR allowed before sim termination, status == LIMITFAIL when #UVM_ERROR >= QUITLIMIT (default: {DEFAULT_QUITLIMIT})')
    args = argp.parse_args()
    
    if(args.clear): # --clear | rm logs folder
        cmd = ["find","logs","-mindepth","1","-delete"]
        process = subprocess.run(cmd,cwd=CUR_DIR,capture_output=True,text=True)
        print("Successfully deleted logs!") if not process.returncode else \
            print("Failed to delete logs folder!")
        return 0
    
    phases = args.phase or list(TESTS)
    start_seed = args.start_seed
    seeds = args.seeds
    cov = args.cov
    quitlimit = args.quitlimit

    print(f'Beginning regression script with the following settings:' + \
          f'\nPhases: {str(phases).replace('\'','')}' + \
          f'\nSeeds: {start_seed} -> {start_seed + seeds}' + \
          f'\nCoverage: {'Yes' if cov else 'No'}' + \
          f'\nQuit Limit: {quitlimit}\n')
    
    passes, fails = 0, 0    # track successes and fails
    items = []              # track the actual phase/test/seeds that ran
    
    for phase in phases:
        timer = 0
        tests = [args.test] if args.test else TESTS.get(phase,[])
        print(f'Starting phase \'{phase}\'')
        if not tests:
            print(f"No tests available, skipping...")
        else:
            progress_chunks = ''
            j = 0
            for test in tests:
                items_len = len(tests)*seeds
                print(f'\r[{j}/{items_len}]\t{progress_chunks:<{items_len}}\tRunning {test}...\x1b[K',flush=True,end='')
                for i in range(start_seed,start_seed+seeds):
                    status, counts, elapsed_time, out = run_once(phase,test,i,args.cov,args.quitlimit)
                    timer += elapsed_time;

                    items.append((phase,test,i,status,counts,elapsed_time))
                    if(status == 'PASS'):
                        progress_chunks += '.'
                        passes += 1
                    else:
                        progress_chunks += 'X'
                        fails += 1

                    j += 1
                    print(f'\r[{j}/{items_len}]\t{progress_chunks:<{items_len}}\tRunning {test}...\x1b[K',flush=True,end='')
                    # NOTE: This weird ANSI value above just clears everything to the right
    # EVERYTHING DONE
    print(f'\nResults:\n{passes} passes, {fails} fails. Detailed report below.')
    print(f'{'Phase':^26}|{'Test':^26}|{'Seed':^6}|{'Status':^15}|{'ERROR':^8}|{'WARN':^8}|{'FATAL':^8}|{'Time':^12}')
    print('-'*(27+26+6+15+8+8+8+12+7))
    for i, elem in enumerate(items):
        print(f'{elem[0]:^26}|{elem[1]:^26}|{elem[2]:^6}|{elem[3]:^15}|{elem[4].get("ERROR",0):^8}|{elem[4].get("WARNING",0):^8}|{elem[4].get("FATAL",0):^8}|{get_time(elem[5]):^12}')
    
    return 1 if fails else 0
    # if passes:
    #     print(f'Passes: {passes[0][0]}', end = '')
    #     for i in range(1,len(passes),1):
    #         print(f', {passes[i][0]}', end = '')
    #     print()
    # if fails:
    #     print(f'Fails: {fails[0][0]} [{fails[0][1]}]', end = '')
    #     for i in range(1,len(fails),1):
    #         print(f', {fails[i][0]} [{fails[i][1]}]', end = '')
    #     print()




if __name__ == '__main__':
    sys.exit(main())