"""Verify report failure handling and simulate the practice circuit; not synthesis."""
import argparse
import contextlib
import importlib.util
import io
import json
import shutil
from pathlib import Path
import sys
import tempfile
from unittest.mock import patch

root = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('flow', root / 'synthesis/flow.py')
flow = importlib.util.module_from_spec(spec)
spec.loader.exec_module(flow)
checks = []
commands = []
with tempfile.TemporaryDirectory(prefix='stage3a_verify_', dir=root / 'tmp') as tmp:
    td = Path(tmp)
    args = argparse.Namespace(label='negative-validation', top='smoke', files=str(root / 'synthesis/smoke/files.f'),
                              tool='kwt_stage3a_deliberately_missing_yosys_7f290', sdc=None, timeout=10)
    out = td / 'missing_tool'
    out.mkdir()
    with patch.object(flow, 'directory', return_value=out), contextlib.redirect_stdout(io.StringIO()):
        code = flow.run(args)
    data = json.loads((out / 'report.json').read_text(encoding='utf8'))
    assert code == 2 and data['status'] == data['synthesis']['status'] == 'BLOCKED'
    assert all(m['value'] is None and m['status'] == 'BLOCKED' for m in data['ppa'].values())
    assert not (out / 'netlist.v').exists()
    checks.append('PASS: missing executable returns 2, writes BLOCKED logs and null PPA; no netlist')
    assert data['inputs'][0]['sha256'] == flow.sha(root / 'synthesis/smoke/smoke.v')
    assert data['git']['branch'] and data['git']['commit']
    checks.append('PASS: Git snapshot and source SHA-256 match actual inputs')
    sdc = td / 'test.sdc'
    sdc.write_text('# Metadata-only validation; no clock constraint or PPA claim.\n', encoding='utf8')
    args.sdc = str(sdc)
    out2 = td / 'sdc_metadata'
    out2.mkdir()
    with patch.object(flow, 'directory', return_value=out2), contextlib.redirect_stdout(io.StringIO()):
        assert flow.run(args) == 2
    data2 = json.loads((out2 / 'report.json').read_text(encoding='utf8'))
    assert data2['constraints']['version'] == flow.sha(sdc) and data2['constraints']['applied'] is False
    checks.append('PASS: SDC hash recorded without claiming application or timing analysis')
    args.top = 'bad; injection'
    out3 = td / 'invalid_input'
    out3.mkdir()
    with patch.object(flow, 'directory', return_value=out3), contextlib.redirect_stdout(io.StringIO()):
        assert flow.run(args) == 1
    assert json.loads((out3 / 'report.json').read_text(encoding='utf8'))['status'] == 'FAIL'
    checks.append('PASS: invalid top rejected with FAIL and retained report')
    rec = flow.execute([sys.executable, '-c', 'raise SystemExit(7)'])
    commands.append(rec)
    assert rec['returncode'] == 7 and rec['status'] == 'FAIL'
    rec = flow.execute([sys.executable, '-c', 'import time; time.sleep(2)'], timeout=0.2)
    commands.append(rec)
    assert rec['status'] == 'FAIL' and 'timeout' in rec['error']
    checks.append('PASS: nonzero exit and timeout remain failures')
    buffer = io.StringIO()
    with contextlib.redirect_stdout(buffer):
        assert flow.compare(argparse.Namespace(reports=[str(out / 'report.json'), str(out2 / 'report.json')])) == 0
    assert buffer.getvalue().count('negative-validation') == 2 and 'BLOCKED' in buffer.getvalue()
    checks.append('PASS: two-run comparison shows missing metrics as BLOCKED')
    tb = '''module smoke_check;
reg clk=0, reset=1, enable=0;
reg [7:0] a=0,b=0;
wire [8:0] q;
smoke dut(clk,reset,enable,a,b,q);
always #5 clk=~clk;
initial begin
  @(posedge clk); #1; if(q !== 0) $fatal(1,"reset");
  @(negedge clk); reset=0; enable=1; a=255; b=255;
  @(posedge clk); #1; if(q !== 510) $fatal(1,"carry");
  @(negedge clk); enable=0; a=1; b=2;
  @(posedge clk); #1; if(q !== 510) $fatal(1,"hold");
  @(negedge clk); enable=1;
  @(posedge clk); #1; if(q !== 3) $fatal(1,"addition");
  @(negedge clk); reset=1;
  @(posedge clk); #1; if(q !== 0) $fatal(1,"reset priority");
  $display("STAGE3A_SMOKE_SIM_OK"); $finish;
end
endmodule
'''
    source = td / 'smoke_check.v'
    source.write_text(tb, encoding='ascii')
    rec = flow.execute([shutil.which('iverilog'), '-g2012', '-s', 'smoke_check', '-o', str(td / 'sim.vvp'),
                        str(root / 'synthesis/smoke/smoke.v'), str(source)], td)
    commands.append(rec)
    assert rec['status'] == 'PASS', rec
    rec = flow.execute([shutil.which('vvp'), str(td / 'sim.vvp')], td)
    commands.append(rec)
    assert rec['status'] == 'PASS' and 'STAGE3A_SMOKE_SIM_OK' in rec['stdout'], rec
    checks.append('PASS: actual Icarus simulation checks reset, 255+255 carry, enable hold, addition and reset priority')
result = {'status':'PASS', 'time':flow.now(), 'runner':flow.identity(flow.__file__),
          'verification_script':flow.identity(__file__), 'git':flow.snapshot(),
          'checks':checks, 'commands':commands, 'testbench_source':tb,
          'comparison_output':buffer.getvalue(),
          'limitations':'No Yosys installed: successful synthesis/netlist/statistics path is NOT_RUN. Icarus simulation is not synthesis or formal equivalence.'}
(root / 'synthesis/validation.json').write_text(json.dumps(result, ensure_ascii=False, indent=2)+'\n', encoding='utf8')
print('\n'.join(checks))
