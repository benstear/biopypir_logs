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
import pandas as pd

#import tabulate as tb

import glob

logs_path = "logs/*.json"
all_logs = glob.glob(logs_path) 


print(len(all_logs))

# Only read logs from new_logs folder, process them, and move them into archive_logs

# Read in all logs, check cache of logs and get whats new

'''

# Only read in logs created within time frame ie one week
for filename in glob.glob(os.path.join("logs/", '*.json')):
    if os.path.getmtime(filename) < time.time() - 24 * 60 * 60:  # 24h ago
        continue  # skip the old file


'''



#table = pd.read_csv('biopypir_matrix.md')

