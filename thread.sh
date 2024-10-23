#!/bin/bash

LOG_PATH="$PWD/woorricane-logs/t-$CURRENT_THREAD"
rm -rf "$LOG_PATH"
mkdir -p "$LOG_PATH"

COOKIE_JAR=$(mktemp)

set -o history -o histexpand

LAST_REQ_FILE=$(mktemp)
LAST_REQ_TRACE=$(mktemp)
LAST_REQ_HEADERS=$(mktemp)
LAST_REQ_RESPONSE_HEADERS=$(mktemp)
LAST_REQ_FULL=$(mktemp)
LAST_REQ_STDERR=$(mktemp)
STEP=0

function run() {
  STEP=$(( STEP + 1 ))

  echo -n "0" >> "$STEPS_PIPE/started/$STEP"
  "$1" > "$LOG_PATH/curl-step-$STEP.log"
  RET_CODE="$?"
  echo -n "0" >> "$STEPS_PIPE/finished/$STEP"
  return "$RET_CODE"
}

get_time() {
  local DATA
  local key
  DATA=$1
  key=$2
  {
    echo "$DATA" | grep -oP "$key=\K[0-9.]+"
  } 2> /dev/null
}

get() {
  mkdir -p "$STEPS_PIPE/statuses/$STEP"
  mkdir -p "$STEPS_PIPE/times/$CURRENT_THREAD/$STEP"
  local DATA
  local status_code

  PARAMS=( --connect-timeout 400 --max-time 400 )
  if [ -n "$RESOLVED_IP" ]; then
    PARAMS+=( --resolve "$RESOLVED_IP" )
  fi

  DATA=$(curl -o "${LAST_REQ_FILE}" -c "${COOKIE_JAR}" -b "${COOKIE_JAR}" -sSL -D "${LAST_REQ_RESPONSE_HEADERS}" \
    "${PARAMS[@]}" \
    --write-out 'time_namelookup=%{time_namelookup}\ntime_connect=%{time_connect}\ntime_appconnect=%{time_appconnect}\ntime_pretransfer=%{time_pretransfer}\ntime_redirect=%{time_redirect}\ntime_starttransfer=%{time_starttransfer}\ntime_total=%{time_total}\n' \
    --trace-ascii "${LAST_REQ_TRACE}" \
    --retry 0 "$@" 2>"${LAST_REQ_STDERR}")

  HAS_ERR=$?
  if [ $HAS_ERR -eq 0 ]; then
    status_code=$(cat "$LAST_REQ_RESPONSE_HEADERS" | head -n 1 | awk '{print $2}')
  else
    status_code="999"
    {
      echo "Error: $HAS_ERR"
      echo "Status Code: $status_code"
      echo ""
      echo ""
      cat "$LAST_REQ_STDERR"
      echo ""
      echo ""
      cat "${LAST_REQ_TRACE}"
      echo ""
      echo ""
      echo "$DATA"
    } >> "$LAST_REQ_RESPONSE_HEADERS"
  fi

  # use grep to find times in $DATA
  get_time "$DATA" 'time_namelookup' >> "$STEPS_PIPE/times/$CURRENT_THREAD/$STEP/time_namelookup"
  get_time "$DATA" 'time_connect' >> "$STEPS_PIPE/times/$CURRENT_THREAD/$STEP/time_connect"
  get_time "$DATA" 'time_appconnect' >> "$STEPS_PIPE/times/$CURRENT_THREAD/$STEP/time_appconnect"
  get_time "$DATA" 'time_pretransfer' >> "$STEPS_PIPE/times/$CURRENT_THREAD/$STEP/time_pretransfer"
  get_time "$DATA" 'time_redirect' >> "$STEPS_PIPE/times/$CURRENT_THREAD/$STEP/time_redirect"
  get_time "$DATA" 'time_starttransfer' >> "$STEPS_PIPE/times/$CURRENT_THREAD/$STEP/time_starttransfer"
  get_time "$DATA" 'time_total' >> "$STEPS_PIPE/times/$CURRENT_THREAD/$STEP/time_total"

  {
    cat "${LAST_REQ_TRACE}" | awk '/=> Send header,/{flag=1; next} /== Info:/{flag=0} flag' | sed '/^=> Send data,.*$/d' | sed 's/^[[:xdigit:]]*: //g'
    echo ""
  } > "${LAST_REQ_HEADERS}"

  {
    cat "${LAST_REQ_HEADERS}"
    cat "${LAST_REQ_RESPONSE_HEADERS}"
    cat "${LAST_REQ_FILE}"
    echo ""
  } > "${LAST_REQ_FULL}"
  
  echo -n "0" >> "$STEPS_PIPE/statuses/$STEP/$status_code"
  
  cat "${LAST_REQ_FULL}"
  if [ "$status_code" != "200" ]; then
	return 1
  fi
  return $HAS_ERR
}

