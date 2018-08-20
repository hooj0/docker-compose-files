#!/bin/sh
# @changelog container httpd ping test

echo "----------run test script-----------"

echo "ENV_REQUEST_URL: ${ENV_REQUEST_URL}"

OLD_IFS=$IFS
IFS=","
for requrl in ${ENV_REQUEST_URL}; do
	echo
	echo "===> ping ${requrl}"
	#ping -c 1 url
	wget $requrl -T 3 -O -
	#nc -v -z -w 2 $requrl
	echo
done

IFS=$OLD_IFS