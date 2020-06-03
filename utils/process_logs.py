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
    
    data = json.load(open(all_logs[i]))

    if i==0: list_of_lists.append(list(data.keys()))
        
    list_of_lists.append(list(data.values()))

pd.DataFrame(list_of_lists[1:],columns=list_of_lists[0]).to_csv('log_matrix.csv',sep='\t')
