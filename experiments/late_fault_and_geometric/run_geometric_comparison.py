from pathlib import Path
import importlib.util,json,csv,hashlib
import numpy as np
SRC=Path(__file__).resolve().with_name('run_adaptive_variation.py')
spec=importlib.util.spec_from_file_location('model',SRC);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
OUT=Path(__file__).resolve().parent;rows=[]
# Use the exact fixed-r1 trial streams already used for Table 11. Changing
# threshold alone leaves resistance draws, read noise and fault scenario paired.
for index,(profile,cl,ch) in enumerate(m.PROFILES):
 calibrated=m.choose_calibrated_threshold(np.random.default_rng(m.DEFAULT_SEED+index*1000+1),cl,ch,.15,1,20000)
 for strategy,threshold in [('arithmetic',5050.),('geometric',1000.),('calibrated_paired',calibrated)]:
  for value in [0,1]:
   seed=m.DEFAULT_SEED+200000+index*10000+value
   r={'profile':profile,'cv_lrs':cl,'cv_hrs':ch,'strategy':strategy,'threshold_ohms':threshold,'stored_data':value,'trial_seed':seed,'read_noise_cv':.15}
   r.update(m.proposed_double_fault_trial(np.random.default_rng(seed),100000,value,cl,ch,.15,1,threshold,0.))
   rows.append(r)
with(OUT/'geometric_paired_results.csv').open('w',newline='')as f:
 w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
metadata={'seed':m.DEFAULT_SEED,'trials_per_stored_value':100000,'stored_values':[0,1],'thresholds':{'arithmetic':5050,'geometric':1000,'calibrated':'Same held-out calibration rule, independent of evaluation'},'pairing':'Every strategy uses the same resistance/read-noise stream for each profile and stored value; arithmetic reproduces original fixed-r1 counts. Original unpaired calibrated rows are retained separately.','phase_model':'Independent resistance draws across WRITE_ZERO, WRITE_ONE and operation, held fixed within read burst.','policy':'All usable replicas must agree; same-bit double fault in A+B.','source_sha256':hashlib.sha256(SRC.read_bytes()).hexdigest()}
(OUT/'geometric_metadata.json').write_text(json.dumps(metadata,indent=2))
original=m.__dict__
for profile in ['moderate','stress','severe']:
 print(profile,{s:sum(int(r['correct_count']) for r in rows if r['profile']==profile and r['strategy']==s)/2000 for s in ['arithmetic','geometric','calibrated_paired']})
