#!/bin/bash
cat <<EOF >> /etc/hosts
192.168.56.10  k8s-master
192.168.56.11  k8s-worker
EOF
