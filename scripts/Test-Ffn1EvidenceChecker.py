"""Synthetic unit tests of the evidence checker, NOT RTL simulation evidence."""
import copy
import importlib.util
from pathlib import Path
import unittest

spec=importlib.util.spec_from_file_location('ffn1_checker',Path(__file__).with_name('Run-Ffn1Verification.py'))
checker=importlib.util.module_from_spec(spec);spec.loader.exec_module(checker)

class CheckerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.outputs=[dict(row=str(i//256),column=str(i%256),word_address=str(210000+2*i),
                          result_bits='0x42820000',expected_bits='0x42820000',match='1')
                     for i in range(99*256)]
        cls.writes=[dict(zip(('tile_id','row','column','word_address','half'),map(str,entry)),
                         cycle=str(2*i+1),actual_word='0x4282' if entry[-1] else '0x0000')
                    for i,entry in enumerate(checker.write_order())]
        cls.tiles=[dict(tile_id=str(i),row_base=str(i//16*8),column_base=str(i%16*16),
                        rows_valid=str(min(8,99-i//16*8)),cols_valid='16',k_blocks='2',cycle=str(i*1000+1))
                   for i in range(208)]

    def test_valid_synthetic_shape(self):
        checker.check_outputs(self.outputs)
        self.assertEqual(checker.check_writes(self.writes,self.outputs),101375)
        checker.check_tiles(self.tiles)

    def test_negative_controls_reject_all_five(self):
        self.assertEqual(len(checker.negative_controls(self.outputs,self.writes,self.tiles)),5)

    def test_duplicate_actual_halfword(self):
        rows=copy.deepcopy(self.writes);rows[1]['word_address']=rows[0]['word_address']
        with self.assertRaises(ValueError):checker.check_writes(rows,self.outputs)

    def test_wrong_actual_halfword(self):
        rows=copy.deepcopy(self.writes);rows[-1]['actual_word']='0x0000'
        with self.assertRaises(ValueError):checker.check_writes(rows,self.outputs)

    def test_wrong_write_cycle(self):
        rows=copy.deepcopy(self.writes);rows[1]['cycle']=rows[0]['cycle']
        with self.assertRaises(ValueError):checker.check_writes(rows,self.outputs)

    def test_missing_final_output(self):
        with self.assertRaises(ValueError):checker.check_outputs(self.outputs[:-1])

    def test_missing_last_tile(self):
        with self.assertRaises(ValueError):checker.check_tiles(self.tiles[:-1])

if __name__=='__main__':
    unittest.main()
