-----------------------------------------------------------------
# namesilo_ddns version 2.2
Dynamic DNS record update with NameSilo.

This is a shell script to update Namesilo's DNS record when IP changed.  Set to run this script as cronjob in your system.

Previous version was tested in Fedora 23, CentOS 7 and Ubuntu 14.04+.

Portablity fixes mean it should work anywhere, but definitely works on FreeBSD.
Please report test results.

## Prerequisites:

* Generate API key in the _api manager_ at Namesilo

* Make sure your system has `xmllint` and `dig` or `drill`.  Your system will also require `cURL` or `fetch`.  If not, install them:

on CentOS:

```sudo yum install bind-utils libxml2```

on Ubuntu/Debian:

```sudo apt-get install dnsutils libxml2-utils```

on FreeBSD:

```sudo pkg install libxml2```

## How to use:
* Download and save the shell script.
* Copy namesilo_ddns.conf.sample somewhere, chmod 600 and set `DOMAIN`, `HOSTS`, and `APIKEY`.  You may optionally change the `TTL`.
* Set file permission to make the script executable.
* Create cronjob (optional)

## Manual test:
You should test the script to verify that actually can update the DNS record at Namesilo.

Step 1: Create an A record in DNS Manager at Namesilo. Set it to a random IP address (not the same public IP of yours). For example:

```test.mydomain.tld     A     1.2.3.4```

Step 2: Run the script to try to update this DNS record

```# ./namesilo_ddns.sh /path/to/config_file```

Step 3: Verify:

```dig +short test.domain.tld @ns1.dnsowl.com```

(you may also try other DNS server at Namesilo, e.g. `ns2.dnsowl.com`, `ns3.dnsowl.com`)

The result should show updated DNS record with your current public IP address. 
(Note: DNS record updates need time to propagate to other DNS server, so if you check against other DNS server you may not see the update right away.)
