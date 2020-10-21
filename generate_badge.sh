 (curl -X GET -s https://api.github.com/repos/biopypir_logs/actions/runs/$GITHUB_RUN_ID/jobs) > jobs.json
 
 #$(cat badge_artifact.json |  jq ".BADGE") 
 # must change .jobs[3] to be last job in the workflow (ie .jobs[-1] for cases where there are more than 3 jobs)
 
 badge_color=$(cat jobs.json | jq .jobs[3].steps[5].name);
 echo $badge_color
 
 
 
 
 
