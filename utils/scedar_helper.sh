#!/bin/bash

# This script was written to help the biopypir github actions workflow  

if [ "$1" = "SET ENV" ]; then
  echo '############################'
  #printenv
  echo '############################'
  echo $PACKAGE
  echo '############################'

  curl -L -o env_vars.json https://raw.githubusercontent.com/benstear/biopypir_logs/master/utils/package_params.json
  #cat env_vars.json | jq .$PACKAGE | jq .OWNER
  
  export OWNER=$(cat env_vars.json | jq .$PACKAGE | jq .OWNER)
  export test_suite=$(cat env_vars.json | jq .$PACKAGE | jq .test_suite)
  export tests_dir=$(cat env_vars.json | jq .$PACKAGE | jq .tests_dir)
  export ignore_tests=$(cat env_vars.json | jq .$PACKAGE | jq .ignore_tests)
  export ignore_lint=$(cat env_vars.json | jq .$PACKAGE | jq .ignore_lint)
  export py-vers=$(cat env_vars.json | jq .$PACKAGE | jq .python_version)
  export workflow_os=$(cat env_vars.json | jq .$PACKAGE | jq .os)

elif [  "$1" = "LINT" ]; then

  #if [[ "$api_os"  =~  .*"ubuntu".* ]] || [[ "$"  =~  .*"mac".* ]]; # if windows, use windows shell  
  
  #--disable=biopypir_utils.sh   # ignore_warnings=
  pylintscore=$(pylint $PACKAGE --exit-zero --disable=C0123,W0611,C0411 --ignore biopypir_utils.sh --reports=y | awk '$0 ~ /Your code/ || $0 ~ /Global/ {print}'\
  | cut -d'/' -f1 | rev | cut -d' ' -f1 | rev)
  
 # pylint $PACKAGE  --disable=C0123,W0611,C0411 --ignore biopypir_utils.sh --exit-zero --reports=y >  pylint-report.txt
  #pylintscore=$(awk '$0 ~ /Your code/ || $0 ~ /Global/ {print}' pylint-report.txt \
  #| cut -d'/' -f1 | rev | cut -d' ' -f1 | rev)
  echo "::set-output name=pylint-score::$pylintscore"
  echo $pylintscore 

elif [ "$1" = "TEST" ]; then  
  
  if [[ "$test_suite" == 'pytest' ]]; then
    echo "::set-output name=pytest_score::False"
    pytest_cov=$(pytest "$test_dir" -ra --color=yes --cov-config .coveragerc --cov-branch --cov=$PACKAGE | \
    awk -F"\t" '/TOTAL/ {print $0}' | grep -o '[^ ]*%') 
    pytestscore=${pytest_cov%\%}
    echo "::set-output name=pytest_score::$pytestscore"; echo "Pytest Coverage: $pytestscore"
  else  echo "::set-output name=pytest_score::0"; echo 'pytest not enabled for this package'
  fi

elif [ "$1" = "BUILD" ]; then
  echo "::set-output name=build_output::False"  
  python setup.py build
  #pytestcheck=$"True"
  echo "::set-output name=build_output::True"  
  
elif [ "$1" = "GATHER" ]; then
   
   jq -n  --arg pyversion $2 \
          --arg os $3 \
          --arg pylintscore $4 \
          --arg pytestscore $5 \
        '{    Python_version : "\($pyversion)", 
              OS            : "\($os)",
              Pylint_score : "\($pylintscore)",
              Pytest_score :  "\($pytestscore)" }' > biopypir-"$3"-py"$2".json
      # --arg license $6 \
      # --arg pip $7 \
      #    License_check : "\($license)",
      #    PIP           :  "\($pip)"    
                                         
