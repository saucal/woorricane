#!/bin/bash
INSTALL=()
if [ -z "$(which curl)" ]; then
  INSTALL+=("curl")
fi

if [ -z "$(which jq)" ]; then
  INSTALL+=("jq")
fi

if [ -z "$(which php)" ]; then
  INSTALL+=("php")
fi

if [ -n "${INSTALL[*]}" ]; then
  apt-get update && apt-get -y install "${INSTALL[@]}"
fi

CART="cart"
CHECKOUT="checkout"

POSITIONAL=()
while [[ $# -gt 0 ]]; do
  key="$1"

  case $key in
    --url)
    URL="$2"
    shift # past argument
    shift # past value
    ;;
    --cart)
    CART="$2"
    shift # past argument
    shift # past value
    ;;
    --checkout)
    CHECKOUT="$2"
    shift # past argument
    shift # past value
    ;;
    --product)
    PRODUCT_ID="$2"
    shift # past argument
    shift # past value
    ;;
    *)    # unknown option
    POSITIONAL+=("$1") # save it in an array for later
    shift # past argument
    ;;
  esac
done
set -- "${POSITIONAL[@]}" # restore positional parameters

export PRODUCT_ID
URL="${URL%/}"
URL="${URL#/}"
CART="${CART%/}"
CART="${CART#/}"
CHECKOUT="${CHECKOUT%/}"
CHECKOUT="${CHECKOUT#/}"
export HOME_URL="${URL}"
export AJAX_ADD_TO_CART_URL="${URL}/?wc-ajax=add_to_cart"
export CART_URL="${URL}/${CART}/"
export CHECKOUT_URL="${URL}/${CHECKOUT}/"
export AJAX_CHECKOUT_URL="${URL}/?wc-ajax=checkout"

CHILD_PROCS=()

step="$2"
if [ -z "${step}" ]; then
  step="1"
fi
max="$1"
if [ -z "${max}" ]; then
  max="100"
fi

SLEEP="$(printf '%.5f\n' "$(echo "scale=5; (${step} * 60) / ${max}" | bc )")"
rate="$(printf '%d\n' "$(echo "1 / ${SLEEP}" | bc )")"

MAX_USERS="${max}"
USERS="0"
LAUNCHED_PIPE=$(mktemp)
export FINISHED_PIPE
FINISHED_PIPE=$(mktemp)
export STEPS_PIPE
STEPS_PIPE=$(mktemp)
rm -rf "$STEPS_PIPE"
mkdir -p "$STEPS_PIPE/started"
mkdir -p "$STEPS_PIPE/finished"
mkdir -p "$STEPS_PIPE/max-concurrent"
mkdir -p "$STEPS_PIPE/statuses"

function step_active() {
  STEP=$1
  FILE="$STEPS_PIPE/started/$STEP"
  if [ ! -f "$FILE" ]; then
    echo 0;
    return;
  fi

  LAUNCHED=$(wc -c < "$FILE")
  LAUNCHED=$((LAUNCHED))
  FINISHED=0
  if [ -f "$STEPS_PIPE/finished/$STEP" ]; then
    FINISHED=$(wc -c < "$STEPS_PIPE/finished/$STEP")
    FINISHED=$((FINISHED))
  fi
  echo $((LAUNCHED - FINISHED));
}

export -f step_active

function step_max() {
  STEP=$1
  CURRENT_ACTIVE=$2
  local MAX=0 
  FILE="$STEPS_PIPE/max-concurrent/$STEP"
  if [ -f "$FILE" ]; then
    MAX=$(cat "$FILE")
  fi
  
  if [ $CURRENT_ACTIVE -gt $MAX ]; then
    echo $CURRENT_ACTIVE > "$FILE"
    echo $CURRENT_ACTIVE
  else
    echo $MAX
  fi
}

export -f step_max

