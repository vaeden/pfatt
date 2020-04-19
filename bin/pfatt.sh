#!/bin/sh
set -e

ONT_IF='em0'
RG_IF='em1'
RG_ETHER_ADDR='xx:xx:xx:xx:xx:xx'
OPNSENSE='no'
LOG=/var/log/pfatt.log

getTimestamp(){
    echo `date "+%Y-%m-%d %H:%M:%S :: [pfatt.sh] ::"`
}

{
    echo "$(getTimestamp) pfSense + AT&T U-verse Residential Gateway for true bridge mode"
    echo "$(getTimestamp) Configuration: "
    echo "$(getTimestamp)        ONT_IF: $ONT_IF"
    echo "$(getTimestamp)         RG_IF: $RG_IF"
    echo "$(getTimestamp) RG_ETHER_ADDR: $RG_ETHER_ADDR"
    echo "$(getTimestamp)      OPNSENSE: $OPNSENSE"

    echo -n "$(getTimestamp) loading netgraph kernel modules... "
    /sbin/kldload -nq netgraph
    /sbin/kldload -nq ng_ether
    /sbin/kldload -nq ng_etf
    /sbin/kldload -nq ng_vlan
    echo "OK!"

    if [ ${OPNSENSE} != 'yes' ]; then
        echo -n "$(getTimestamp) attaching interfaces to ng_ether... "
        /usr/local/bin/php -r "pfSense_ngctl_attach('.', '$ONT_IF');" 
        /usr/local/bin/php -r "pfSense_ngctl_attach('.', '$RG_IF');"
        echo "OK!"
    fi 

    echo "$(getTimestamp) building netgraph nodes..."

    echo -n "$(getTimestamp) bridging EAPOL packets between $ONT_IF (ONT) and $RG_IF (RG)... "
    /usr/sbin/ngctl mkpeer $ONT_IF: etf lower downstream
    /usr/sbin/ngctl name $ONT_IF:lower ont-eap
    /usr/sbin/ngctl mkpeer $RG_IF: etf lower downstream
    /usr/sbin/ngctl name $RG_IF:lower rg-eap
    /usr/sbin/ngctl connect ont-eap: rg-eap: eap eap
    /usr/sbin/ngctl msg ont-eap: 'setfilter {ethertype=0x888e matchhook="eap"}'
    /usr/sbin/ngctl msg rg-eap: 'setfilter {ethertype=0x888e matchhook="eap"}'
    echo "OK!"

    echo -n "$(getTimestamp) untagging other packets on $ONT_IF (ONT) to ngeth0"
    /usr/sbin/ngctl mkpeer ont-eap: vlan nomatch downstream
    /usr/sbin/ngctl name ont-eap:nomatch ont-vl0
    /usr/sbin/ngctl mkpeer ont-vl0: eiface vl0 ether
    /usr/sbin/ngctl msg ont-vl0: 'addfilter {vid=0 hook="vl0"}'
    /usr/sbin/ngctl msg ngeth0: set $RG_ETHER_ADDR
    echo "OK!"

    echo -n "$(getTimestamp) untagging other packets on $RG_IF (RG) to ngeth1"
    /usr/sbin/ngctl mkpeer rg-eap: vlan nomatch downstream
    /usr/sbin/ngctl name rg-eap:nomatch rg-vl0
    /usr/sbin/ngctl mkpeer rg-vl0: eiface vl0 ether
    /usr/sbin/ngctl msg rg-vl0: 'addfilter {vid=0 hook="vl0"}'
    echo "OK!"

    echo -n "$(getTimestamp) enabling $RG_IF interface... "
    /sbin/ifconfig $RG_IF up
    echo "OK!"

    echo -n "$(getTimestamp) enabling $ONT_IF interface... "
    /sbin/ifconfig $ONT_IF up
    echo "OK!"

    echo -n "$(getTimestamp) enabling promiscuous mode on $RG_IF... "
    /sbin/ifconfig $RG_IF promisc
    echo "OK!"

    echo -n "$(getTimestamp) enabling promiscuous mode on $ONT_IF... "
    /sbin/ifconfig $ONT_IF promisc
    echo "OK!"

    echo "$(getTimestamp) ngeth0 should now be available to configure as your pfSense WAN"
    echo "$(getTimestamp) done!"
} >> $LOG