elif [ "$1" = "EVALUATE" ]; then

  echo "::set-output name=run_status::True"
  echo "::set-env name=run_status::True"
  
  if [[ ! "$(ls -A parallel_runs)" ]]; then 
    echo "No runs succeded, exiting eval step..."
    echo '{ RUN_STATUS: "FAIL" }' > RUN_STATUS.json
    echo "::set-output name=run_status::False"   
    exit 1
  fi

  (curl -X GET -s https://api.github.com/repos/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID/jobs) > API.json

  job_count=$(cat API.json |  jq ".total_count")
  echo "raw job count: $job_count"
  j=$(($job_count-2)) # dont want last job (job2) included, and its 0-indexed, so do - 2
  echo "adjusted jobcount: $j (0 indexed)"
  
  linux_array=(); linux_vs=()
  mac_array=();  mac_vs=()
  windows_array=(); windows_vs=()
  
  for ((i=0;i<=$j;i++)); do 
     job_status=$(cat API.json | jq ".jobs[$i].conclusion")
     step_status=$(cat API.json | jq ".jobs[$i].steps[].conclusion")
    
     if  [[ "$job_status" =~ .*"success".* ]] && [[ ! "${step_status[@]}" =~ "failure" ]] ; then
       
       # Get job name,  ie (3.6, ubuntu-latest) of parallel job, split into OS string & py version string
        name=$(cat API.json |  jq ".jobs[$i].name" | cut -d "(" -f2 | cut -d ")" -f1)
        api_pyvers=$(echo $name | cut -d "," -f1); 
        api_os=$(echo $name | rev | cut -d ' ' -f1 | rev)
        
        # Add passing python versions to their respective OS array
        if [[ "$api_os"  =~  .*"ubuntu".* ]]; then linux_arr+=("$api_pyvers"); linux_vs+=("$api_os")
        elif [[ "$api_os"  =~  .*"mac".* ]]; then  mac_arr+=("$api_pyvers"); mac_vs+=("$api_os")
        elif [[ "$api_os"  =~  .*"windows".* ]]; then windows_arr+=("$api_pyvers"); windows_vs+=("$api_os")
        fi
     fi  #exit 1; echo "One or more steps failed in job " $(cat API.json | jq ".jobs[$i].name")
  done
  
  # Remove duplicate OS versions from each list
  linux_unq=($(echo "${linux_vs[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
  mac_unq=($(echo "${mac_vs[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
  windows_unq=($(echo "${windows_vs[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
  
  pylint_score_ave=0.00; pytest_score_ave=0.00
  
  # Get pylint and pytest scores from each of the parallel runs
  echo 'pylint/pytest scores'
  for file in "$(pwd)/parallel_runs"/*/*.json; do
    
    pylint_score=$(cat "$file" | jq ".Pylint_score"); pylint_score="${pylint_score:1:4}"; 
    echo "pylint_score: $pylint_score"
    pylint_score_cum=$(awk "BEGIN {print $pylint_score_cum + $pylint_score}")
    
    pytest_score=$(cat "$file" | jq ".Pytest_score"); pytest_score=$(echo "$pytest_score" | tr -d '"'); 
    echo "pytest_score: $pytest_score"
    pytest_score_cum=$(awk "BEGIN {print $pytest_score_cum + $pytest_score}")
  done
   
   echo "cumulative pytest score: $pytest_score_cum"
   
   # Calculate pylint and pytest scores average
   k="$(($j+1))" ; echo "k = $k"
   pylint_score_final=$(bc -l <<< "scale=2; $pylint_score_cum/$k")
   pytest_score_final=$(bc -l <<< "scale=2; $pytest_score_cum/$k")  
   
   if [[ ! "$test_suite" == 'None' ]]; then pytest_score_final=null; fi
   
   date=$(cat API.json | jq ".jobs[0].completed_at") ;date_slice=${date:1:10}; echo $date; echo $date_slice
   
   jq -n --arg full_date "$date_slice" \
         --arg lint_score "$pylint_score_final" \
         --arg coverage_score "$pytest_score_final" \
         --arg linux "${linux_arr[*]}" --arg linux_vers "${linux_unq[*]}" \
         --arg mac "${mac_arr[*]}" --arg mac_vers "${mac_unq[*]}" \
         --arg windows "${windows_arr[*]}" --arg windows_vers "${windows_unq[*]}" \
           '{ Date          :  $full_date,
              Pylint_score  :  $lint_score,  
              Pytest_score  :  $coverage_score,
              Pip           : "True",
              License       : "True",
              Build         : "True",
              Linux         : $linux,
              Mac           : $mac,
              Windows       : $windows,
              Linux_versions: $linux_vers,
              Mac_versions: $mac_vers,
              Windows_versions: $windows_vers }'  > scores_and_matrix.json
               
  a=$(ls parallel_runs/ | head -1)
  
  echo 'scores and matrix:'
  cat scores_and_matrix.json
  
  echo  'parallel run:'
  cat parallel_runs/$a/biopypir-*.json
  
  echo $(cat scores_and_matrix.json) $(cat parallel_runs/$a/biopypir-*.json) | \
  jq -s add | jq 'del(.OS, .Python_version)' > eval.json
  
  #echo  'eval.json'
  #cat eval.json
  
   # ================= GET BADGE STATUS ======================== #
   LICENSE=$(cat eval.json | jq ".License")
   BUILD=$(cat eval.json | jq ".Build")
   PIP=$(cat eval.json | jq ".Pip")
   LINT_SCORE=$(cat eval.json | jq ".Pylint_score")   # move into other cmd
   COVERAGE_SCORE=$(cat eval.json | jq ".Pytest_score")
   badge='NONE'
   
   COVERAGE_SCORE=$(sed -e 's/^"//' -e 's/"$//' <<<"$COVERAGE_SCORE") # Remove quotes
   LINT_SCORE=$(sed -e 's/^"//' -e 's/"$//' <<<"$LINT_SCORE") # Remove quotes
   #temp="${opt%\"}"; temp="${temp#\"}"; echo "$temp"
  # switch order of badge logic and jq add of above json files, if any passed, test_pass: TRUE, put in  failed?
  
  if [ "$LICENSE" ] && [ "$BUILD" ] && [ "PIP" ]; then 
    badge='BRONZE'; Hex_color=0x9c5221; 
  else 
    badge='null';Hex_color=0xffffff; 
  fi
  
  if  (( $(echo "$LINT_SCORE > 6.0" |bc -l) ))  && [ $COVERAGE_SCORE -gt 40 ]; then 
    badge='GOLD';  Hex_color=0xd4af37
  elif (( $(echo "$LINT_SCORE > 3.0" |bc -l) )) && [ $COVERAGE_SCORE -gt 20 ] ; then
    badge='SILVER';  Hex_color=0xb5b5bd
  fi
  
  jq -n --arg badge "$badge" --arg hex_color $Hex_color \
  '{BADGE : $badge, badge_color: $hex_color}' > badge.json; 
  
  jq -s add eval.json badge.json  > eval_2.json
  
  #cat eval_2.json
  
elif [ "$1" = "STATISTICS" ]; then
     
    curl https://api.github.com/repos/"$OWNER"/"$PACKAGE" | jq "{Owner_Repo: .full_name, 
      Package: .name, Description: .description, date_created: .created_at, last_commit: .pushed_at, forks: .forks, watchers: 
      .subscribers_count, stars: .stargazers_count, contributors: .contributors_url,
      homepage_url: .homepage, has_wiki: .has_wiki, open_issues: .open_issues_count,
      has_downloads: .has_downloads}" > stats.json

      jq -n --arg github_event "$GITHUB_EVENT_NAME" --arg run_id $GITHUB_RUN_ID \
      '{ Github_event_name: $github_event,Run_ID: $run_id }' > run_info.json
      
      jq -s add stats.json run_info.json  > stats_2.json
            
      if [ ! "$run_status" ]; then
        jq -s add stats_2.json RUN_STATUS.json > "$PACKAGE"_"$GITHUB_RUN_ID".json; rm RUN_STATUS.json
        echo "::set-env name=biopypir_workflow_status::FAIL"
      else
        jq -s add stats_2.json eval_2.json > "$PACKAGE"_"$GITHUB_RUN_ID".json
        echo "::set-env name=biopypir_workflow_status::SUCCESS"      
      fi
      
elif [ "$1" = "CLEAN UP" ]; then

     rm eval.json eval_2.json stats.json stats_2.json badge.json run_info.json \
     scores_and_matrix.json API.json biopypir_utils.sh package_params.json
     rm -r parallel_runs

     
     mv logs/"$PACKAGE"*.json archived_logs
     
     #for file in "$(pwd)"/logs/*.json; do
     #   if [[ file  =~  .*"$PACKAGE".*  ]]; then
     #     echo file; mv file archived_logs
     #   fi
     # done
     
     mv "$PACKAGE"_"$GITHUB_RUN_ID".json logs/ 
     
     pip install --upgrade pip 
     python3 -m pip install pandas numpy tabulate
     python3 utils/process_logs.py
    
fi 