function monitor() {
  local STEP

  local STATUS_CODE
  local STATUS_FILE
  local STATUS_AMOUNT
  local STATUS_JSON
  local STEP_ACTIVE
  local STEP_JSON

  local TOTAL_ACTIVE=0

  STEP_JSON="{}"
  if [ -n "$(ls -A "$STEPS_PIPE/started")" ]; then
    for entry in "$STEPS_PIPE/started"/*; do
      STEP="$(basename "$entry")"

      STATUS_JSON="{}"
      if [ -d "$STEPS_PIPE/statuses/$STEP" ] && [ -n "$(ls -A "$STEPS_PIPE/statuses/$STEP")" ]; then
        for STATUS_FILE in "$STEPS_PIPE/statuses/$STEP"/*; do
          STATUS_CODE="$(basename "$STATUS_FILE")"
          STATUS_AMOUNT=$(wc -c < "$STATUS_FILE")
          STATUS_AMOUNT=$((STATUS_AMOUNT))
          STATUS_JSON=$(echo "$STATUS_JSON" | jq -rc ". += {\"$STATUS_CODE\": $STATUS_AMOUNT}")
        done
      fi

      STEP_ACTIVE=$(step_active "$STEP")
      STEP_MAX=$(step_max "$STEP" "$STEP_ACTIVE")
      TOTAL_ACTIVE=$((TOTAL_ACTIVE + STEP_ACTIVE))
      STEP_JSON=$(echo "$STEP_JSON" | jq --arg step "$STEP" --argjson max "$STEP_MAX" --argjson active "$STEP_ACTIVE" --argjson statuses "$STATUS_JSON" -rc '. += {($step): {"active": $active,"max-concurrent": $max, "statuses": ($statuses)}}')
    done
  fi

  # Function to draw the table based on data
  draw_table() {
    tput civis    # Hide cursor
    tput cup 4 0  # Move cursor to top-left
    tput el       # Clear to end of line
    echo "Total Active: $TOTAL_ACTIVE"
    echo ""
    tput el       # Clear to end of line
    while IFS= read -r step_key; do
      local row_data=$(echo "$STEP_JSON" | jq --arg step "$step_key" -rc '.[$step]')
      echo "$step_key - $row_data";
      tput el       # Clear to end of line
      continue;
      while IFS= read -r key; do
        local cell=$(echo "$row_data" | jq -rc ".$key")
        printf "%-15s" "$cell"
      done < <(echo "$row_data" | jq -r 'keys_unsorted[]')
      printf "\n"
    done < <(echo "$STEP_JSON" | jq -r 'keys_unsorted[]')
    tput cnorm    # Show cursor
  }

  draw_table
}

# Record the start time
start_time=$(date +%s.%N)

function launch_monitor() {
  (
    clear;
    echo "Ramp up: $step minutes"
    echo "Rate: $rate calls added / second"
    echo "Max: $max total users"
    while true; do
      sleep 0.1;
      monitor;
      if [ -f "$STEPS_PIPE/monitor_exit" ]; then
        sleep 0.5;
        monitor;
        break;
      fi
    done;
  ) &
  MONITOR_PROC=$!
}

function kill_childs() {
  for i in ${CHILD_PROCS[@]}; do
    kill -9 "$i" 2>/dev/null
  done
  kill -15 "${MONITOR_PROC}" 2>/dev/null 1>/dev/null
  exit 1
}

function graceful_exit() {
  # Record the end time
  end_time=$(date +%s.%N)
  elapsed_time=$(echo "scale=0;$end_time - $start_time" | bc)
  iterations_per_second=$(echo "scale=3;$USERS / $elapsed_time" | bc)

  touch "$STEPS_PIPE/monitor_exit"
  wait

  echo ""
  echo "Script execution time: $elapsed_time seconds. Iterations per second: $iterations_per_second"
}

function woorricane_api() {
  curl -o /dev/null -sSL \
    --connect-timeout 400 \
    --max-time 400 \
    --retry 0 "$HOME_URL/?woorricane_control&action=$1&$1=$2"
}

trap "kill_childs" SIGINT

trap "graceful_exit" EXIT

LOG_PATH="$PWD/logs"

echo "--- Cleaning up"
rm -rf "$LOG_PATH"
rm -f curl-step-*.log

# Lock On Checkout to simulate race
woorricane_api "cleanup" || exit 1

echo "--- Preparing product"
woorricane_api "prepare_product" "$PRODUCT_ID" || exit 1

echo "--- Launching process"
launch_monitor

export CURRENT_THREAD
while true; do
  USERS=$(( USERS + 1 ));
  CURRENT_THREAD="$USERS"
  bash "thread.sh" & # 2>/dev/null 1>/dev/null &
  CHILD_PROCS+=("$!")
  echo -n '0' >> "${LAUNCHED_PIPE}"
  sleep "${SLEEP}"
  LIMIT=$(( USERS >= MAX_USERS ));
  if [ $LIMIT == "1" ]; then
    break;
  fi
done

wait "${CHILD_PROCS[@]}"
