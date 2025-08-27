#!/bin/bash
curl -k  -L https://${SATELLITE_URL}/pub/katello-server-ca.crt -o /etc/pki/ca-trust/source/anchors/${SATELLITE_URL}.ca.crt
update-ca-trust
rpm -Uhv https://${SATELLITE_URL}/pub/katello-ca-consumer-latest.noarch.rpm

subscription-manager register --org=${SATELLITE_ORG} --activationkey=${SATELLITE_ACTIVATIONKEY}

yum install nano httpd -y


cat <<EOF | tee /var/www/html/index.html


<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Nothing to See Here</title>
    <style>
        body {
            display: flex;
            justify-content: center;
            align-items: center;
            height: 100vh;
            margin: 0;
            font-family: Arial, sans-serif;
            background-color: #f4f4f9;
            color: #333;
        }
        h1 {
            font-size: 3em;
            text-align: center;
        }
    </style>
</head>
<body>
    <h1>Waiting for compliance report - Node02</h1>
</body>
</html>

EOF

systemctl start httpd

mkdir /backup
chmod -R 777 /backup


## ^ from getting started controller

## COMMENT CENTOS 
# dnf config-manager --disable rhui*,google*

# sudo bash -c 'cat >/etc/yum.repos.d/centos8-baseos.repo <<EOL
# [centos8-baseos]
# name=CentOS 8 Stream BaseOS
# baseurl=http://mirror.centos.org/centos/8-stream/BaseOS/x86_64/os
# enabled=1
# gpgcheck=0

# EOL
# cat /etc/yum.repos.d/centos8-baseos.repo'

# sudo bash -c 'cat >/etc/yum.repos.d/centos8-appstream.repo <<EOL
# [centos8-appstream]
# name=CentOS 8 Stream AppStream
# baseurl=http://mirror.centos.org/centos/8-stream/AppStream/x86_64/os/
# enabled=1
# gpgcheck=0

# EOL
# cat /etc/yum.repos.d/centos8-appstream.repo'
## END COMMENT CENTOS 

## clean repo metadata and refresh
# dnf config-manager --disable google*
# dnf clean all
# dnf config-manager --enable rhui-rhel-9-for-x86_64-baseos-rhui-rpms
# dnf config-manager --enable rhui-rhel-9-for-x86_64-appstream-rhui-rpms
# dnf makecache

#Install a package to build metadata of the repo and not need to wait during labs
#dnf install -y cups-filesystem

# stop web server
systemctl stop nginx

# make Dan Walsh weep: https://stopdisablingselinux.com/
setenforce 0




###################################
# yum install yum-utils jq podman wget git ansible-core nano -y
# setenforce 0
# firewall-cmd --permanent --add-port=2000:2003/tcp
# firewall-cmd --permanent --add-port=6030:6033/tcp
# firewall-cmd --permanent --add-port=8065:8065/tcp
# firewall-cmd --reload
# export RTPASS=ansible
# echo "ansible" | passwd root --stdin

# # Grab sample switch config
# rm -rf /tmp/setup ## Troubleshooting step

# ansible-galaxy collection install community.general
# ansible-galaxy collection install servicenow.itsm

# mkdir /tmp/setup/

# git clone https://github.com/nmartins0611/Instruqt_netops.git /tmp/setup/

# ### Configure containers

# podman pull quay.io/nmartins/ceoslab-rh
# #podman pull docker.io/nats
# #podman run --name mattermost-preview -d --publish 8065:8065 mattermost/mattermost-preview


# ## Create Networks

# podman network create net1
# podman network create net2
# podman network create net3
# podman network create loop
# podman network create management

# # Create mattermost container
# podman run -d --network management --name=mattermost --privileged --publish 8065:8065 mattermost/mattermost-preview:7.8.6

# ##docker pull mattermost/platform:6.5.0

