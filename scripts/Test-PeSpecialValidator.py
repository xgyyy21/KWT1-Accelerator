"""Negative checks on COPIES of real outputs; not hardware evidence."""
import argparse
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import csv

runner=Path(__file__).with_name('Run-PeSpecialValidation.py')
if not runner.exists():
    runner=Path(__file__).with_name('Replay-Special.py')
spec=importlib.util.spec_from_file_location('pe_special',runner)
module=importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

def write_csv(path, fields, rows):
    with path.open('w',encoding='ascii',newline='') as stream:
        writer=csv.DictWriter(stream,fields,lineterminator='\n')
        writer.writeheader(); writer.writerows(rows)

class ValidatorTests(unittest.TestCase):
    packet=None
    results=None
    def setUp(self):
        self.case=next(c for c in json.loads((self.packet/'cases.json').read_bytes()) if c['id']=='k32_boundary')
        self.original=self.results/'k32_boundary'
        self.revision=json.loads((self.packet/'provenance.json').read_bytes())['csv_rtl_commit']
    def mutate(self, filename, mutation):
        with tempfile.TemporaryDirectory() as name:
            output=Path(name)
            for leaf in ('pe_trace.csv','signal_trace.csv'):
                fields,rows=module.csv_read(self.original/leaf)
                if leaf==filename:
                    mutation(rows)
                write_csv(output/leaf,fields,rows)
            with self.assertRaises(ValueError):
                module.validate_measured(output,self.case,self.revision)
    def test_real_evidence(self):
        report=module.validate_measured(self.original,self.case,self.revision)
        self.assertEqual(report['status'],'PASS')
        self.assertEqual(len(report['actual_k32_boundaries']),1)
        self.assertEqual(report['actual_k32_boundaries'][0]['previous_acc_after_bits'],'0x40000000')
        self.assertEqual(report['actual_k32_boundaries'][0]['next_acc_before_bits'],'0x40000000')
    def test_wrong_global_k(self):
        self.mutate('pe_trace.csv',lambda rows: rows[32].update(k='0'))
    def test_wrong_tile(self):
        self.mutate('pe_trace.csv',lambda rows: rows[32].update(tile_id='0'))
    def test_wrong_bias_tile(self):
        self.mutate('pe_trace.csv',lambda rows: rows[-1].update(tile_id='0'))
    def test_cleared_wait_accumulator(self):
        def change(rows):
            next(r for r in rows if r['enable']=='0')['accumulator_bits']='0x00000000'
        self.mutate('signal_trace.csv',change)
    def test_missing_wait(self):
        def change(rows):
            for r in rows:
                r['enable']='1'
        self.mutate('signal_trace.csv',change)
    def test_reset_at_boundary(self):
        def change(rows):
            next(r for r in rows if r['enable']=='0')['rst_n']='0'
        self.mutate('signal_trace.csv',change)
    def test_clear_at_boundary(self):
        def change(rows):
            next(r for r in rows if r['enable']=='0')['clear_acc']='1'
        self.mutate('signal_trace.csv',change)
    def test_task_first_at_second_block(self):
        def change(rows):
            next(r for r in rows if r['block']=='1' and r['input_accept']=='1')['task_first']='1'
        self.mutate('signal_trace.csv',change)
    def test_lost_partial_sum(self):
        self.mutate('pe_trace.csv',lambda rows: rows[32].update(acc_before_bits='0x00000000'))
    def test_duplicate_bias(self):
        self.mutate('pe_trace.csv',lambda rows: rows.append(copy.deepcopy(rows[-1])))
    def test_wrong_result_valid(self):
        def change(rows):
            next(r for r in rows if r['trace_bias_valid']=='1')['result_valid']='0'
        self.mutate('signal_trace.csv',change)
    def test_wrong_cycle(self):
        self.mutate('pe_trace.csv',lambda rows: rows[32].update(cycle=str(int(rows[32]['cycle'])+1)))
    def test_multiplier_latency(self):
        def change(rows):
            accepts=[r for r in rows if r['input_accept']=='1']
            later=next(r for r in rows if int(r['cycle'])==int(accepts[0]['cycle'])+1)
            accepts[0]['input_accept']='0'; later['input_accept']='1'
        self.mutate('signal_trace.csv',change)

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--packet',type=Path,required=True)
    parser.add_argument('--results',type=Path)
    args,remaining=parser.parse_known_args()
    ValidatorTests.packet=args.packet.resolve()
    ValidatorTests.results=args.results.resolve() if args.results else ValidatorTests.packet/'replay'
    unittest.main(argv=['Test-PeSpecialValidator.py',*remaining])
