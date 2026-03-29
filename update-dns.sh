#!/bin/bash
sed -i 's/#DNS=/DNS=8.8.8.8/' /etc/systemd/resolved.conf
systemctl restart systemd-resolved
