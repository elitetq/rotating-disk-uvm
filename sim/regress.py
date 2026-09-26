#!/usr/bin/env python3

import argparse, re, subprocess, sys, time
from pathlib import Path

CUR_DIR = Path(__file__).resolve().parent

TESTS = {"pwm": ["pwm_smoke_test","pwm_base_test","pwm_corner_test","pwm_duty_change_test","pwm_random_test","pwm_reset_test"]}

SEV = re.compile(r"^UVM_(INFO|WARNING|ERROR|FATAL)\s*:\s*(\d+)", re.M)

def run_once(phase, test, seed = 0, cov = 0):
    cmd = ['make','-s',f'PHASE={phase}',f'TEST={test}',f'SEED={seed}',f'COV={cov}','run']
    t0 = time.time()
    process = subprocess.run(cmd,cwd=CUR_DIR,capture_output=True,text=True)
    elapsed_time = time.time() - t0
    out = process.stdout + process.stderr

    counts = {k: int(v) for k, v in SEV.findall(out)}

    if process.returncode: status = "TOOLFAIL"
    elif not "UVM Report Summary" in out: status = "NOREPORT"
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
        help='Coverage db')
    argp.add_argument('--start_seed',type=int,default=0, \
        help='Start of randomization seed, inclusive (default: 0)')
    argp.add_argument('--seeds',type=int,default=1, \
        help='Number of randomization seeds to run (default: 1)')
    argp.add_argument('--clear',action='store_true', \
        help='Clear logs folder')
    args = argp.parse_args()
    
    if(args.clear):
        cmd = ["find","logs","-mindepth","1","-delete"]
        process = subprocess.run(cmd,cwd=CUR_DIR,capture_output=True,text=True)
        print("Successfully deleted logs!") if not process.returncode else \
            print("Failed to delete logs folder!")
        return
    phases = args.phase or list(TESTS)
    start_seed = args.start_seed
    seeds = args.seeds
    
    passes, fails = 0, 0
    items = []
    
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
                    status, counts, elapsed_time, out = run_once(phase,test,i,args.cov)
                    timer += elapsed_time;

                    # pass fail logging | PHASE | TEST | SEED |
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