#!/bin/sh

##For security, you should really use a config file readable only by the user
##calling this utility (root may not be such a great idea).  There is an example
##provided.  Give the filename as an argument.
##Otherwise, set the variables here:

##Domain name:
DOMAIN="mydomain.tld"

##Host names (subdomains). Space separated list.
##Use @ if you need to include the domain in the list
HOSTS="@ www subdomain"

##APIKEY obtained from Namesilo:
APIKEY="c40031261ee449037a4b4"

##TTL can be anything down to 3600, but 3603 allows them to use anti-DoSing
##and is recommended
TTL=3603

## Do not edit lines below ##

usage="Usage: $0 [conf-file]"
if [ $# = 1 ]; then
  if grep -q ^APIKEY= $1 2>/dev/null; then
    . $1
  else
    echo $usage
    exit 1
  fi
elif [ $# -gt 1 ]; then
    echo $usage
    exit 1
fi

set -- $HOSTS

get_random()
{
	max=$1
	add=${2-0}

	expr $(echo | awk "{srand; print int(rand * $max)}") + $add
}

get_ip()
{
  record_type=$1
  addr=$2
  resolver=$3

  case $DNSUTIL in
  dig)
    dig $record_type +short $addr @$resolver
    ;;
  drill)
    drill $record_type $addr @$resolver | \
      sed -ne "/^$addr/s/.*[[:space:]]\"*\([0-9.]*\)\"*/\1/p"
    ;;
  esac
}

if type drill > /dev/null; then
  DNSUTIL=drill
else
  DNSUTIL=dig
fi

deps_missing=0
for d in $DNSUTIL curl xmllint; do
  if ! type $d > /dev/null; then
    echo "You need to make sure the $d utility is available, see README"
    deps_missing=1
  fi
done
if [ "$deps_missing" = 1 ]; then
  exit 1
fi

##Saved history pubic IP from last check
IP_FILE="/var/tmp/MyPubIP"

##Time IP last updated or 'No IP change' log message output
IP_TIME="/var/tmp/MyIPTime"

##How often to output 'No IP change' log messages
NO_IP_CHANGE_TIME=86400

##Response from Namesilo
RESPONSE="/tmp/namesilo_response.xml"

##Choose randomly which OpenDNS resolver to use
RESOLVER=resolver$(get_random 4 1).opendns.com
##Get the current public IP using DNS
CUR_IP="$(get_ip a myip.opendns.com $RESOLVER)"
ODRC=$?

## Try google dns if opendns failed
if [ $ODRC -ne 0 ]; then
   logger -t IP.Check -- IP Lookup at $RESOLVER failed!
   sleep 5
##Choose randomly which Google resolver to use
   RESOLVER=ns$(get_random 4 1).google.com
##Get the current public IP 
   IPQUOTED=$(get_ip TXT o-o.myaddr.l.google.com $RESOLVER)
   GORC=$?
## Exit if google failed
   if [ $GORC -ne 0 ]; then
     logger -t IP.Check -- IP Lookup at $RESOLVER failed!
     exit 1
   fi
   CUR_IP=$(echo $IPQUOTED | awk -F'"' '{ print $2}')
fi

##Check file for previous IP address
if [ -f $IP_FILE ]; then
  KNOWN_IP=$(cat $IP_FILE)
else
  KNOWN_IP=
fi

##See if the IP has changed
if [ "$CUR_IP" != "$KNOWN_IP" ]; then
  while [ $# -gt 0 ]; do
    # @ is the bare domain.  Dots are not required, but handle correctly in
    # case the user puts them in anyway.
    HOST=${1%@}
    HOST=${HOST%.}
    HOST_DOT="${HOST:+$HOST.}"
    echo $CUR_IP > $IP_FILE
    logger -t IP.Check -- Public IP changed to $CUR_IP from $RESOLVER

    ##Update DNS record in Namesilo:
    curl -s "https://www.namesilo.com/api/dnsListRecords?version=1&type=xml&key=$APIKEY&domain=$DOMAIN" > /tmp/$DOMAIN.xml
    RECORD_ID=`xmllint --xpath "//namesilo/reply/resource_record/record_id[../host/text() = '$HOST_DOT$DOMAIN' ]" /tmp/$DOMAIN.xml`
    RECORD_ID=${RECORD_ID#*>}
    RECORD_ID=${RECORD_ID%<*}
    curl -s "https://www.namesilo.com/api/dnsUpdateRecord?version=1&type=xml&key=$APIKEY&domain=$DOMAIN&rrid=$RECORD_ID&rrhost=$HOST&rrvalue=$CUR_IP&rrttl=$TTL" > $RESPONSE
    RESPONSE_CODE=`xmllint --xpath "//namesilo/reply/code/text()"  $RESPONSE`
    case $RESPONSE_CODE in
    300)
      ## Really doesn't matter if this is shared.
      date "+%s" > $IP_TIME
      logger -t IP.Check -- Update success. Now $HOST_DOT$DOMAIN IP address is $CUR_IP
      ;;
    280)
      logger -t IP.Check -- Duplicate record exists. No update necessary
      ;;
    *)
      ## put the old IP back, so that the update will be tried next time
      echo $KNOWN_IP > $IP_FILE
      logger -t IP.Check -- DDNS update failed code $RESPONSE_CODE!
      ;;
    esac

    shift
  done
else
  ## Only log all these events NO_IP_CHANGE_TIME after last update
  if [ $(date "+%s") -gt \
		$(expr "$(cat $IP_TIME)" + "$NO_IP_CHANGE_TIME") ]; then
    logger -t IP.Check -- NO IP change from $RESOLVER
    date "+%s" > $IP_TIME
  fi
fi

exit 0
