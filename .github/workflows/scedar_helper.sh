#!/bin/bash

# This is a script 

if [  "$1" = "LINT" ]; then
  
  pylint $PACKAGE --exit-zero --reports=y >  pylint-report.txt
  pylintscore=$(awk '$0 ~ /Your code/ || $0 ~ /Global/ {print}' pylint-report.txt \
  | cut -d'/' -f1 | rev | cut -d' ' -f1 | rev)
  echo "::set-output name=pylint-score::$pylintscore"
  echo "::set-env name=env_pylint_score::$pylintscore"
  echo $env_pylint_score
  printenv 

elif [ "$1" = "TEST" ]; then  

  echo "::set-output name=pytest_score::False"
  pytest_cov=$(pytest "tests/" -ra --mpl-generate-path=tests/baseline_images \
  --color=yes --cov-config .coveragerc --cov-branch --cov=$PACKAGE \
  --ignore=tests/test_cluster/test_mirac_large_data.py --ignore=tests/test_eda/ | \
  awk -F"\t" '/TOTAL/ {print $0}' | grep -o '[^ ]*%') 
  pytestscore=${pytest_cov%\%}
  echo "::set-output name=pytest_score::$pytestscore"
  echo "Pytest Coverage: $pytestscore"
  
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
          --arg license $6 \
          --arg pip $7 \
        '{    Python_version : "\($pyversion)", 
              OS            : "\($os)",
              Pylint_score : "\($pylintscore)",
              Pytest_score :  "\($pytestscore)",
              License_check : "\($license)",
              PIP           :  "\($pip)"      }' > biopypir-"$3"-py"$2".json
  #echo "biopypir file: \\n" 
  #cat biopypir-"$3"-py"$2".json
  
