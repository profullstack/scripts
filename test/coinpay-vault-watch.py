import os,subprocess,tempfile,time,json
from pathlib import Path
root=Path(__file__).resolve().parent.parent/'bin'
cases=[
 ('legacy-clear',{'mode':'legacy','sealedSigningRows':0},'',0,None),
 ('legacy-sealed',{'mode':'legacy','sealedSigningRows':5},'',1,'signing mismatch'),
 ('vault-unknown',{'mode':'operator-vault','sealedSigningRows':5},'',1,'state is unknown'),
 ('vault-locked',{'mode':'operator-vault','sealedSigningRows':5},'operator keys locked',1,'vault is LOCKED'),
 ('probe-failed',{'mode':'probe-error'},'',1,'could not be verified'),
]
for name,probe,logs,want,phrase in cases:
 with tempfile.TemporaryDirectory() as temp:
  t=Path(temp);b=t/'bin';b.mkdir();state=t/'state';sent=t/'sent';fixture=t/'probe';fixture.write_text(json.dumps(probe));probe_input=t/'input.mjs';probe_input.write_text('')
  mocks={
   'docker':'#!/bin/sh\ncase "$1" in exec) cat "$WATCH_TEST_JSON";; logs) printf "%s\\n" "$WATCH_TEST_LOGS";; inspect) echo 2026-10-01T00:00:00Z;; esac\n',
   'alert':'#!/bin/sh\nprintf "%s\\n" "$*" >> "$WATCH_TEST_SENT"\n',
   'mail':'#!/bin/sh\nexit 0\n',
  }
  for command,body in mocks.items():p=b/command;p.write_text(body);p.chmod(0o755)
  s=(root/'coinpay-vault-watch').read_text();s='\n'.join(l for l in s.splitlines() if not l.startswith('export PATH='));s=s.replace('S="$HOME/.local/state/coinpay-vault-watch"',f'S="{state}"')
  script=t/'watch';script.write_text(s)
  env={**os.environ,'PATH':str(b)+':'+os.environ['PATH'],'WATCH_TEST_JSON':str(fixture),'WATCH_TEST_LOGS':logs,'WATCH_TEST_SENT':str(sent),'COINPAY_WATCH_PROBE':str(probe_input)}
  subprocess.run(['bash',str(script)],env=env,check=name!='probe-failed',capture_output=True)
  lines=sent.read_text().splitlines() if sent.exists() else []
  assert len(lines)==want,(name,lines)
  if phrase:assert phrase in lines[0],(name,lines)
  if name=='legacy-sealed':assert 'Unlock the CoinPay operator vault' not in lines[0]
  if want:
   subprocess.run(['bash',str(script)],env=env,capture_output=True)
   assert len(sent.read_text().splitlines())==1,'repeat was not throttled'
  print('PASS',name)
