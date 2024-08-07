#!/bin/bash

LOG_PATH="$PWD/woorricane-logs/t-$CURRENT_THREAD"
rm -rf "$LOG_PATH"
mkdir -p "$LOG_PATH"

COOKIE_JAR=$(mktemp)

set -o history -o histexpand

LAST_REQ_FILE=$(mktemp)
LAST_REQ_HEADERS=$(mktemp)
LAST_REQ_RESPONSE_HEADERS=$(mktemp)
LAST_REQ_FULL=$(mktemp)
STEP=0

function run() {
  STEP=$(( STEP + 1 ))

  echo -n "0" >> "$STEPS_PIPE/started/$STEP"
  "$1" > "$LOG_PATH/curl-step-$STEP.log"
  RET_CODE="$?"
  echo -n "0" >> "$STEPS_PIPE/finished/$STEP"
  return "$RET_CODE"
}

get() {
  local DATA
  DATA=$(curl -o "${LAST_REQ_FILE}" -c "${COOKIE_JAR}" -b "${COOKIE_JAR}" -sSL -D "${LAST_REQ_RESPONSE_HEADERS}" \
    --connect-timeout 400 \
    --max-time 400 \
    --trace-ascii - \
    --retry 0 "$@" 2>&1)

  HAS_ERR=$?
  if [ $HAS_ERR -ne 0 ]; then
    return $HAS_ERR;
  fi
  
  DATA=$(echo "$DATA" | awk '/=> Send header,/{flag=1; next} /== Info:/{flag=0} flag' | sed '/^=> Send data,.*$/d' | sed 's/^[[:xdigit:]]*: //g')

  {
    echo "${DATA}"
    echo ""
  } > "${LAST_REQ_HEADERS}"

  {
    cat "${LAST_REQ_HEADERS}"
    cat "${LAST_REQ_RESPONSE_HEADERS}"
    cat "${LAST_REQ_FILE}"
    echo ""
  } > "${LAST_REQ_FULL}"

  mkdir -p "$STEPS_PIPE/statuses/$STEP"
  local status_code=$(cat "$LAST_REQ_RESPONSE_HEADERS" | head -n 1 | awk '{print $2}')
  echo -n "0" >> "$STEPS_PIPE/statuses/$STEP/$status_code"
  
  cat "${LAST_REQ_FULL}"
}

function step_1() {
  # home
  get "${HOME_URL}"
}

function step_2() {
  QTY="1"
  # add to cart
  get "${AJAX_ADD_TO_CART_URL}" \
    -X 'POST' \
    -H "Referer: ${HOME_URL}" \
    --data-raw "product_id=${PRODUCT_ID}&quantity=${QTY}"

  HAS_ERR=$(jq '.error' < "${LAST_REQ_FILE}")
  if [ "$HAS_ERR" != "null" ]; then
    return 1;
  fi
}

function step_3() {
  # cart page
  get "${CART_URL}"
}

function step_4() {
  # get nonces on the checkout page
  get "${CHECKOUT_URL}" \
    -H "Referer: ${CART_URL}"

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
