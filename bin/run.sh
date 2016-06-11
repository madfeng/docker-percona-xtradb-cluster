#!/bin/bash

set -e

[ "$DEBUG" == "1" ] && set -x && set +e

if [ "${PXC_SST_PASSWORD}" == "**ChangeMe**" -o -z "${PXC_SST_PASSWORD}" ]; then
   echo "*** ERROR: you need to define PXC_SST_PASSWORD environment variable - Exiting ..."
   exit 1
fi

if [ "${PXC_ROOT_PASSWORD}" == "**ChangeMe**" -o -z "${PXC_ROOT_PASSWORD}" ]; then
   echo "*** ERROR: you need to define PXC_ROOT_PASSWORD environment variable - Exiting ..."
   exit 1
fi

if [ "${SERVICE_NAME}" == "**ChangeMe**" -o -z "${SERVICE_NAME}" ]; then
   echo "*** ERROR: you need to define SERVICE_NAME environment variable - Exiting ..."
   exit 1
fi

sleep 6

echo "=> Configuring PXC cluster"
PXC_NODES=`dig +short ${SERVICE_NAME} | sort`
export PXC_NODES=`echo ${PXC_NODES} | sed "s/ /,/g"`
if [ -z "${PXC_NODES}" ]; then
   echo "*** ERROR: Could not determine which containers are part of this service."
   echo "*** Is this service named \"${SERVICE_NAME}\"? If not, please regenerate the service"
   echo "*** and add SERVICE_NAME environment variable which value should be equal to this service name"
   echo "*** Exiting ..."
   exit 1
fi
echo "==>PXC_NODES:[${PXC_NODES}]"

export MY_IP=`ip addr | grep inet | grep ${PXC_TOP_IP} | tail -1 | awk '{print $2}' | awk -F\/ '{print $1}'`
if [ -z "${MY_IP}" ]; then
   echo "*** ERROR: you need to define MY_IP environment variable - Exiting ..."
   exit 1
fi
echo "==>MY_IP:[${MY_IP}]"
#----------

#if [ "${MY_IP}" == "**ChangeMe**" -o -z "${MY_IP}" ]; then
#    echo "==>PXC_TOP_IP:[${PXC_TOP_IP}]"
#    export MY_IP=`ip addr | grep inet | grep ${PXC_TOP_IP} | tail -1 | awk '{print $2}' | awk -F\/ '{print $1}'`
#    echo "==>MY_IP:[${MY_IP}]"
#    if [ -z "${MY_IP}" ]; then
#       echo "*** ERROR: you need to define MY_IP environment variable - Exiting ..."
#       exit 1
#    fi
#fi
#
#
#if [ "${PXC_NODES}" == "-NODES-" -o -z "${PXC_NODES}" ]; then
#    export PXC_NODES=${MY_IP}
#else
#    export PXC_NODES="${PXC_NODES},${MY_IP}"
#fi


# Logs
chown -R mysql ${PXC_LOGS_PATH}

# Configure the cluster (replace required parameters)

#echo "=> Configuring PXC cluster"

change_pxc_nodes.sh "${PXC_NODES}"
echo "root:${PXC_ROOT_PASSWORD}" | chpasswd
perl -p -i -e "s/PXC_SST_PASSWORD/${PXC_SST_PASSWORD}/g" ${PXC_CONF}
perl -p -i -e "s/MY_IP/${MY_IP}/g" ${PXC_CONF}
chown -R mysql:mysql ${PXC_VOLUME}

echo "==========================================="
echo "When you need to use this database cluster in an application"
echo "remember that your MySQL root password is ${PXC_ROOT_PASSWORD}"
echo "===========================================" 

# If this container is not configured, just configure it
BOOTSTRAPED=false
if [ ! -e ${PXC_BOOTSTRAP_FLAG} ]; then
   # Ask other containers if they're already configured
   # If so, I'm joining the cluster
   # If not, I'm bootstraping only if I'm first node in PXC_NODES - needed for cluster initialization
   for node in `echo "${PXC_NODES}" | sed "s/,/ /g"`; do
      # Skip myself
      if [ "${MY_IP}" == "${node}" ]; then
         continue
      fi
      # Check if node is already initializated - that means the cluster has already been bootstraped 
      if sshpass -p ${PXC_ROOT_PASSWORD} ssh ${SSH_OPTS} ${SSH_USER}@${node} "[ -e ${PXC_BOOTSTRAP_FLAG} ]" >/dev/null 2>&1; then
         BOOTSTRAPED=true
         break
      fi
   done
   
   if ${BOOTSTRAPED}; then
      echo "=> Seems like cluster has already been bootstraped, so I'm joining it ..."
      join-cluster.sh || exit 1
   else
      # If I could not detect any other container bootstraped I'm bootstraping it, but only if I'm the first one in PXC_NODES
      if [ "${MY_IP}" == `echo "${PXC_NODES}" | awk -F, '{print $1}'` ]; then
         bootstrap-pxc.sh || exit 1
      # Don't bootstrap the cluster, just join it - Needed for subsequent containers initialization
      else
         echo "=> Seems like cluster is being bootstraped by another container, so I'm joining it ..."
         join-cluster.sh || exit 1
      fi
   fi
else
   # If this container is already configured, just start it
   echo "=> I was already part of the cluster, starting PXC"
   /usr/bin/supervisord
fi
