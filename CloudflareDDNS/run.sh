#!/usr/bin bash

declare EMAIL
declare TOKEN
declare ZONE
declare DOMAINS
declare INTERVAL

#EMAIL=$(::config 'email_address' | xargs echo -n)
#TOKEN=$(bashio::config 'cloudflare_api_token'| xargs echo -n)     
#ZONE=$(bashio::config 'cloudflare_zone_id'| xargs echo -n)
#DOMAINS=$(bashio::config 'domains')
#INTERVAL=$(bashio::config 'interval')

CONFIG_PATH=/data/options.json

EMAIL=$(jq --raw-output '.email_address // empty' $CONFIG_PATH | xargs echo -n)
TOKEN=$(jq --raw-output '.cloudflare_api_token // empty' $CONFIG_PATH | xargs echo -n)
ZONE=$(jq --raw-output '.cloudflare_zone_id // empty' $CONFIG_PATH | xargs echo -n)
DOMAINS=$(jq --raw-output '.domains // empty' $CONFIG_PATH)
INTERVAL=$(jq --raw-output '.interval // empty' $CONFIG_PATH)

if ! [[ ${EMAIL} == ?*@?*.?* ]];
then
    echo -e "\e[1;31mFailed to run due to invalid email address\e[1;37m\n"
    exit 1
elif [[ ${#TOKEN} == 0 ]];
then
    echo -e "\e[1;31mFailed to run due to missing Cloudflare API token\e[1;37m\n"
    exit 1
elif [[ ${#ZONE} == 0 ]];
then
    echo -e "\e[1;31mFailed to run due to missing Cloudflare Zone ID\e[1;37m\n"
    exit 1
fi

if [[ ${INTERVAL} == 1 ]];
then
    echo -e "Updating DNS A records every minute\n "
else
    echo -e "Updating DNS A records every ${INTERVAL} minutes\n "
fi

while :
do
    PUBLIC_IP=$(wget -O - -q -t 1 https://api.ipify.org 2>/dev/null)
    echo -e "Time: $(date '+%Y-%m-%d %H:%M')\nPublic IP address: ${PUBLIC_IP}\nIterating domain list:"

    for DOMAIN in ${DOMAINS[@]}
    do
        DNS_RECORD=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${ZONE}/dns_records?type=A&name=${DOMAIN}&page=1&per_page=100&match=all" \
         -H "X-Auth-Email: ${EMAIL}" \
         -H "Authorization: Bearer ${TOKEN}" \
         -H "Content-Type: application/json")

        if [[ ${DNS_RECORD} == *"\"success\":false"* ]];
        then
            ERROR=$(echo ${DNS_RECORD} | awk '{ sub(/.*"message":"/, ""); sub(/".*/, ""); print }')
            echo -e " - \e[1;31mStopped, Cloudflare response: ${ERROR}\e[1;37m"
            exit 0
        fi

        DOMAIN_ID=$(echo ${DNS_RECORD} | awk '{ sub(/.*"id":"/, ""); sub(/",.*/, ""); print }')
        DOMAIN_IP=$(echo ${DNS_RECORD} | awk '{ sub(/.*"content":"/, ""); sub(/",.*/, ""); print }')
        DOMAIN_PROXIED=$(echo ${DNS_RECORD} | awk '{ sub(/.*"proxied":/, ""); sub(/,.*/, ""); print }')

        if [[ ${PUBLIC_IP} != ${DOMAIN_IP} ]];
        then
            DATA=$(printf '{"type":"A","name":"%s","content":"%s","proxied":%s}' "${DOMAIN}" "${PUBLIC_IP}" "${DOMAIN_PROXIED}")
            API_RESPONSE=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/${ZONE}/dns_records/${DOMAIN_ID}" \
            -H "X-Auth-Email: ${EMAIL}" \
            -H "Authorization: Bearer ${TOKEN}" \
            -H "Content-Type: application/json" \
            --data ${DATA})
            
            if [[ ${API_RESPONSE} == *"\"success\":false"* ]];
            then
                echo -e " - ${DOMAIN} (\e[1;31m${DOMAIN_IP}\e[1;37m),\e[1;31m failed to update\e[1;37m\n"
            else
                echo -e " - ${DOMAIN} (\e[1;31m${DOMAIN_IP}\e[1;37m),\e[1;32m updated\e[1;37m\n"
            fi
        else
            echo -e " - ${DOMAIN}, up-to-date\n"
        fi
        
    done
    
    if [[ ${INTERVAL} == 1 ]];
    then
        echo -e " \nWaiting 1 minute for next check...\n "
    else
        echo -e " \nWaiting ${INTERVAL} minutes for next check...\n "
    fi
    
    sleep ${INTERVAL}m
    
done