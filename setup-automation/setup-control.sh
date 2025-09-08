#!/bin/bash

# Initial system and user setup
dnf install -y python3-pip python3-libsemanage

sudo cp -a /root/.ssh/* /home/rhel/.ssh/.
sudo chown -R rhel:rhel /home/rhel/.ssh

mkdir -p /home/rhel/ansible
chown -R rhel:rhel /home/rhel/ansible
chmod 777 /home/rhel/ansible

# Git global configuration
git config --global user.email "student@redhat.com"
git config --global user.name "student"

# Create inventory file
cat <<EOF | tee /tmp/inventory.ini
[ctrlnodes]
controller.acme.example.com ansible_host=controller ansible_user=rhel ansible_connection=local

[windowssrv]
windows ansible_host=windows ansible_user=Administrator ansible_password=Ansible123! ansible_connection=winrm ansible_port=5986 ansible_winrm_server_cert_validation=ignore

[all:vars]
ansible_python_interpreter=/usr/bin/python3
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
EOF

# Create variables file
cat <<EOF | tee /tmp/track-vars.yml
---
# config vars
controller_hostname: controller
controller_validate_certs: false
ansible_python_interpreter: /usr/bin/python3
controller_ee: windows workshop execution environment
student_user: student
student_password: learn_ansible
controller_admin_user: admin
controller_admin_password: "ansible123!"
host_key_checking: false
custom_facts_dir: "/etc/ansible/facts.d"
custom_facts_file: custom_facts.fact
admin_username: admin
admin_password: ansible123!
repo_user: rhel
default_tag_name: "0.0.1"
lab_organization: ACME
EOF

# Create simplified controller setup playbook
cat <<EOF | tee /tmp/controller-setup.yml
---
- name: Controller config for Windows Getting Started
  hosts: controller.acme.example.com
  gather_facts: true
  collections:
    - ansible.controller
    
  tasks:
    - name: Ensure controller is online and responsive
      ansible.builtin.uri:
        url: "https://localhost/api/v2/ping/"
        method: GET
        user: "{{ controller_admin_user }}"
        password: "{{ controller_admin_password }}"
        validate_certs: "{{ controller_validate_certs }}"
        force_basic_auth: true
      register: controller_online
      until: controller_online.status == 200
      retries: 10
      delay: 5

    - name: Create an OAuth2 token for automation
      ansible.controller.token:
        description: 'Token for lab setup automation'
        scope: "write"
        state: present
        controller_host: "{{ controller_hostname }}"
        controller_username: "{{ controller_admin_user }}"
        controller_password: "{{ controller_admin_password }}"
        validate_certs: "{{ controller_validate_certs }}"
      register: oauth_token

    - name: Add Organization
      ansible.controller.organization:
        name: "{{ lab_organization }}"
        description: "ACME Corp Organization"
        state: present
        controller_oauthtoken: "{{ oauth_token.token }}"
        controller_host: "{{ controller_hostname }}"
        validate_certs: "{{ controller_validate_certs }}"

    - name: Add Windows EE
      ansible.controller.execution_environment:
        name: "{{ controller_ee }}"
        image: "quay.io/nmartins/windows_ee"
        pull: missing
        organization: "{{ lab_organization }}"
        state: present
        controller_oauthtoken: "{{ oauth_token.token }}"
        controller_host: "{{ controller_hostname }}"
        validate_certs: "{{ controller_validate_certs }}"
        
    - name: Create student admin user
      ansible.controller.user:
        username: "{{ student_user }}"
        password: "{{ student_password }}"
        email: "student@acme.example.com"
        is_superuser: true
        state: present
        controller_oauthtoken: "{{ oauth_token.token }}"
        controller_host: "{{ controller_hostname }}"
        validate_certs: "{{ controller_validate_certs }}"

    - name: Create Workshop Inventory
      ansible.controller.inventory:
        name: "Workshop Inventory"
        organization: "{{ lab_organization }}"
        state: present
        controller_oauthtoken: "{{ oauth_token.token }}"
        controller_host: "{{ controller_hostname }}"
        validate_certs: "{{ controller_validate_certs }}"

    - name: Create Host for Windows Server
      ansible.controller.host:
        name: "windows"
        inventory: "Workshop Inventory"
        state: present
        controller_oauthtoken: "{{ oauth_token.token }}"
        controller_host: "{{ controller_hostname }}"
        validate_certs: "{{ controller_validate_certs }}"

    - name: Create Group for Windows Servers
      ansible.controller.group:
        name: "Windows Servers"
        inventory: "Workshop Inventory"
        state: present
        variables: |
          ansible_connection: winrm
          ansible_port: 5986
          ansible_winrm_server_cert_validation: ignore
        controller_oauthtoken: "{{ oauth_token.token }}"
        controller_host: "{{ controller_hostname }}"
        validate_certs: "{{ controller_validate_certs }}"
        
    - name: Associate windows host with the Windows Servers group
      ansible.controller.host:
        name: "windows"
        inventory: "Workshop Inventory"
        groups:
          - "Windows Servers"
        state: present
        controller_oauthtoken: "{{ oauth_token.token }}"
        controller_host: "{{ controller_hostname }}"
        validate_certs: "{{ controller_validate_certs }}"

    - name: Create Project
      ansible.controller.project:
        name: "Windows Workshop"
        description: "Windows Getting Started Workshop Content"
        organization: "{{ lab_organization }}"
        scm_type: git
        scm_url: "http://gitea:3000/student/workshop_project.git"
        state: present
        controller_oauthtoken: "{{ oauth_token.token }}"
        controller_host: "{{ controller_hostname }}"
        validate_certs: "{{ controller_validate_certs }}"
EOF

# Install necessary collections and packages
ansible-galaxy collection install community.general
ansible-galaxy collection install microsoft.ad
ansible-galaxy collection install ansible.controller
pip3 install pywinrm

# Execute the controller setup
ansible-playbook /tmp/controller-setup.yml -i /tmp/inventory.ini -e @/tmp/track-vars.yml

# Install additional tools
sudo dnf clean all
sudo dnf install -y ansible-navigator ansible-lint nc
pip3.9 install yamllint