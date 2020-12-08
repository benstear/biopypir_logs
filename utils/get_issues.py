#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Created on Tue Dec  8 14:08:21 2020
@author: stearb
"""

#import json
#import pandas as pd
#import numpy as np
import datetime
import requests
import sys
#import os


#print('Number of arguments:', len(sys.argv), 'arguments.')
#print('Argument List:', str(sys.argv[1]))


#issues_url = os.path.join('https://api.github.com/repos/', sys.argv[1], '/issues')

issues_url = 'https://api.github.com/repos/' + sys.argv[1] + '/issues'

#print(issues_url)
#issues_url = 'https://api.github.com/repos/manubot/manubot/issues'

res = requests.get(issues_url)#,headers=headers)
issues_obj = res.json()

total_num_issues = len(issues_obj)

open_issues = []
closed_issues = []

for i in issues_obj:
    #print(i.keys())
    created_at = datetime.datetime.strptime(i['created_at'], "%Y-%m-%dT%H:%M:%SZ")
    updated_at = datetime.datetime.strptime(i['created_at'], "%Y-%m-%dT%H:%M:%SZ")
    response_time =  updated_at - created_at
    #print(i['created_at'],i['updated_at'])
    #print(type(created_at),type(updated_at))
    #print(response_time)
    if i['state'] == 'open':
        open_issues.append((i['number'],i['title']))
    elif i['state'] == 'closed':
        closed_issues.append((i['number'],i['title']))    
    else:
        print(i['state'])
        
        
os.environ["NUM_ISSUES"] = len(issues_obj)
