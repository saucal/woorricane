#!/bin/bash

COOKIE_JAR=$(mktemp)

set -o history -o histexpand

LAST_REQ_FILE=$(mktemp)
LAST_REQ_HEADERS=$(mktemp)
LAST_REQ_FULL=$(mktemp)

function get_json() {
  php -r "try{ \$json = json_decode(file_get_contents('php://stdin'), true ); if( isset( \$json ) && isset( \$json[\$argv[1]] ) ) { echo is_scalar(\$json[\$argv[1]]) ? \$json[\$argv[1]] : json_encode(\$json[\$argv[1]]); } } catch( Exception \$e ) {}" "$@"
}

get() {
  local DATA
  DATA=$(curl -o "${LAST_REQ_FILE}" -c "${COOKIE_JAR}" -b "${COOKIE_JAR}" -sSL -D - \
    --connect-timeout 400 \
    --max-time 400 \
    --retry 0 "$@" 2>&1)
  echo "${DATA}" > "${LAST_REQ_HEADERS}"
  echo "${DATA}" > "${LAST_REQ_FULL}"
  cat "${LAST_REQ_FILE}" >> "${LAST_REQ_FULL}"
  cat "${LAST_REQ_FULL}"
}

function step_1() {
  # home
  get "${HOME_URL}" \
    >> curl-step-1.log
}

function step_2() {
  QTY=$((RANDOM % 10))
  # add to cart
  get "${AJAX_ADD_TO_CART_URL}" \
    -X 'POST' \
    -H "Referer: ${HOME_URL}" \
    --data-raw "product_id=${PRODUCT_ID}&quantity=${QTY}" \
    >> curl-step-2.log

  HAS_ERR=$(cat "${LAST_REQ_FILE}" | get_json "error")
  if [ -n "$HAS_ERR" ]; then
    return 1;
  fi
}

function step_3() {
  # cart page
  get "${CART_URL}" \
    >> curl-step-3.log
}

function step_4() {
  # get nonces on the checkout page
  get "${CHECKOUT_URL}" \
    -H "Referer: ${CART_URL}" \
    >> curl-step-4.log

  CHECKOUT_NONCE=$(grep -oP ' name="woocommerce-process-checkout-nonce" value="\K.+?(?=")' "${LAST_REQ_FILE}")
  CHECKOUT_REFERER=$(grep -oP ' name="_wp_http_referer" value="\K.+?(?=")' "${LAST_REQ_FILE}")
  ORDER_REVIEW_NONCE=$(grep -oP '"update_order_review_nonce":"\K.+?(?=")' "${LAST_REQ_FILE}")
}

function step_5() {
  # checkout
  get "${AJAX_CHECKOUT_URL}" \
    -H "Referer: ${CHECKOUT_URL}" \
    --data-urlencode "woocommerce-process-checkout-nonce=${CHECKOUT_NONCE}" \
    --data-urlencode "_wp_http_referer=${CHECKOUT_REFERER}" \
    --data-raw "billing_first_name=Mai+K&billing_last_name=Love&billing_company=&billing_country=US&billing_address_1=4876++Hillcrest+Circle&billing_address_2=&billing_city=Crystal&billing_state=MN&billing_postcode=55429&billing_phone=218-404-4099&billing_email=bm0kig52zgp%40temporary-mail.net&order_comments=&payment_method=dummy" \
    >> curl-step-5.log
}

function checkout_flow() {

  step_1
  step_2

  HAS_ERR="$?"

  if [ "$HAS_ERR" == "1" ]; then
    return;
  fi

  step_3

  step_4

  step_5

}

checkout_flow

echo -n '0' >> "${FINISHED_PIPE}"