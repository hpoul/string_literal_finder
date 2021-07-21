#!/bin/bash

# This script requires `jq`, `curl`, `git`.

set -xeu

cd "${0%/*}"/..


pub get
pub global activate coverage

fail=false
dart test --coverage coverage || fail=true
echo "fail=$fail"

# shellcheck disable=SC2038
# shellcheck disable=SC2046
jq -s '{coverage: [.[].coverage] | flatten}' $(find coverage -name '*.json' | xargs) > coverage/merged_json.cov

pub global run coverage:format_coverage --packages=.packages -i coverage/merged_json.cov -l --report-on lib --report-on test > coverage/lcov.info

bash <(curl -s https://codecov.io/bash) -f coverage/lcov.info

test "$fail" == "true" && exit 1

echo "Success 🎉️"

exit 0