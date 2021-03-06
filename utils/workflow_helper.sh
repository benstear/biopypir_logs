#!/bin/bash

# This script was written to do the heavy lifting for the biopypir github actions workflow: benstear/biopypir_logs/.github/workflows/main_workflow.yml 

# TODO:
# get evironment variable setting worked out, which file to do it in?
# clean up alot of the formatting with python
# put in variable type checks



if [ "$1" = "SET ENV" ]; then
  curl -L -o env_vars.json https://raw.githubusercontent.com/benstear/biopypir_logs/master/utils/package_params.json
  
  OWNER=$(cat env_vars.json | jq .$PACKAGE | jq .OWNER)   
  echo "OWNER=$OWNER" >> $GITHUB_ENV
  
  TEST_SUITE=$(cat env_vars.json | jq .$PACKAGE | jq .test_suite); 
  TEST_SUITE=$(sed -e 's/^"//' -e 's/"$//' <<<"$TEST_SUITE") # Remove quotes
  echo "TEST_SUITE=TEST_SUITE" >> $GITHUB_ENV
  
  TEST_DIR=$(cat env_vars.json | jq .$PACKAGE | jq .tests_dir); 
  TEST_DIR=$(sed -e 's/^"//' -e 's/"$//' <<<"$TEST_DIR") # Remove quotes
  echo "TEST_DIR=$TEST_DIR" >> $GITHUB_ENV

  echo "IGNORE_TESTS=$(cat env_vars.json | jq .$PACKAGE | jq .ignore_tests)" >> $GITHUB_ENV
  
  echo "IGNORE_LINT=$(cat env_vars.json | jq .$PACKAGE | jq .ignore_lint)" >> $GITHUB_ENV

elif [  "$1" = "LINT" ]; then
  echo $PACKAGE
  #if [[ "$api_os"  =~  .*"ubuntu".* ]] || [[ "$"  =~  .*"mac".* ]]; # if windows, use windows shell  
  #--disable=biopypir_utils.sh   # ignore_warnings=
  pylintscore=$(pylint $PACKAGE --exit-zero --disable=C0123,W0611,C0411 --ignore biopypir_utils.sh --reports=y | awk '$0 ~ /Your code/ || $0 ~ /Global/ {print}'\
  | cut -d'/' -f1 | rev | cut -d' ' -f1 | rev)
  echo pylint score: $pylintscore
  
  #if [[ "$pylintscore" =~ .*"No module named".*  ]]; then echo "Pylint Error: Package Name not found"; exit 1; fi
  
 # pylint $PACKAGE  --disable=C0123,W0611,C0411 --ignore biopypir_utils.sh --exit-zero --reports=y >  pylint-report.txt
  #pylintscore=$(awk '$0 ~ /Your code/ || $0 ~ /Global/ {print}' pylint-report.txt \
  #| cut -d'/' -f1 | rev | cut -d' ' -f1 | rev)
 
  echo "::set-output name=pylint_score::$pylintscore"
  
  
  
elif [ "$1" = "TEST" ]; then  
  echo 'TEST_SUITE = ' "$test_suite" 
  
  if [[ "$test_suite" =~ .*"pytest".*  ]]; then
    echo "::set-output name=pytest_score::False"
    
    # Find test directory  and print it
    find ~ -type d -name "tests" -print
    
    pytest_cov=$(pytest "$TEST_DIR" -ra --color=yes --cov-config .coveragerc --cov-branch --cov=$PACKAGE | \
    awk -F"\t" '/TOTAL/ {print $0}' | grep -o '[^ ]*%') 
    pytestscore=${pytest_cov%\%}
    
    echo "::set-output name=pytest_score::$pytestscore"; 
    echo "Pytest Coverage: $pytest_score"
    
  elif [ ! "$test_suite" = "pytest"  ]; then
    pytestscore=0
    echo "::set-output name=pytest_score::$pytestscore"; 
    echo 'pytest not enabled for this package'
  fi

elif [ "$1" = "BUILD" ]; then
  echo "::set-output name=build_output::False"  
  python setup.py build
  echo "::set-output name=build_output::True"  
  
