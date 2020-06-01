#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Created on Thu May 28 15:09:37 2020

@author: stearb
"""




# read biopypir_log

# get name date, run id, and info


# and check if anything is different, only change 'last checked' if everything same   
import os
import time
import json
import pandas as pd

import tabulate as tb

import glob
import numpy as np
from datetime import datetime


#def populate_log_matrix():
local_path= '/Users/stearb/desktop/temp_biop/logs/*.json'
logs_path = "logs/*.json"
#all_logs = glob.glob(logs_path) 
all_logs = glob.glob(local_path) 
print('Total Logs found: '+str(len(all_logs)))

owners  = []
dups =  []
v=0
list_of_lists = []

for i in range(0,len(all_logs)):
    #if 'ALL JOBS FAILED': 
    data = json.load(open(all_logs[i]))
    
    if len(data) == 26: 
        v=v+1
  
        if v==1: 
            list_of_lists.append(list(data.keys()))
            
        list_of_lists.append(list(data.values()))

df = pd.DataFrame(list_of_lists[1:],columns=list_of_lists[0])


for i in range(0,len(df)):
    if len(df.loc[i,'Date']) < 12: 
        df=df.drop([i])
    else:
        if '"' in df.loc[i,'Date']:
            df.loc[i,'Date'] = df.loc[i,'Date'][1:-1]

df.reset_index(inplace=True,drop=True)

for i in range(0,len(df)):
    owners.append(df.loc[i,'Owner_Repo'])
    if df.loc[i,'Owner_Repo'] in owners: 
        dups.append((df.loc[i,'Owner_Repo'],df.loc[i,'Date']))

u = np.unique(owners)
print(u)


df.to_csv('log_matrix.csv',sep='\t')


'''

# Only read in logs created within time frame ie one week
for filename in glob.glob(os.path.join("logs/", '*.json')):
    if os.path.getmtime(filename) < time.time() - 24 * 60 * 60:  # 24h ago
        continue  # skip the old file
'''



#table = pd.read_csv('biopypir_matrix.md')

