#!/bin/bash

# This script was written to help the biopypir github actions workflow   

if [  "$1" = "LINT" ]; then

  #if [[ "$api_os"  =~  .*"ubuntu".* ]] || [[ "$"  =~  .*"mac".* ]]; # if windows, use windows shell
  
  pylint $PACKAGE --exit-zero --reports=y --ignore biopypir_utils.sh >  pylint-report.txt
  pylintscore=$(awk '$0 ~ /Your code/ || $0 ~ /Global/ {print}' pylint-report.txt \
  | cut -d'/' -f1 | rev | cut -d' ' -f1 | rev)
  echo "::set-output name=pylint-score::$pylintscore"
  printenv 

elif [ "$1" = "TEST" ]; then  
  echo "$test_suite"
  #if "$test_suite" = 'pytest'; then
    echo "::set-output name=pytest_score::False"
    pytest_cov=$(pytest tests/ -ra --color=yes --cov-config .coveragerc --cov-branch --cov=$PACKAGE | \
    awk -F"\t" '/TOTAL/ {print $0}' | grep -o '[^ ]*%') 
    echo $pytest_cov
    pytestscore=${pytest_cov%\%}
    echo "::set-output name=pytest_score::$pytestscore"
    echo "Pytest Coverage: $pytestscore"
    # --mpl-generate-path=tests/baseline_images  --ignore=tests/test_cluster/test_mirac_large_data.py --ignore=tests/test_eda/ 
  #else  echo "::set-output name=pytest_score::null"; echo 'didnt run'
  #fi

elif [ "$1" = "BUILD" ]; then
  echo "::set-output name=build_output::False"  
  python setup.py build
  pytestcheck=$"True"
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
                                         
  #echo "biopypir file: \\n" 
  #cat biopypir-"$3"-py"$2".json
  
elif [ "$1" = "EVAL" ]; then
  
  # GET job_1 workflow info;  $2 = owner/repo;  $3 = RUN_ID
  (curl -X GET -s https://api.github.com/repos/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID/jobs) > API.json

  job_count=$(cat API.json |  jq ".total_count")
  #echo "raw job count: $job_count"
  j=$(($job_count-2)) # dont want last job (job2) included, and its 0-indexed, so do - 2
  #echo "adjusted jobcount: $j (0 indexed)"
  
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
  
  for file in "$(pwd)/parallel_runs"/*/*.json; do
    
    pylint_score=$(cat "$file" | jq ".Pylint_score"); pylint_score="${pylint_score:1:4}"
    pylint_score_cum=$(awk "BEGIN {print $pylint_score_cum + $pylint_score}")
    
    pytest_score=$(cat "$file" | jq ".Pytest_score"); pytest_score=$(echo "$pytest_score" | tr -d '"')
    pytest_score_cum=$(awk "BEGIN {print $pytest_score_cum + $pytest_score}")
  done

   k="$(($j+1))" 
   pylint_score_final=$(bc -l <<< "scale=2; $pylint_score_cum/$k")
   pytest_score_final=$(bc -l <<< "scale=2; $pytest_score_cum/$k")         # cast to int
   
   date=$(cat API.json | jq ".jobs[0].completed_at") ;date_slice=${date:1:10}; #echo $date
   
   jq -n --arg date "$date_slice" \
         --arg lint_score "$pylint_score_final" \
         --arg coverage_score "$pytest_score_final" \
         --arg linux "${linux_arr[*]}" --arg linux_vers "${linux_unq[*]}" \
         --arg mac "${mac_arr[*]}" --arg mac_vers "${mac_unq[*]}" \
         --arg windows "${windows_arr[*]}" --arg windows_vers "${windows_unq[*]}" \
         --arg github_event "$GITHUB_EVENT_NAME" \
           '{ Date          :  $date,
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
              Windows_versions: $windows_vers,
              Github_event_name: $github_event }'  > scores_and_matrix.json
               
  a=$(ls parallel_runs/ | head -1)
  echo $(cat scores_and_matrix.json) $(cat parallel_runs/$a/biopypir-*.json) | \
  jq -s add | jq 'del(.OS, .Python_version)' > final.json

   # ================= GET BADGE STATUS ======================== #
   LICENSE=$(cat final.json | jq ".License")
   BUILD=$(cat final.json | jq ".Build")
   PIP=$(cat final.json | jq ".Pip")
   LINT_SCORE=$(cat final.json | jq ".Pylint_score")
   COVERAGE_SCORE=$(cat final.json | jq ".Pytest_score")
   badge='NONE'
   
   COVERAGE_SCORE=$(sed -e 's/^"//' -e 's/"$//' <<<"$COVERAGE_SCORE") # Remove quotes
   LINT_SCORE=$(sed -e 's/^"//' -e 's/"$//' <<<"$LINT_SCORE") # Remove quotes
   #temp="${opt%\"}"; temp="${temp#\"}"; echo "$temp"
  # switch order of badge logic and jq add of above json files, if any passed, test_pass: TRUE, put in  failed?
  
  if [ "$LICENSE" ] && [ "$BUILD" ] && [ "PIP" ]; then badge='BRONZE'; Hex_color=1; else badge='null'; 
  fi
  
  #(( $(echo "$num1 > $num2" |bc -l) ))
  if  (( $(echo "$LINT_SCORE > 6.0" |bc -l) ))  && [ $COVERAGE_SCORE -gt 40 ]; then 
    badge='GOLD'; echo $badge; Hex_color=1
  elif (( $(echo "$LINT_SCORE > 3.0" |bc -l) )) && [ $COVERAGE_SCORE -gt 20 ] ; then
    badge='SILVER'; echo $badge; Hex_color=5
  fi
  
  jq -n --arg badge "$badge" '{BADGE : $badge}' > badge.json
  
  cat final.json
  echo '------------'
  cat scores_and_matrix.json
  echo '------------'
  cat badge.json
  
  echo $(cat scores_and_matrix.json) $(cat badge.json) | jq -s add > cat scores_and_matrix.json

  
  elif [ "$1" = "STATS" ]; then
  #date_slice=${date:1:10}
  
  curl https://api.github.com/repos/"$REPO_OWNER"/"$PACKAGE" | jq "{Owner_Repo: .full_name, 
      Package: .name, Description: .description,
      date_created: .created_at, last_commit: .pushed_at, forks: .forks, watchers: 
      .subscribers_count, stars: .stargazers_count, contributors: .contributors_url,
      homepage_url: .homepage, has_wiki: .has_wiki, open_issues: .open_issues_count,
      has_downloads: .has_downloads}" > stats.json
      
      last_update=$(cat stats.json |  jq ".last_commit")
      created_at=$(cat stats.json |  jq ".date_created")
     
      created_at=${created_at:1:10}; echo $created_at;
      last_update=${last_update:1:10}; echo $last_update; 
      
      jq -n --arg badge "$badge" '{BADGE : $badge}' > badge.json
      
      jq -n --arg  last_commit  "$last_update" '{last_updated : $last_update}' > update.json
      cat update.json
      
      #cat stats.json | jq -n --arg badge "$badge" '{BADGE : $badge}' > badge.json
      echo $(cat stats.json) $(cat scores_and_matrix.json) | jq -s add > $GITHUB_RUN_ID.json
      mv $GITHUB_RUN_ID.json logs/
      
  # sizs xkb
fi 