elif [ "$1" = "GATHER" ]; then
   
   #echo "$2";echo "$3"; echo "$4"; echo "$5"; echo "$6"; echo "$7"
   
   # Check if any variables are empty (indicating the result of one or more tests did not exit successfully)
   [ -z "$2" ] && echo "Python version variable is empty." && exit 1;
   [ -z "$3" ] && echo "OS variable is empty." && exit 1;
   [ -z "$4" ] && echo "Pylint score variable is empty." && exit 1;
   [ -z "$5" ] && echo "Pytest score variable is empty." && exit 1;
   [ -z "$6" ] && echo "PIP variable is empty." && exit 1;
   [ -z "$7" ] && echo "License variable is empty."  && exit 1;
   
   jq -n  --arg pyversion $2 \
          --arg os $3 \
          --arg pylintscore $4 \
          --arg pytestscore $5 \
           --arg pip $6 \
           --arg license $7 \
        '{    Python_version : "\($pyversion)", 
              OS            : "\($os)",
              Pylint_score : "\($pylintscore)",
              Pytest_score :  "\($pytestscore)",
               PIP           :  "\($pip)",
               License_check : "\($license)" }' > biopypir-"$3"-py"$2".json
 
 
 ###################################### 
 ########## JOB 2 FUNCTIONS ###########
 #####################################
