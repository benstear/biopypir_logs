#!/bin/bash

# This script was written to do the heavy lifting for the biopypir github actions workflow: benstear/biopypir_logs/.github/workflows/main_workflow.yml 

if [ "$1" = "SET ENV" ]; then

  curl -L -o env_vars.json https://raw.githubusercontent.com/benstear/biopypir_logs/master/utils/package_params.json
  #cat env_vars.json | jq .$PACKAGE | jq .OWNER
  OWNER=$(cat env_vars.json | jq .$PACKAGE | jq .OWNER)   
  #export OWNER=$(cat env_vars.json | jq .$PACKAGE | jq .OWNER)
  echo "::set-env name=OWNER::$OWNER"
  
  TEST_SUITE=$(cat env_vars.json | jq .$PACKAGE | jq .test_suite); 
  TEST_SUITE=$(sed -e 's/^"//' -e 's/"$//' <<<"$TEST_SUITE") # Remove quotes
  #export TEST_SUITE=$(cat env_vars.json | jq .$PACKAGE | jq .test_suite)
  echo "::set-env name=TEST_SUITE::$TEST_SUITE"
  
  TEST_DIR=$(cat env_vars.json | jq .$PACKAGE | jq .tests_dir); 
  TEST_DIR=$(sed -e 's/^"//' -e 's/"$//' <<<"$TEST_DIR") # Remove quotes

  #export TEST_DIR=$(cat env_vars.json | jq .$PACKAGE | jq .tests_dir)
  echo "::set-env name=TEST_DIR::$TEST_DIR"
  
  export IGNORE_TESTS=$(cat env_vars.json | jq .$PACKAGE | jq .ignore_tests)
  echo "::set-env name=IGNORE_TESTS::$(cat env_vars.json | jq .$PACKAGE | jq .ignore_tests)"
  
  export IGNORE_LINT=$(cat env_vars.json | jq .$PACKAGE | jq .ignore_lint)
  echo "::set-env name=IGNORE_LINT::$(cat env_vars.json | jq .$PACKAGE | jq .ignore_lint)"
  
  #export PY_VERS=$(cat env_vars.json | jq .$PACKAGE | jq .python_version)
  #export WORKFLOW_OS=$(cat env_vars.json | jq .$PACKAGE | jq .os)
  echo  $TEST_SUITE
  echo $TEST_DIR
elif [  "$1" = "SET ENV DISPATCH" ]; then
  printenv
  #${{ github.event.environment_vars.PACKAGE }}
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
  
  if [[ "$TEST_SUITE" =~ .*"pytest".*  ]]; then
    echo "::set-output name=pytest_score::False"
    pytest_cov=$(pytest "$TEST_DIR" -ra --color=yes --cov-config .coveragerc --cov-branch --cov=$PACKAGE | \
    awk -F"\t" '/TOTAL/ {print $0}' | grep -o '[^ ]*%') 
    pytestscore=${pytest_cov%\%}
    echo "::set-output name=pytest_score::$pytestscore"; echo "Pytest Coverage: $pytestscore"
  elif [ ! "$TEST_SUITE" = "pytest"  ]; then
    echo "::set-output name=pytest_score::0"; echo 'pytest not enabled for this package'
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
  
  # Check to see if any runs succeeded
  if [[ ! "$(ls -A parallel_runs)" ]]; then 
    echo "No runs succeded, exiting eval step..."
    echo '{ RUN_STATUS: "FAIL" }' > RUN_STATUS.json
    echo "::set-output name=run_status::False"   
    exit 1
  elif [[ "$(ls -A parallel_runs)" ]]; then    # put the rest of evaluate under this else statement
    echo '{ RUN_STATUS: "SUCCESS" }' > RUN_STATUS.json
  fi

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
  
  # Remove any duplicate OS versions from each list
  linux_unq=($(echo "${linux_vs[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
  mac_unq=($(echo "${mac_vs[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
  windows_unq=($(echo "${windows_vs[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
  
  pylint_score_ave=0.00; pytest_score_ave=0.00  #  Initialize 'average score' variables
  
  # Get pylint and pytest scores from each of the parallel runs
  for file in "$(pwd)/parallel_runs"/*/*.json; do
    pylint_score=$(cat "$file" | jq ".Pylint_score"); pylint_score="${pylint_score:1:4}"; 
    pylint_score_cum=$(awk "BEGIN {print $pylint_score_cum + $pylint_score}")
 
    pytest_score=$(cat "$file" | jq ".Pytest_score"); pytest_score=$(echo "$pytest_score" | tr -d '"'); 
    pytest_score_cum=$(awk "BEGIN {print $pytest_score_cum + $pytest_score}")
  done   
   
   
   # Calculate pylint and pytest average scores
   k="$(($j+1))" ; 
   pylint_score_final=$(bc -l <<< "scale=2; $pylint_score_cum/$k")
   pytest_score_final=$(bc -l <<< "scale=2; $pytest_score_cum/$k")  
   
   if [[ ! "$TEST_SUITE" == 'None' ]]; then pytest_score_final=$'NA'; fi  # fix
   
   date=$(cat API.json | jq ".jobs[0].completed_at");  date_clip=$(sed -e 's/^"//' -e 's/"$//' <<<"$date")
    
    IFS=','; # make OS arrays comma seperated
    if [ ! -z "{$linux_arr[*]}" ]; then linux_arr_=$(echo "${linux_arr[*]}"); else linux_arr_=$('NA'); fi
    if [ ! -z "{$mac_arr[*]}" ]; then mac_arr_=$(echo "${mac_arr[*]}");  else mac_arr_=$('NA'); fi
    if [ ! -z "{$windows_arr[*]}" ]; then windows_arr_=$(echo "${windows_arr[*]}");  else windows_arr_=$('NA'); fi
    IFS=$' \t\n';
    
   jq -n --arg Workflow_Run_Date "$date_clip" \
      --arg linux_vers "${linux_unq[*]}" \
     --arg mac "${mac_arr_[*]}" \
     --arg mac_vers "${mac_unq[*]}" \
     --arg windows "${windows_arr_[*]}" \
     --arg windows_vers "${windows_unq[*]}" \
     --arg coverage_score "$pytest_score_final" \
      --arg linux "${linux_arr_[*]}" \
      --arg lint_score "$pylint_score_final"\
       '{ Workflow_Run_Date :  $Workflow_Run_Date,
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


   
    cat scores_and_matrix.json | jq 'del(.OS, .Python_version)' > eval.json
  
   # ================= GET BADGE STATUS ======================== #
   LICENSE=$(cat eval.json | jq ".License")
   BUILD=$(cat eval.json | jq ".Build")
   PIP=$(cat eval.json | jq ".Pip")
   LINT_SCORE=$(cat eval.json | jq ".Pylint_score")   #
   COVERAGE_SCORE=$(cat eval.json | jq ".Pytest_score")
   badge='NONE'
   

    
fi 