function step_1() {
  # home
  get "${HOME_URL}"

  HAS_ERR="$?"
  if [ $HAS_ERR -ne 0 ]; then
    return $HAS_ERR;
  fi
}

function step_2() {
  QTY="1"
  # add to cart
  get "${AJAX_ADD_TO_CART_URL}" \
    -X 'POST' \
    -H "Referer: ${HOME_URL}" \
    --data-raw "product_id=${PRODUCT_ID}&quantity=${QTY}"

  HAS_ERR="$?"
  if [ $HAS_ERR -ne 0 ]; then
    return $HAS_ERR;
  fi

  HAS_ERR=$(jq '.error' < "${LAST_REQ_FILE}")
  if [ "$HAS_ERR" != "null" ]; then
    return 1;
  fi
}

function step_3() {
  # cart page
  get "${CART_URL}"

  HAS_ERR="$?"
  if [ $HAS_ERR -ne 0 ]; then
    return $HAS_ERR;
  fi
}

function step_4() {
  # get nonces on the checkout page
  get "${CHECKOUT_URL}" \
    -H "Referer: ${CART_URL}"

  HAS_ERR="$?"
  if [ $HAS_ERR -ne 0 ]; then
    return $HAS_ERR;
  fi

  CHECKOUT_NONCE=$(grep -oP ' name="woocommerce-process-checkout-nonce" value="\K.+?(?=")' "${LAST_REQ_FILE}")
  CHECKOUT_REFERER=$(grep -oP ' name="_wp_http_referer" value="\K.+?(?=")' "${LAST_REQ_FILE}")
  if [ -z "$CHECKOUT_NONCE" ] || [ -z "$CHECKOUT_REFERER" ]; then
    return 1;
  fi
}

function step_5() {
  # checkout
  get "${AJAX_CHECKOUT_URL}" \
    -H "Referer: ${CHECKOUT_URL}" \
    --data-urlencode "woocommerce-process-checkout-nonce=${CHECKOUT_NONCE}" \
    --data-urlencode "_wp_http_referer=${CHECKOUT_REFERER}" \
    --data-raw "billing_first_name=Mai+K&billing_last_name=Love&billing_company=&billing_country=US&billing_address_1=4876++Hillcrest+Circle&billing_address_2=&billing_city=Crystal&billing_state=MN&billing_postcode=55429&billing_phone=218-404-4099&billing_email=bm0kig52zgp%40temporary-mail.net&order_comments=&payment_method=dummy"

  HAS_ERR="$?"
  if [ $HAS_ERR -ne 0 ]; then
    return $HAS_ERR;
  fi

  HAS_ERR=$(jq -r '.result' < "${LAST_REQ_FILE}")
  if [ "$HAS_ERR" == "failure" ]; then
    return 1;
  fi
}

function checkout_flow() {

  run step_1 || return;
  run step_2 || return;

  HAS_ERR="$?"

  if [ "$HAS_ERR" == "1" ]; then
    return;
  fi

  run step_3 || return;

  run step_4 || return;

  run step_5 || return;

}

checkout_flow

echo -n '0' >> "${FINISHED_PIPE}"
