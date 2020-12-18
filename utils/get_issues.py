#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Created on Tue Dec  8 14:08:21 2020
@author: stearb
"""

import json
import numpy as np
import datetime
import requests
import sys
import os

#print('Number of arguments:', len(sys.argv), 'arguments.')
#print('Argument List:', str(sys.argv[1]))
#issues_url = os.path.join('https://api.github.com/repos/', sys.argv[1], '/issues')


def find_issues(name_repo):
    
    try:    
        repo_res = requests.get('https://api.github.com/repos/' + name_repo)
        repo_obj = repo_res.json()
        num_open_issues = repo_obj['open_issues_count']
 
    except requests.exceptions.RequestException as e:  
        raise SystemExit(e)
    
    if repo_obj['has_issues']:
        
        try:
            res = requests.get('https://api.github.com/repos/' + name_repo + '/issues')
            issues_obj = res.json()
            response_timeLs = [] #open_issues = closed_issues = []

            for i in issues_obj:
                created_at = datetime.datetime.strptime(i['created_at'], "%Y-%m-%dT%H:%M:%SZ")
                updated_at = datetime.datetime.strptime(i['updated_at'], "%Y-%m-%dT%H:%M:%SZ")
                response_time =  updated_at - created_at
                response_timeLs.append(response_time.days)
               # if i['state'] == 'open':  open_issues.append((i['number'],i['title']))
               # elif i['state'] == 'closed':   closed_issues.append((i['number'],i['title']))    
               # else:    print(i['state'])
            
            return_dict = {"NUM_ISSUES": str(len(issues_obj)), "NUM_OPEN_ISSUES":  str(num_open_issues),"AVE_RES" : str(np.round(sum(response_timeLs)/len(response_timeLs),2) ) }
            print(json.dumps(return_dict))  # This outputs the variable in the bash environment
            
        except requests.exceptions.RequestException as e:  
            raise SystemExit(e)
    else:
            return_dict = {"NUM_ISSUES": "0",  "NUM_OPEN_ISSUES":  str(num_open_issues),  "AVE_RES" : "NA"}
            print(json.dumps(return_dict)) # This outputs the variable in the bash environment
   




#def format_text(text):
#    print(text)



if __name__ == "__main__":
    if sys.argv[1] == 'ISSUES':
        name_repo =  sys.argv[1]
        find_issues(name_repo)
        
    elif sys.argv[1] == 'format':
        

    #print(f"::set-output name=myOUTPUT::{my_output}")
    #bashCommand = "MAGICVAR="42""
    #process = subprocess.Popen(bashCommand.split(), stdout=subprocess.PIPE)



