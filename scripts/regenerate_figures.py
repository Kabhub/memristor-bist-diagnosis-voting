"""Regenerate numeric plots from recorded CSVs; original image/vector masters remain intact.
Asset numbers match the original full manuscript. docs/figure_number_mapping.json
maps them to the shortened main paper and supplement. Plot styling may differ.
"""
from pathlib import Path
import csv
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
R=Path(__file__).resolve().parents[1];O=R/'figures/regenerated';O.mkdir(exist_ok=True)
def rows(n):return list(csv.DictReader((R/n).open(encoding='utf-8-sig')))
def save(f,n):
 f.tight_layout();f.savefig(O/f'figure_{n:02}.png',dpi=300,bbox_inches='tight');f.savefig(O/f'figure_{n:02}.pdf',bbox_inches='tight');plt.close(f)
a=['standard_tmr','self_purging_tmr','secded','proposed_destructive','proposed_preserving'];labels=['TMR','Self-purging','SECDED','Destructive','Preserving'];col=['#8073ac','#dfb000','#777777','#239b83','#da6900']
rr=rows('results/registered_implementation/implementation_summary.csv');ix={(r['architecture'],int(r['width'])):r for r in rr if float(r['constraint_mhz'])==100 and r['strategy']=='default'}
for n,fields,names in [(3,['luts','ffs'],['Core LUTs','Core flip-flops']),(4,['wns_ns','total_power_mw'],['Setup slack at 100 MHz (ns)','Whole-benchmark vectorless power (mW)'])]:
 f,axes=plt.subplots(1,2,figsize=(8,3.8))
 for ax,key,title in zip(axes,fields,names):
  v=[float(ix[x,8][key]) for x in a];ax.bar(labels,v,color=col);ax.set_ylabel(title);ax.tick_params(axis='x',rotation=25);ax.grid(axis='y',alpha=.18)
  for j,y in enumerate(v):ax.text(j,y,f'{y:g}',ha='center',va='bottom',fontsize=8)
 save(f,n)
f,axes=plt.subplots(1,3,figsize=(10,3.4))
for ax,key,title in zip(axes,['luts','ffs','wns_ns'],['Core LUTs','Core flip-flops','Setup slack at 100 MHz (ns)']):
 for x,l,c in zip(a,labels,col):ax.plot([8,16,32],[float(ix[x,w][key]) for w in [8,16,32]],'-o',label=l,color=c)
 ax.set(xlabel='Logical word width (bits)',ylabel=title,xticks=[8,16,32]);ax.grid(alpha=.18)
axes[-1].legend(fontsize=7);save(f,5)
r=rows('archive/initial_campaigns/publication_variation_results/state_classification_sweep.csv');f,ax=plt.subplots(figsize=(6.4,3.8))
for k,l in [('lrs_as_hrs_rate','LRS read as HRS'),('hrs_as_lrs_rate','HRS read as LRS'),('balanced_read_error_rate','Balanced read error')]:ax.semilogy([float(x['cv_lrs'])*100 for x in r],[max(float(x[k])*100,1e-5) for x in r],'-o',label=l)
ax.set(xlabel='Coefficient of variation (%)',ylabel='Error rate (%)');ax.legend();ax.grid(alpha=.2);save(f,6)
r=rows('archive/initial_campaigns/publication_variation_results/threshold_sweep.csv');f,ax=plt.subplots(figsize=(6.4,3.8));ax.semilogy([float(x['threshold_ohms']) for x in r],[max(float(x['balanced_read_error_rate'])*100,1e-5) for x in r]);ax.axvline(5050,color='red',ls='--',label='RTL threshold')
opt=[x for x in r if x['is_model_optimal_threshold']=='1'];ax.axvline(float(opt[0]['threshold_ohms']),color='green',ls=':',label='Finite-grid model choice');ax.set(xlabel='Resistance threshold (ohm)',ylabel='Balanced read error (%)');ax.legend();save(f,7)
r=rows('archive/initial_campaigns/publication_variation_results/architecture_robustness_summary.csv');f,axes=plt.subplots(1,4,figsize=(10,3))
profiles=list(dict.fromkeys(x['profile'] for x in r))
for ax,p in zip(axes,profiles):
 for architecture,label in [('standard_tmr','Standard TMR'),('proposed_bist_guided','Proposed')]:
  q=sorted([x for x in r if x['profile']==p and x['architecture']==architecture],key=lambda x:int(x['faults_in_logical_bit']))
  assert len(q)==4,(p,architecture)
  ax.plot([int(x['faults_in_logical_bit']) for x in q],[float(x['correction_rate'])*100 for x in q],'-o',label=label)
 ax.set(title=p,xlabel='Faulty replicas',ylim=(-3,103));ax.grid(alpha=.2)
axes[0].set_ylabel('Correct accepted output (%)');axes[-1].legend(fontsize=7);save(f,8)
r=rows('experiments/late_fault_and_geometric/geometric_paired_results.csv');guards=rows('results/models/variation/architecture_variation_summary.csv');f,ax=plt.subplots(figsize=(7.2,4));profiles=['moderate','stress','severe'];xx=np.arange(3)
for i,(strategy,label) in enumerate([('arithmetic','Arithmetic'),('geometric','Geometric'),('calibrated_paired','Calibrated (paired)'),('calibrated_guard10_r5','Guard + 5 reads (unpaired)')]):
 source=guards if i==3 else r;v=[sum(int(x['correct_count']) for x in source if x['profile']==p and x['strategy']==strategy)/2000 for p in profiles];ax.bar(xx+(i-1.5)*.19,v,.19,label=label)
ax.set(xticks=xx,xticklabels=profiles,ylabel='Accepted correct (%)',ylim=(0,111));ax.legend(fontsize=8);save(f,9)
r=rows('results/models/device_validation/vteam_nominal_validation.csv');f,axes=plt.subplots(1,2,figsize=(8,3.5))
for ax,row in zip(axes,r):
 dur=float(row['duration_s']);t=np.linspace(0,dur,200);ratio=np.clip(t/(dur/1.05),0,1);v=float(row['initial_resistance_ohms'])+(float(row['final_resistance_ohms'])-float(row['initial_resistance_ohms']))*ratio
 scale=1 if row['operation'].startswith('RESET') else 1e9;ax.plot(t*scale,v);ax.axhline(float(row['classifier_threshold_ohms']),ls='--',color='black');ax.set(title=row['operation'],xlabel='Time (s)' if scale==1 else 'Time (ns)',ylabel='Resistance (ohm)')
save(f,10)
r=rows('results/defect_aware/implementation_w16/implementation_summary.csv');f,axes=plt.subplots(1,2,figsize=(8,3.7));labels=['Proposed\n48 cells','Remap\n18 cells','Remap\n48 cells']
for ax,k,title in zip(axes,['luts','bist_cycles'],['Core LUTs','Test and allocation cycles']):
 v=[float(x[k]) for x in r];ax.bar(labels,v,color=['#298b7c','#ae8535','#8073ac']);ax.set_ylabel(title)
 for j,y in enumerate(v):ax.text(j,y,f'{y:g}',ha='center',va='bottom')
save(f,11);print('Regenerated numeric plots 3-11 from recorded CSVs:',O)
