#!/bin/bash

echo "----------run test script-----------"

echo "ENV_REQUEST_URL: ${ENV_REQUEST_URL}"

OLD_IFS=$IFS
IFS=","
for url in ${ENV_REQUEST_URL}; do
	echo "===> ping ${url}"
	ping -cv 1 url
	wget url -O -
done

IFS=$OLD_IFS