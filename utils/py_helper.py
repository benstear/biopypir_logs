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


def get_issues(name_repo):
    
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
   



def get_contributors(name_repo):
     cont_response = requests.get(f'https://api.github.com/repos/{name_repo}/contributors')
     cont_obj = cont_response.json()
    
     contributors = []
     for i in cont_obj:
            contributors.append(i['login'])

     logins = [i.strip(' "') for i in contributors]
     formatted_urls = ['https://github.com/' + i for i  in logins]
        
     return_dict = {"contributor_names": logins, "contributors_url": formatted_urls,"num_contributors" : len(logins) }
     print(json.dumps(return_dict)) 
            

            
            
            
            
            
            
            
def process_logs():

    logs_path = "logs/*.json"
    all_logs = glob.glob(logs_path)  # load all logs from logs/ directory. Only the most recent 
                                     # workflow run results for each package will be there. 
    print('Total Logs found: '+str(len(all_logs)))

    list_of_lists = []
    for i in range(0,len(all_logs)):
        try:
            data = json.load(open(all_logs[i]))
        except json.decoder.JSONDecodeError as e:  
            raise SystemExit(e)

        if i==0: list_of_lists.append(list(data.keys())) # if it's the first pass of the loop, save the keys to use as
                                                         #  headers for the log_matrix.csv and biopypir_matrix.md files
        list_of_lists.append(list(data.values()))        # otherwise append each packages results to list_of_lists

    # if you add more, or get rid of columns (fields in .json file), you will get an error, 
    # when the script tries to read the old logs in because they will have the old number of columns.
    # Delete all old logs in logs/ and rerun new workflow.
    df =pd.DataFrame(list_of_lists[1:],columns=list_of_lists[0]) 

    reordered_cols= ['Package','BADGE','Owner_Repo','Description','Workflow_Run_Date','date_created','last_commit',
                         'forks','watchers','stars','homepage_url','has_wiki','open_issues',
                         'has_downloads','Run_ID','Pylint_score','Pytest_score','Pip','Pip_url','License','Build','Linux',
                         'Mac','Windows','Linux_versions','Mac_versions','Windows_versions','contributor_names','contributor_url',
                     'num_contributors','Github_event_name', 'Num_Issues', 'Num_Open_Issues', 'Average_Response_Time' ]

    df = df.reindex(reordered_cols, axis=1)
    df.to_csv('log_matrix.csv',index=False,sep='\t')

    # Create and save markdown table of packages
    md_table =  df.to_markdown()
    with open('biopypir_matrix.md', 'w') as f:
        f.write(md_table)

            

            
               
if __name__ == "__main__":
    if sys.argv[1] == 'ISSUES':
        get_issues(sys.argv[2])
        
    elif sys.argv[1] == 'CONTRIBUTORS':
        get_contributors(sys.argv[2])

    elif  sys.argv[1] == 'PROCESS LOGS':
        process_logs()
        
# Try to set env vars from this script


