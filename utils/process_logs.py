#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Created on Thu May 28 15:09:37 2020
@author: stearb
"""

import json
import pandas as pd
import glob
import numpy as np

logs_path = "logs/*.json"
all_logs = glob.glob(logs_path) 

print('Total Logs found: '+str(len(all_logs)))

list_of_lists = []

for i in range(0,len(all_logs)):
    try:
        data = json.load(open(all_logs[i]))
        
    except json.decoder.JSONDecodeError as e:  
        raise SystemExit(e)
        
    if i==0: list_of_lists.append(list(data.keys())) # if it's the first pass of the loop, save the keys to use as headers 
        
    list_of_lists.append(list(data.values())) 

df =pd.DataFrame(list_of_lists[1:],columns=list_of_lists[0])

reordered_cols= ['Package','BADGE','Owner_Repo','Description','date_created','last_commit',
                     'forks','watchers','stars','homepage_url','has_wiki','open_issues',
                     'has_downloads','Run_ID','Date','Pylint_score','Pytest_score','Pip','License','Build','Linux',
                     'Mac','Windows','Linux_versions','Mac_versions','Windows_versions','contributors','num_contributors','Github_event_name']

df = df.reindex(reordered_cols, axis=1)

df.to_csv('log_matrix.csv',index=False,sep='\t')


# Create and save markdown table of packages
md_table =  df.to_markdown()

with open('biopypir_matrix.md', 'w') as f:
    f.write(md_table)

