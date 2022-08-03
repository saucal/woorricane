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
export HOME_URL="${URL}"
export AJAX_ADD_TO_CART_URL="${URL}/?wc-ajax=add_to_cart"
export CART_URL="${URL}/${CART}"
export CHECKOUT_URL="${URL}/${CHECKOUT}"
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

function monitor() {
  local LAUNCHED

  LAUNCHED=$(cat "$LAUNCHED_PIPE")
  FINISHED=$(wc -c < "${FINISHED_PIPE}")
  FINISHED=$((FINISHED))
  ACTIVE=$((LAUNCHED - FINISHED));

  echo -ne "\033[2K\r"
  echo -ne "Launched: ${LAUNCHED}/${MAX_USERS} - Active: ${ACTIVE}"
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

trap "kill_childs" SIGINT EXIT

SLEEP="$(php -r "echo number_format(( ( ${step} * 60 ) / ${max} ), 5, '.', '' );")"
rate="$(php -r "echo intval( 1 / ${SLEEP} );")"

echo "Ramp up: $step minutes"
echo "Rate: $rate calls added / second"
echo "Max: $max total users"

rm -f curl-step-*.log
export CURRENT_THREAD
while true; do
  USERS=$(( USERS + 1 ));
  CURRENT_THREAD="$USERS"
  bash "thread.sh" & # 2>/dev/null 1>/dev/null &
  CHILD_PROCS+=("$!")
  echo "${USERS}" > "$LAUNCHED_PIPE"
  sleep "${SLEEP}"
  LIMIT=$(( USERS >= MAX_USERS ));
  if [ $LIMIT == "1" ]; then
    break;
  fi
done

wait "${CHILD_PROCS[@]}"
kill_childs

monitor

echo ""