elif [ "$1" = "EVAL" ]; then
  
  # GET job_1 workflow info;  $2 = owner/repo;  $3 = RUN_ID
  (curl -X GET -s https://api.github.com/repos/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID/jobs) > API.json

  job_count=$(cat API.json |  jq ".total_count")
  #echo "raw job count: $job_count"
  j=$(($job_count-2)) # dont want last job (job2) included, and its 0-indexed, so do - 2
  echo "adjusted jobcount: $j (0 indexed)"
  
  linux_array=()
  mac_array=()

  for ((i=0;i<=$j;i++)); do 
     job_status=$(cat API.json | jq ".jobs[$i].conclusion")
     step_status=$(cat API.json | jq ".jobs[$i].steps[].conclusion")
    
     if  [[ "$job_status" =~ .*"success".* ]] && [[ ! "${step_status[@]}" =~ "failure" ]] ; then
      #&&  [[ ! "${step_status[@]}" =~ "skipped" ]] ; then
        # Get job name,  ie (3.6, ubuntu-latest) of parallel job, split into OS string & py version string
        name=$(cat API.json |  jq ".jobs[$i].name" | cut -d "(" -f2 | cut -d ")" -f1)
        api_pyvers=$(echo $name | cut -d "," -f1); api_os=$(echo $name | rev | cut -d ' ' -f1 | rev)
        
        # Add passing python versions to their respective OS array
        if [[ "$api_os"  =~  .*"ubuntu".* ]]; then linux_arr+=("$api_pyvers")
        elif [[ "$api_os"  =~  .*"mac".* ]]; then  mac_arr+=("$api_pyvers")
        fi
        
     fi  #exit 1; echo "One or more steps failed in job " $(cat API.json | jq ".jobs[$i].name")
  done
  
  #echo "Linux array: ${linux_arr[*]}"; echo "Mac array: ${mac_arr[*]}"
  pylint_score_ave=0.00; pytest_score_ave=0.00
  
  for file in "$(pwd)/parallel_runs"/*/*.json; do
    
    pylint_score=$(cat "$file" | jq ".Pylint_score"); pylint_score="${pylint_score:1:4}"
    #echo $pylint_score; #echo "pylint_score length = ${#pylint_score}"
    pylint_score_cum=$(awk "BEGIN {print $pylint_score_cum + $pylint_score}")
    
    pytest_score=$(cat "$file" | jq ".Pytest_score"); pytest_score=$(echo "$pytest_score" | tr -d '"')
    #echo $pytest_score; #echo "pytest_score length = ${#pytest_score}"
    pytest_score_cum=$(awk "BEGIN {print $pytest_score_cum + $pytest_score}")
    
  done

   k="$(($j+1))" 
   pylint_score_final=$(bc -l <<< "scale=2; $pylint_score_cum/$k")
   pytest_score_final=$(bc -l <<< "scale=2; $pytest_score_cum/$k")
   
   echo "pytest final: $pytest_score_final"; echo "lint final: $pylint_score_final"
   
   date=$(cat API.json | jq ".jobs[-1].completed_at"); date_slice=${date:1:10}; echo "DATE: $date"
   echo 'full date = $date'
   
   echo '-----------past finals------------------'
   (jq -n --arg lint_score "$pylint_score_final" \
          --arg coverage_score "$pytest_score_final" \
          --arg date "$date_slice"  \
          --arg linux "${linux_arr[*]}" \
          --arg mac "${mac_arr[*]}" \
           '{ Pylint_score :  $lint_score,  
              Pytest_score  :  $coverage_score,
              Current_date   :  $date,
              Pip           : "True",
              License      : "True",
              Linux       : $linux,
              Mac        : $mac,
              Github_event_name: $GITHUB_EVENT_NAME}' ) > scores.json
               
  a=$(ls parallel_runs/ | head -1)
  #echo $(cat scores.json) $(cat parallel_runs/$a/biopypir-*.json) | jq -s add | jq 'del(.OS, .Python_version)' > final.json
  cat scores.json
  echo '----------'
  cat parallel_runs/$a/biopypir-*.json
  #cat final.json | jq 'del(.OS, .Python_version)'  > final.json

  #echo '------artifacts name and id--------'
  #curl -X GET -s "https://api.github.com/repos/benstear/scedar/actions/runs/90141152/artifacts" | jq ".id" > art.json
  #cat art.json
  #echo '-----artifact IDs------'
  #URL="https://api.github.com/repos/benstear/scedar/actions/artifacts"
  #echo $(curl -X GET $URL |jq '.artifacts[].id') > art_ids.txt
  #cat art_ids.txt
  #echo '----delete artifacts-----'
  #curl -X DELETE -u "admin:$secrets.GITHUB_TOKEN" "https://api.github.com/repos/benstear/scedar/actions/artifacts/*"
  #echo "done"
   # ================= GET BADGE STATUS ======================== #
  
   #LICENSE=$(cat final.json | jq ".License_check")
   #TESTS=$(cat final.json | jq ".Pytest_status")
   #BUILD=$(cat final.json | jq ".Build_status")
   #COVERAGE_SCORE=$(cat final.json | jq ".Pytest_score")
   #COVERAGE_SCORE="44"
   #badge='NONE'
   
  #if [[ "$LICENSE" ]] && [[ "$TESTS" ]] && [[ "$BUILD" ]] && \
  #   [[ "$((COVERAGE_SCORE))" -gt 40 ]] ; then badge='BRONZE' fi
  #jq -n --arg badge "$badge" '{BADGE : $badge}' > badge.json
  #echo $(cat final.json) $(cat badge.json) | jq -s add > final.json
  
  
  elif [ "$1" = "STATS" ]; then
  
  curl https://api.github.com/repos/TaylorResearchLab/scedar | jq \   # deal with owner/repo hardcode
      "{Owner_Repo: .full_name, Package: .name, Description: .description,
      date_created: .created_at, last_commit: .pushed_at, forks: .forks, watchers: 
      .subscribers_count, stars: .stargazers_count, contributors: .contributors_url,
      homepage_url: .homepage, has_wiki: .has_wiki, open_issues: .open_issues_count,
      has_downloads: .has_downloads}" > stats.json
      
      echo $(cat stats.json) $(cat scores.json) | jq -s add > $GITHUB_RUN_ID.json
      mv $GITHUB_RUN_ID.json logs/
  # sizs xkb
fi 


