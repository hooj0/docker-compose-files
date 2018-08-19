#!/bin/sh

echo "----------run test script-----------"

echo "ENV_REQUEST_URL: ${ENV_REQUEST_URL}"

OLD_IFS=$IFS
IFS=","
for requrl in ${ENV_REQUEST_URL}; do
	echo
	echo "===> ping ${requrl}"
	#ping -c 1 url
	wget $requrl -O -
	echo
done

IFS=$OLD_IFS