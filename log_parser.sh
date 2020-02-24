#!/bin/sh

lockfile=/tmp/lockfile
if ( set -o noclobber; echo "$$" > "$lockfile" ) 2> /dev/null;
then
  trap 'rm -f "$lockfile"; exit $?' INT TERM EXIT
    
    # arrays and variables
    ip_addr_arr_src=()
    ip_addr_arr_dst=()
    resp_code_arr=()
    ip_addr_src_string=
    ip_addr_sdt_string=
    num_of_errors=0
    email_body=
    NEWLINE=$'\n'
    log_file="$2"
    to_address="$3"


    if [ "$1" != "" ]; then
      offset=$1
    else
      offset=0
    fi

    # scripts starts to process log with the starting hour + offset*3600sec
    determine_checkpoint()
    {
      CHECKPOINT_UPPER=$((1565748000+3599*$offset))
      CHECKPOINT_LOWER=$((1565744400+3599*$offset))
      CHECKPOINT_UPPER_HUMAN="$(date -d @$CHECKPOINT_UPPER)"
      CHECKPOINT_LOWER_HUMAN="$(date -d @$CHECKPOINT_LOWER)"
    }

    # make ip_dest,ip_source, responce codes arrays
    make_stat()
    {
    # read file line by line
    while IFS= read -r line; do

      # get log record time
      log_time="$(echo $line | awk '{print $4}' | cut -b 2-21)"
      log_time="$(date -d "$(echo $log_time | sed -e 's,/,-,g' -e 's,:, ,')" +"%s")"
      #echo $log_time
      
	  if [[ log_time -gt $CHECKPOINT_LOWER ]] ; then
	    if [[ log_time -lt $CHECKPOINT_UPPER ]] ; then

              # extract source IP
              ip_addr_src="$(echo $line | awk '{print $1}')"
              ip_addr_src_arr+=($ip_addr_src)

              # extract destination IP
              ip_addr_dst="$(echo $line | sed -E 's/.+\s//')"
              ip_addr_dst_arr+=($ip_addr_dst)

              # extract responce code
              resp_code="$( echo $line | sed -E 's/[^\"]*\"[^\"]*\"\s//' | awk '{print $1}')"
              resp_code_arr+=($resp_code)

              # count number of errors (404 responce code)
              if  echo $line  | grep -q 404 ; then 
                num_of_errors=$((num_of_errors+1))
              fi
            else
              break
	    fi
	  fi 
    done < "$log_file"
    }

    # makes report csv from string
    make_csv_from_sorted_string()
    {
      SAVEIFS=$IFS
      IFS=$'\n'
      sorted_str=($1)
      IFS=$SAVEIFS

      for elem in "${sorted_str[@]}"
      do
        key="$(echo "$elem" | awk '{print $2}')"
        count="$(echo "$elem" | awk '{print $1}')"
        email_body+="$key,$count\n"
      done
    }

    determine_checkpoint
    email_body="\nTime range : "$CHECKPOINT_LOWER_HUMAN" - "$CHECKPOINT_UPPER_HUMAN"\n\n"
    make_stat

    email_body+="Destination IPs for the last hour:\n"
    ip_addr_src_sorted_str="$(echo "${ip_addr_src_arr[@]}" | tr ' ' '\n' | sort | uniq -c  | sort -bgr)"
    make_csv_from_sorted_string "$ip_addr_src_sorted_str"

    email_body+="\nSource IPs for the last hour:\n"
    ip_addr_src_sorted_dst="$(echo "${ip_addr_dst_arr[@]}" | tr ' ' '\n' | sort | uniq -c  | sort -bgr)"
    make_csv_from_sorted_string "$ip_addr_src_sorted_dst"

    email_body+="\nTop responce codes:\n"
    resp_code_sorted="$(echo "${resp_code_arr[@]}" | tr ' ' '\n' | sort | uniq -c  |  sort -bgr)"
    make_csv_from_sorted_string "$resp_code_sorted"

    email_body+="\nNumber of errors (404 responce codes): "
    email_body+="$num_of_errors\n"

    # uncomment for debug
    echo -e $email_body
    echo -e $email_body | mail -s "this is log stat" "$to_address"

  rm -f "$lockfile"
  trap - INT TERM EXIT
else
  echo "Failed to acquire lockfile: $lockfile"
  echo "Held by $(cat $lockfile)"
fi