# # podman create --name=ceos1 --privileged -v /tmp/setup/sw01/sw01:/mnt/flash/startup-config -e INTFTYPE=eth -e ETBA=1 -e SKIP_ZEROTOUCH_BARRIER_IN_SYSDBINIT=1 -e CEOS=1 -e EOS_PLATFORM=ceoslab -e container=docker -p 9092:9092 -p 6031:6030 -p 2001:22/tcp -i -t quay.io/nmartins/ceoslab-rh /sbin/init systemd.setenv=INTFTYPE=eth systemd.setenv=ETBA=1 systemd.setenv=SKIP_ZEROTOUCH_BARRIER_IN_SYSDBINIT=1 systemd.setenv=CEOS=1 systemd.setenv=EOS_PLATFORM=ceoslab systemd.setenv=container=podman
# podman run -d --network management --name=ceos1 --privileged -v /tmp/setup/sw01/sw01:/mnt/flash/startup-config -e INTFTYPE=eth -e ETBA=1 -e SKIP_ZEROTOUCH_BARRIER_IN_SYSDBINIT=1 -e CEOS=1 -e EOS_PLATFORM=ceoslab -e container=docker -p 6031:6030 -p 2001:22/tcp -i -t quay.io/nmartins/ceoslab-rh /sbin/init systemd.setenv=INTFTYPE=eth systemd.setenv=ETBA=1 systemd.setenv=SKIP_ZEROTOUCH_BARRIER_IN_SYSDBINIT=1 systemd.setenv=CEOS=1 systemd.setenv=EOS_PLATFORM=ceoslab systemd.setenv=container=podman  ##
# podman run -d --network management --name=ceos2 --privileged -v /tmp/setup/sw02/sw02:/mnt/flash/startup-config -e INTFTYPE=eth -e ETBA=1 -e SKIP_ZEROTOUCH_BARRIER_IN_SYSDBINIT=1 -e CEOS=1 -e EOS_PLATFORM=ceoslab -e container=docker -p 6032:6030 -p 2002:22/tcp -i -t quay.io/nmartins/ceoslab-rh /sbin/init systemd.setenv=INTFTYPE=eth systemd.setenv=ETBA=1 systemd.setenv=SKIP_ZEROTOUCH_BARRIER_IN_SYSDBINIT=1 systemd.setenv=CEOS=1 systemd.setenv=EOS_PLATFORM=ceoslab systemd.setenv=container=podman  ##systemd.setenv=MGMT_INTF=eth0
# podman run -d --network management --name=ceos3 --privileged -v /tmp/setup/sw03/sw03:/mnt/flash/startup-config -e INTFTYPE=eth -e ETBA=1 -e SKIP_ZEROTOUCH_BARRIER_IN_SYSDBINIT=1 -e CEOS=1 -e EOS_PLATFORM=ceoslab -e container=docker -p 6033:6030 -p 2003:22/tcp -i -t quay.io/nmartins/ceoslab-rh /sbin/init systemd.setenv=INTFTYPE=eth systemd.setenv=ETBA=1 systemd.setenv=SKIP_ZEROTOUCH_BARRIER_IN_SYSDBINIT=1 systemd.setenv=CEOS=1 systemd.setenv=EOS_PLATFORM=ceoslab systemd.setenv=container=podman  ##systemd.setenv=MGMT_INTF=eth0

# ## Attach Networks
# podman network connect loop ceos1
# podman network connect net1 ceos1
# podman network connect net3 ceos1
# podman network connect management ceos1

# podman network connect loop ceos2
# podman network connect net1 ceos2
# podman network connect net2 ceos2
# podman network connect management ceos2

# podman network connect loop ceos3
# podman network connect net2 ceos3
# podman network connect net3 ceos3
# podman network connect management ceos3

# podman network connect management mattermost

# ## Wait for Switches to load conf
# sleep 60

# ## Get management IP
# var1=$(podman inspect ceos1 | jq -r '.[] | .NetworkSettings.Networks.management | .IPAddress')
# var2=$(podman inspect ceos2 | jq -r '.[] | .NetworkSettings.Networks.management | .IPAddress')
# var3=$(podman inspect ceos3 | jq -r '.[] | .NetworkSettings.Networks.management | .IPAddress')
# var4=$(podman inspect mattermost | jq -r '.[] | .NetworkSettings.Networks.management | .IPAddress')

# ## Build local host etc/hosts
# echo "$var1" ceos1 >> /etc/hosts
# echo "$var2" ceos2 >> /etc/hosts
# echo "$var3" ceos3 >> /etc/hosts
# echo "$var4" mattermost >> /etc/hosts

# ## Install Gmnic
# bash -c "$(curl -sL https://get-gnmic.kmrd.dev)"

# ## Test GMNIC
# ## gnmic -a localhost:6031 -u ansible -p ansible --insecure subscribe --path   "/interfaces/interface[name=Ethernet1]/state/admin-status"
# ## gnmic -addr ceos1:6031 -username ansible -password ansible   get '/network-instances/network-instance[name=default]/protocols/protocol[identifier=BGP][name=BGP]/bgp'
# ## gnmic -a localhost:6031 -u ansible -p ansible --insecure subscribe --path 'components/component/state/memory/'

# ## SSH Setup
# echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDdQebku7hz6otXEso48S0yjY0mQ5oa3VbFfOvEHeApfu9pNMG34OCzNpRadCDIYEfidyCXZqC91vuVM+6R7ULa/pZcgoeDopYA2wWSZEBIlF9DexAU4NEG4Zc0sHfrbK66lyVgdpvu1wmHT5MEhaCWQclo4B5ixuUVcSjfiM8Y7FL/qOp2FY8QcN10eExQo1CrGBHCwvATxdjgB+7yFhjVYVkYALINDoqbFaituKupqQyCj3FIoKctHG9tsaH/hBnhzRrLWUfuUTMMveDY24PzG5NR3rBFYI3DvKk5+nkpTcnLLD2cze6NIlKW5KygKQ4rO0tJTDOqoGvK5J5EM4Jb" >> /root/.ssh/authorized_keys 
# echo "Host *" >> /etc/ssh/ssh_config
# echo "StrictHostKeyChecking no" >> /etc/ssh/ssh_config
# echo "UserKnownHostsFile=/dev/null" >> /etc/ssh/ssh_config
# chmod 400 /etc/ssh/ssh_config
# systemctl restart sshd





