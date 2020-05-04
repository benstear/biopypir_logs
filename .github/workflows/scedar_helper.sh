#!/bin/bash


if [  "$1" = "LINT" ]; then
  
  pylint scedar --exit-zero --reports=y >  pylint-report.txt
  pylintscore=$(awk '$0 ~ /Your code/ || $0 ~ /Global/ {print}' pylint-report.txt \
  | cut -d'/' -f1 | rev | cut -d' ' -f1 | rev)
  echo "::set-output name=pylint-score::$pylintscore"

elif [ "$1" = "TEST" ]; then    # "tests/"

  echo "::set-output name=pytest_score::False"
  pytest_cov=$(pytest "tests/" -ra --mpl-generate-path=tests/baseline_images \
  --color=yes --cov-config .coveragerc --cov-branch --cov="scedar" \
  --ignore=tests/test_cluster/test_mirac_large_data.py --ignore=tests/test_eda/ | \
  awk -F"\t" '/TOTAL/ {print $0}' | grep -o '[^ ]*%') 
  echo $pytest_cov
  pytestscore=${pytest_cov%\%}
  echo "::set-output name=pytest_score::$pytestscore"
  echo $pytestscore

elif [ "$1" = "BUILD" ]; then
  echo "::set-output name=build_output::False"  
  python setup.py build
  pytestcheck=$"True"
  echo "::set-output name=build_output::True"  
  
elif [ "$1" = "GATHER" ]; then
   
   jq -n --arg repo $2 \
         --arg pyversion $3 \
         --arg os $4 \
         --arg run_id $5  \
         --arg pylintscore $6 \
         --arg pytestscore $7 \
         --arg license $8 \
         --arg pip $9 \
        '{    Github_Repo : "\($repo)",
              Python_version : "\($pyversion)", 
              OS            : "\($os)",
              Run_ID        : "\($run_id)",
              Pylint_score : "\($pylintscore)",
              Pytest_score :  "\($pytestscore)",
              License_check : "\($license)",
              PIP           :  "\($pip)"
          }' > biopypir-"$4"-py"$3".json
          
  echo "biopypir file: " 
  cat $(biopypir-"$4"-py"$3".json)
  #2> gather_errors.txt  
  
elif [ "$1" = "EVAL" ]; then
  
  # GET job workflow information w API
  (curl -X GET -s https://api.github.com/repos/"$2"/actions/runs/"$3"/jobs) > API.json

  job_count=$(cat API.json |  jq ".total_count")
  
  j=$(($job_count-2)) # dont want last job (job2) included, and its 0-indexed, so - 2
  echo "jobcount: $j (0 - indexed)"
  
  linux_array=()
  mac_array=()

  for ((i=0;i<=$j;i++)); do 
     job_status=$(cat API.json | jq ".jobs[$i].conclusion")
     step_status=$(cat API.json | jq ".jobs[$i].steps[].conclusion")
    
     if  [[ "$job_status" =~ .*"success".* ]] && [[ ! "${step_status[@]}" =~ "failure" ]] ; then
      #&&  [[ ! "${step_status[@]}" =~ "skipped" ]] ; then
        
        # Get job name,  ie (3.6, ubuntu-latest) current each parallel job
        name=$(cat API.json |  jq ".jobs[$i].name" | cut -d "(" -f2 | cut -d ")" -f1)
        
        # Split $name into py version and OS  
        api_pyvers=$(echo $name | cut -d "," -f1)
        api_os=$(echo $name | rev | cut -d ' ' -f1 | rev)
        
        # Add passing python versions to their respective OS array
        if [[ "$api_os"  =~  .*"ubuntu".* ]]; then linux_arr+=("$api_pyvers")
        elif [[ "$api_os"  =~  .*"mac".* ]]; then  mac_arr+=("$api_pyvers")
        fi
        
     fi
     #exit 1; echo "One or more steps were skipped or failed in job " $(cat API.json | jq ".jobs[$i].name")
  done
  echo "Linux array: ${linux_arr[*]}"
  echo "Mac array: ${mac_arr[*]}"
  
  date=$(cat API.json | jq ".jobs[0].completed_at"); date_slice=${date:1:10}; echo $date_slice
  pylint_score_ave=0.00; pytest_score_ave=0.00
  
  for file in "$(pwd)/parallel_runs"/*/*; do
    pylint_score=$(cat "$file" | jq ".Pylint_score"); pylint_score="${pylint_score:1:4}"
    pylint_score_cum=$(awk "BEGIN {print $pylint_score_cum + $pylint_score}")
    
    pytest_score=$(cat "$file" | jq ".Pytest_score"); pytest_score="${pytest_score:1:2}"
    pytest_score_cum=$(awk "BEGIN {print $pytest_score_cum + $pytest_score}")
  done

   k="$(($j+1))"  # FIX
   pylint_score_final=$(bc -l <<< "scale=2; $pylint_score_cum/$k")
   pytest_score_final=$(bc -l <<< "scale=2; $pytest_score_cum/$k")
   
   echo "pytest final: $pytest_score_final"
   echo "lint final: $pylint_score_final"
   
   echo '-----------past finals------------------'
   (jq -n --arg lint_score "$pylint_score_final" --arg coverage_score "$pytest_score_final" \
          --arg date "$date_slice"  --arg linux "${linux_arr[*]}" --arg mac "${mac_arr[*]}" \
           '{ Pylint_score  :  $lint_score,  
              Pytest_score  :  $coverage_score,
              Date          :  $date,
              Ubuntu        : $linux,
              Mac          : $mac }' ) > scores.json
               
  #mkdir just_runs
  #find /parallel_runs -type f -exec mv --backup=numbered -t /just_runs {} +
  #ls just_runs
  cat scores.json
  a=$(ls parallel_runs/ | head -1)
  echo $(cat scores.json) $(cat parallel_runs/$a/biopypir-*.json) | jq -s add > final.json
  
  cat final.json | jq 'del(.OS, .Python_version)'  > final.json

  echo '-----edited final json------'
  cat final.json
  
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
  
  
  #curl -X POST -H "Content-Type: application/json" --data @final.json http://587f4908.ngrok.io/biopypir
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
  
  
fi 

