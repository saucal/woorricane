#!/bin/bash
INSTALL=()
if [ -z "$(which curl)" ]; then
  INSTALL+=("curl")
fi

if [ -z "$(which php)" ]; then
  INSTALL+=("php7.4-cli")
fi

if [ -n "${INSTALL[*]}" ]; then
  apt-get update && apt-get -y install "${INSTALL[@]}"
fi

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

function monitor() {
  local LAUNCHED
  local FINISHED
  local ACTIVE
  local STEP

  LAUNCHED=$(wc -c < "${LAUNCHED_PIPE}")
  LAUNCHED=$((LAUNCHED))
  FINISHED=$(wc -c < "${FINISHED_PIPE}")
  FINISHED=$((FINISHED))
  ACTIVE=$((LAUNCHED - FINISHED));

  STEP_STATUS=""
  if [ -n "$(ls -A "$STEPS_PIPE/started")" ]; then
    for entry in "$STEPS_PIPE/started"/*; do
      STEP="$(basename "$entry")"
      STEP_STATUS="${STEP_STATUS} - $STEP:$(step_active "$STEP")"
    done
  fi
  STEP_STATUS="${STEP_STATUS#" - "}"
  if [ -n "$STEP_STATUS" ]; then
      STEP_STATUS=" | ${STEP_STATUS}"
  fi

  echo -ne "\033[2K\r"
  echo -ne "Launched: ${LAUNCHED}/${MAX_USERS} - Active: ${ACTIVE}${STEP_STATUS}"
}

( while true; do sleep 0.1; monitor; done; ) &
MONITOR_PROC=$!

function kill_childs() {
  for i in ${CHILD_PROCS[@]}; do
    kill -9 "$i" 2>/dev/null
  done
  kill -15 "${MONITOR_PROC}" 2>/dev/null 1>/dev/null
  echo -en "\n"
  exit 1
}

function woorricane_api() {
  curl -o /dev/null -sSL \
    --connect-timeout 400 \
    --max-time 400 \
    --retry 0 "$HOME_URL/?woorricane_control&action=$1&$1=$2" 2>&1
}

trap "kill_childs" SIGINT EXIT

SLEEP="$(php -r "echo number_format(( ( ${step} * 60 ) / ${max} ), 5, '.', '' );")"
rate="$(php -r "echo intval( 1 / ${SLEEP} );")"

echo "Ramp up: $step minutes"
echo "Rate: $rate calls added / second"
echo "Max: $max total users"

LOG_PATH="$PWD/logs"
rm -rf "$LOG_PATH"

# Lock On Checkout to simulate race
woorricane_api "cleanup"
woorricane_api "prepare_product" "$PRODUCT_ID"

rm -f curl-step-*.log
export CURRENT_THREAD

# Record the start time
start_time=$(date +%s.%N)

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

# Record the end time
end_time=$(date +%s.%N)
elapsed_time=$(echo "$end_time - $start_time" | bc)
iterations_per_second=$(echo "scale=3;$USERS / $elapsed_time" | bc)

echo ""
echo ""
echo "Script execution time: $elapsed_time seconds. Iterations per second: $iterations_per_second"

kill_childs

monitor

echo ""
