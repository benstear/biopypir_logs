OWNER=$(sed -e 's/^"//' -e 's/"$//' <<<"$OWNER")
    
    curl https://api.github.com/repos/"$OWNER"/"$PACKAGE" | jq "{Owner_Repo: .full_name, 
      Package: .name, Description: .description, date_created: .created_at, last_commit: .pushed_at, forks: .forks, watchers: 
      .subscribers_count, stars: .stargazers_count,
      homepage_url: .homepage, has_wiki: .has_wiki, open_issues: .open_issues_count,
      has_downloads: .has_downloads}" > stats.json

      # get names of contributors
      curl https://api.github.com/repos/"$OWNER"/"$PACKAGE"/contributors | jq ".[].login"  > contrib_logins.txt
      tr -d '"' <contrib_logins.txt > contributors.txt # delete quotes from file
      sed -i -e  's#^#https://github.com/#' contributors.txt # add github url to login names
      contributors_spc=$(tr '\n' ' ' < contributors.txt) # replace \n with ' '
      #cntrbtrs=$(paste -sd, contributors.txt) # add commas
      n_cntrbtrs="$(wc -l contributors.txt |  cut -d ' ' -f1)" 

      # specific OS version
      # date added to biopypir
      # license type

      jq -n --arg github_event "$GITHUB_EVENT_NAME" --arg run_id "$GITHUB_RUN_ID" --arg contributors "$contributors_spc" --arg num_contributors "$n_cntrbtrs" \
      '{ Github_event_name: $github_event, Run_ID: $run_id, contributors: $contributors, num_contributors: $num_contributors}' > run_info.json

      jq -s add stats.json run_info.json  > stats_2.json
      
      if [ ! "$run_status" ]; then
        echo 'run_status = "$run_status"'
        jq -s add stats_2.json RUN_STATUS.json > "$PACKAGE"_"$GITHUB_RUN_ID".json; 
        echo "::set-env name=biopypir_workflow_status::FAIL"
      else
        echo 'run_status = "$run_status"'        
        jq -s add stats_2.json  eval_2.json > "$PACKAGE"_"$GITHUB_RUN_ID".json # RUN_STATUS.json
        #echo "empty log" > "$PACKAGE"_"$GITHUB_RUN_ID".json
        echo "::set-env name=biopypir_workflow_status::SUCCESS"      
      fi     
      
elif [ "$1" = "CLEAN UP" ]; then
    
     echo 'Starting Clean Up...\n\n'
     pwd
     ls -A
     echo '-------------------------'
     ls logs/
     
     # Remove all files we dont want to push to the biopypir logs repository
     
     rm eval.json eval_2.json stats.json stats_2.json badge.json run_info.json \
     scores_and_matrix.json API.json biopypir_utils.sh env_vars.json RUN_STATUS.json contrib_logins.txt contributors.txt
     rm -r parallel_runs

     mv logs/"$PACKAGE"*.json archived_logs
     
     #for file in "$(pwd)"/logs/*.json; do
     #   if [[ file  =~  .*"$PACKAGE".*  ]]; then
     #     echo file; mv file archived_logs
     #   fi
     # done
     echo '---------------------------------'
     ls logs/
     echo '---------------------------------'
     cat "$PACKAGE"_"$GITHUB_RUN_ID".json
     
     
     
     # check if size of file is 0 (aka empty)
     #if [ -s "$PACKAGE"_"$GITHUB_RUN_ID".json ]; then echo 'Log File is Empty!'; exit 1;
     #else mv "$PACKAGE"_"$GITHUB_RUN_ID".json logs/  
     #fi
     mv "$PACKAGE"_"$GITHUB_RUN_ID".json logs/  
     
     pip install --upgrade pip 
     python3 -m pip install pandas numpy tabulate
     python3 utils/process_logs.py