elif [ "$1" = "EVALUATE" ]; then

  echo "::set-output name=run_status::True"
  echo "run_status=True" >> $GITHUB_ENV
  
  ############ Check to see if any runs succeeded #################
  if [[ ! "$(ls -A parallel_runs)" ]]; then 
    echo "No runs succeded, exiting eval step..."; echo '{ RUN_STATUS: "FAIL" }' > RUN_STATUS.json
    echo "::set-output name=run_status::False"; exit 1
  elif [[ "$(ls -A parallel_runs)" ]]; then    # put the rest of evaluate under this else statement
    echo '{ RUN_STATUS: "SUCCESS" }' > RUN_STATUS.json
  fi

  (curl -X GET -s https://api.github.com/repos/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID/jobs) > API.json
   #step_names=$(cat API.json | jq .jobs[0].steps[].name); #echo $step_names
  #n=10  #for ((i=0;i<=$n;i++)); do #   if [[ "${step_names[$i]}" =~ "Checkout" ]] ; then  #   PACKAGE="${step_names[$i]}";fi; done   #echo $(echo $PACKAGE |  cut -d' ' -f 1)    #if step_names is 1 long string, split by ' ' and get string after 'Checkout'
   
  package_and_owner=$(cat API.json | jq .jobs[0].steps[3].name); # get the step (step 3) that has the owner and repo as its name. automate this with regex in the line above this  one ^^^
  package_and_owner=$(sed -e 's/^"//' -e 's/"$//' <<<"$package_and_owner")
  PACKAGE=$(echo $package_and_owner |  cut -d' ' -f 3); 
  OWNER=$(echo $package_and_owner |  cut -d' ' -f 2)

  echo "OWNER=$OWNER" >> $GITHUB_ENV
  echo "PACKAGE=$PACKAGE" >> $GITHUB_ENV
  
  
  job_count=$(cat API.json |  jq ".total_count")  #echo "raw job count: $job_count"
  j=$(($job_count-2)) # dont want last job (job2) included, and its 0-indexed, so do - 2  #echo "adjusted jobcount: $j (0 indexed)"
  
  linux_array=(); linux_vs=(); mac_array=();  mac_vs=(); windows_array=(); windows_vs=()
  
  ############ Get Passing OS and Python Versions ####################
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


  ############ Remove duplicate OS versions from each list ############################
  linux_unq=($(echo "${linux_vs[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
  mac_unq=($(echo "${mac_vs[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
  windows_unq=($(echo "${windows_vs[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
  pylint_score_ave=0.00; pytest_score_ave=0.00  #  Initialize 'average score' variables
  
    ########## Get pip and license  from parallel_run  ####################
   for file in "$(pwd)/parallel_runs"/*/*.json; do
    pip_result=$(cat "$file" | jq ".PIP"); 
    license_result=$(cat "$file" | jq ".License_check");
    done
    
    pip_result=$(sed -e 's/^"//' -e 's/"$//' <<<"$pip_result")
    license_result=$(sed -e 's/^"//' -e 's/"$//' <<<"$license_result")

    if [ "$pip_result" ]; then     pip_url=$'https://pypi.org/project/'"$PACKAGE"'/'; echo 'yes pip'
    else pip_url == 'NA'; echo 'no pip'
    fi
    pip_url=$'https://pypi.org/project/'"$PACKAGE"'/'


  ######### Get pylint and pytest scores from each of the parallel runs ######################
  for file in "$(pwd)/parallel_runs"/*/*.json; do
    pylint_score=$(cat "$file" | jq ".Pylint_score"); pylint_score="${pylint_score:1:4}"; 
    pylint_score_cum=$(awk "BEGIN {print $pylint_score_cum + $pylint_score}")
 
    pytest_score=$(cat "$file" | jq ".Pytest_score"); pytest_score=$(echo "$pytest_score" | tr -d '"'); 
    pytest_score_cum=$(awk "BEGIN {print $pytest_score_cum + $pytest_score}")
  done   
   
   k="$(($j+1))" ;    # Calculate pylint and pytest average scores
   pylint_score_final=$(bc -l <<< "scale=2; $pylint_score_cum/$k"); pytest_score_final=$(bc -l <<< "scale=2; $pytest_score_cum/$k")  
   

  if [[ "$TEST_SUITE" == 'None' ]]; then pytest_score_final=$'NA'; fi  # fix
   
   date=$(cat API.json | jq ".jobs[0].completed_at");  date_clip=$(sed -e 's/^"//' -e 's/"$//' <<<"$date")
    
    IFS=','; # make OS arrays comma seperated
    if [ ! -z "{$linux_arr[*]}" ]; then linux_arr_=$(echo "${linux_arr[*]}"); else linux_arr_=$('NA'); fi
    if [ ! -z "{$mac_arr[*]}" ]; then mac_arr_=$(echo "${mac_arr[*]}");  else mac_arr_=$('NA'); fi
    if [ ! -z "{$windows_arr[*]}" ]; then windows_arr_=$(echo "${windows_arr[*]}");  else windows_arr_=$('NA'); fi
    IFS=$' \t\n';
    
     pip install --upgrade pip 
     pip install requests numpy pandas tabulate
     issues=$(python3 utils/py_helper.py "ISSUES" "$OWNER/$PACKAGE") 
     
     NUM_ISSUES=$(sed -e 's/^"//' -e 's/"$//' <<<$(echo $issues | jq '.NUM_ISSUES'))
     NUM_OPEN_ISSUES=$(sed -e 's/^"//' -e 's/"$//' <<<$(echo $issues | jq '.NUM_OPEN_ISSUES'))
     AVE_RES=$(sed -e 's/^"//' -e 's/"$//' <<<$(echo $issues | jq '.AVE_RES'))
     
     echo "NUM_ISSUES=$NUM_ISSUES" >> $GITHUB_ENV
     echo "NUM_OPEN_ISSUES=$NUM_OPEN_ISSUES" >> $GITHUB_ENV
     echo "AVE_RES=$AVE_RES" >> $GITHUB_ENV
    
   ######## Put Everything we just calculated (and formatted) into eval.json file ###################
   jq -n --arg Workflow_Run_Date "$date_clip" \
             --arg lint_score "$pylint_score_final" \
             --arg coverage_score "$pytest_score_final" \
             --arg PIP "$pip_result" \
             --arg LICENSE "$license_result" \
              --arg linux "${linux_arr_[*]}" \
              --arg mac "${mac_arr_[*]}" \
              --arg windows "${windows_arr_[*]}" \
              --arg linux_vers "${linux_unq[*]}" \
              --arg mac_vers "${mac_unq[*]}" \
              --arg windows_vers "${windows_unq[*]}" \
              --arg pip_url "$pip_url" \
              --argjson Num_Issues "$NUM_ISSUES" \
              --argjson Num_Open_Issues "$NUM_OPEN_ISSUES" \
              --argjson Average_Response_Time "$AVE_RES" '{  Workflow_Run_Date :  $Workflow_Run_Date,
                                                  Pylint_score  :  $lint_score,  
                                                Pytest_score  :  $coverage_score,
                                                Pip           : $PIP,   
                                                License       : $LICENSE,
                                                Build         : "True",
                                                Linux         : $linux,
                                                Mac           : $mac,
                                                Windows       : $windows,
                                                Linux_versions: $linux_vers,
                                                Mac_versions: $mac_vers,
                                                Windows_versions: $windows_vers,
                                                 Pip_url       : $pip_url,
                                                 Num_Issues:   $Num_Issues, 
                                                 Num_Open_Issues:  $Num_Open_Issues,
                                                 Average_Response_Time: $Average_Response_Time  }'  > eval.json

    cp  eval.json  eval.json.tmp && cat eval.json.tmp | jq 'del(.OS, .Python_version)' > eval.json && rm eval.json.tmp
    
    
elif [ "$1" = "BADGING" ]; then

   badge='NONE'
   badge='BRONZE'

#if  [[ $NUM_ISSUES != "0" ]]   && [[ $(echo $issues | jq '.AVE_RES') ]]
if [ "$NUM_ISSUES" -gt 0 ];  then echo 'nonzero'; fi


if [[ $pytest_score_final != "NA" ]]; then pytest_score_final=$(sed -e 's/^"//' -e 's/"$//' <<<$pytest_score_final); fi  # Remove quotes  if pytest_score_final is a number

  if [ "$license_result" ] && [ "$build_result" ] && [ "$pip_result" ]; then badge='BRONZE'; badge_color='#cd7f32'; echo 'BRONZE BADGE';
    #if [ $pytest_score_final != 'NA' ]; then
        if  (( $(echo "$pylint_score_final > 6.0" |bc -l) ))  && [ $pytest_score_final -gt 40 ]; then badge='GOLD';  badge_color='#FFD700'; echo 'SILVER BADGE';
        elif (( $(echo "$pylint_score_final > 3.0" |bc -l) )) && [ $pytest_score_final -gt 20 ]; then badge='SILVER'; badge_color='#C0C0C0'; echo 'GOLD BADGE';
        fi 
    #fi 
  fi
  
  echo '+++++++++++++++++++++++++++++++++++++'
  echo 'NUM_ISSUES: ' $NUM_ISSUES
  echo 'AVE_RES: ' '"$AVE_RES"
  echo 'pytest_score_final: ' $pytest_score_final
  echo 'license_result: ' $license_result
  echo 'build_result: ' $build_result
  echo 'pip_result: ' $pip_result
  echo 'pylint_score_final: ' $pylint_score_final
  echo '+++++++++++++++++++++++++++++++++++++'

  jq -n --arg badge "$badge" '{BADGE : $badge}' > badge.json;  
  cp  eval.json  eval.json.tmp && jq  -s add eval.json.tmp badge.json > eval.json && rm eval.json.tmp badge.json
  
  echo "BADGE=$badge" >> $GITHUB_ENV  
  
  #badge_color='#cd7f32' #bronze #badge_color='#C0C0C0'  # silver
  badge_color='#FFD700'  # gold  
  
  # Create Badge Endpoint 
  jq -n --arg biopypir_badge "$badge" --arg biopypir_name "BIOPYPIR" --arg badge_color "$badge_color" \
        --arg logo  "Auth0"  --arg logoColor "white"  --arg width 40 --arg style "for-the-badge" \
                         '{ schemaVersion: 1,
                              label: $biopypir_name,
                              message: $biopypir_badge,
                              color: $badge_color,
                              namedLogo: $logo,
                              logoWidth: $width,
                              logoColor: $logoColor,
                              style: $style,
                                }' >  "$PACKAGE"_badge_endpoint.json
                                
  mv  "$PACKAGE"_badge_endpoint.json badges



elif [ "$1" = "STATISTICS" ]; then


    curl https://api.github.com/repos/"$OWNER"/"$PACKAGE" | \
        jq "{Owner_Repo: .full_name, 
       Package: .name,
       Description: .description,
       date_created: .created_at, 
       last_commit: .pushed_at, 
       forks: .forks, 
       watchers: .subscribers_count, 
       stars: .stargazers_count,
       homepage_url: .homepage,
       has_wiki: .has_wiki, 
       open_issues: .open_issues_count,
       has_downloads: .has_downloads}" | \
          jq --arg github_event_name $GITHUB_EVENT_NAME \
             --arg run_id $GITHUB_RUN_ID '. + {github_event_name: $github_event_name, run_id:  $run_id }' > stats.json


    python3 utils/py_helper.py "CONTRIBUTORS" "$OWNER/$PACKAGE" > contributors.json
    
    cp  stats.json  stats.json.tmp && jq  -s add stats.json.tmp contributors.json > stats.json && rm stats.json.tmp contributors.json                         
     
      if [ ! "$run_status" ]; then
        #echo run_status = "$run_status"
        jq -s add stats.json RUN_STATUS.json > "$PACKAGE"_"$GITHUB_RUN_ID".json; 
        echo "biopypir_workflow_status=FAIL" >> $GITHUB_ENV
      else
        #echo run_status = "$run_status"        
        jq -s add stats.json  eval.json > "$PACKAGE"_"$GITHUB_RUN_ID".json # RUN_STATUS.json
        echo "biopypir_workflow_status=SUCCESS"   >> $GITHUB_ENV
      fi     
      
      
  
elif [ "$1" = "CLEAN UP" ]; then
   
     # Remove all files we dont want to push to the biopypir logs repository
     rm  eval.json stats.json API.json biopypir_utils.sh RUN_STATUS.json 
     rm -r parallel_runs      
     
     
      if ls logs/"$PACKAGE"*.json 1> /dev/null 2>&1; then   # just do mv logs/"$PACKAGE"*, 
      echo "files exist";  mv logs/"$PACKAGE"*.json archived_logs
      ls  logs/
      else 
      echo "files do not exist" 
      fi
      
     #for file in "$(pwd)"/logs/*.json; do
     #   if [[ file  =~  .*"$PACKAGE".*  ]]; then
     #     echo file; mv file archived_logs
     #   fi
     # done
     
     
     if [ $(cat "$PACKAGE"_"$GITHUB_RUN_ID".json | jq length) -eq 34 ]; then
     echo 'correct number of parameters.'
     fi
     
     if [ ! $(cat "$PACKAGE"_"$GITHUB_RUN_ID".json | jq length) -eq 34 ]; then
          echo 'Incorrect number of parameters, exiting...'; exit 1;
     fi
          
     mv "$PACKAGE"_"$GITHUB_RUN_ID".json logs/  
     
     #python3 -m pip install pandas numpy tabulate
     python3 utils/py_helper.py "PROCESS LOGS"
     
    
fi


        
      # get names of contributors
      #curl https://api.github.com/repos/"$OWNER"/"$PACKAGE"/contributors | jq ".[].login"  > contrib_logins.txt      
      #tr -d '"' <contrib_logins.txt > contributors.txt # delete quotes from file     
      #(tr '\n' ' ' < contributors.txt) > contributors2.txt  # replace \n with ' '
      #sed -e  's#^#https://github.com/#' contributors.txt > contributors_gh.txt    # add github url to login names
      #contributors_url=$(tr '\n' ' ' < contributors_gh.txt) # replace \n with ' '   #cntrbtrs=$(paste -sd, contributors.txt) # add commas
      #n_cntrbtrs="$(wc -l contributors.txt |  cut -d ' ' -f1)"  

      # "$(cat contributors2.txt)"
      #jq -n --arg github_event "$GITHUB_EVENT_NAME" \
      #      --arg run_id "$GITHUB_RUN_ID" \
      #      --arg contributors_url "${array[2]} ${array[3]}" \
      #      --arg num_contributors "${array[4]}" \
      #      --arg contributor_names "${array[0]} ${array[1]}" \
      #                                      '{ Github_event_name: $github_event,
      #                                          Run_ID: $run_id,
      #                                          contributor_names: $contributor_names, 
      #                                          contributor_url: $contributors_url,
      #                                          num_contributors: $num_contributors}' > run_info.json
          
