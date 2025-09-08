#!/bin/bash

# Install required packages
dnf install -y python3-pip python3-libsemanage

# Create minimal inventory
cat <<EOF | tee /tmp/inventory.ini
[ctrlnodes]
controller.acme.example.com ansible_host=controller ansible_user=rhel ansible_connection=local

[all:vars]
ansible_python_interpreter=/usr/bin/python3
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
EOF

# Create minimal variables
cat <<EOF | tee /tmp/track-vars.yml
---
controller_hostname: controller
controller_validate_certs: false
controller_ee: windows workshop execution environment
student_user: student
student_password: learn_ansible
controller_admin_user: admin
controller_admin_password: "ansible123!"
lab_organization: ACME
EOF

# Create controller setup playbook
cat <<EOF | tee /tmp/controller-setup.yml
---
- name: Controller config for Windows Getting Started
  hosts: controller.acme.example.com
  gather_facts: true
  collections:
    - ansible.controller
    
  tasks:
    - name: Ensure controller is online
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

    - name: Create OAuth2 token
      ansible.controller.token:
        description: 'Lab setup token'
        scope: "write"
        state: present
        controller_host: "{{ controller_hostname }}"
        controller_username: "{{ controller_admin_user }}"
        controller_password: "{{ controller_admin_password }}"
        validate_certs: "{{ controller_validate_certs }}"
      register: oauth_token

    - name: Create Organization
      ansible.controller.organization:
        name: "{{ lab_organization }}"
        description: "ACME Corp Organization"
        state: present
        controller_oauthtoken: "{{ oauth_token.token }}"
        controller_host: "{{ controller_hostname }}"
        validate_certs: "{{ controller_validate_certs }}"

    - name: Create Windows EE
      ansible.controller.execution_environment:
        name: "{{ controller_ee }}"
        image: "quay.io/nmartins/windows_ee"
        pull: missing
        organization: "{{ lab_organization }}"
        state: present
        controller_oauthtoken: "{{ oauth_token.token }}"
        controller_host: "{{ controller_hostname }}"
        validate_certs: "{{ controller_validate_certs }}"
        
    - name: Create student user
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

    - name: Create Windows Host
      ansible.controller.host:
        name: "windows"
        inventory: "Workshop Inventory"
        state: present
        controller_oauthtoken: "{{ oauth_token.token }}"
        controller_host: "{{ controller_hostname }}"
        validate_certs: "{{ controller_validate_certs }}"

    - name: Create Windows Group
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
        
    - name: Add Windows host to group
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

# Install required collections
echo "Installing ansible.controller collection..."
if ! ansible-galaxy collection install ansible.controller:2.5.0 --force; then
    echo "Failed to install ansible.controller:2.5.0, trying latest version..."
    ansible-galaxy collection install ansible.controller --force
fi

# Verify collection installation
echo "Verifying collection installation..."
ansible-galaxy collection list | grep ansible.controller

# Test if the module is available
echo "Testing ansible.controller.token module availability..."
ansible-doc ansible.controller.token > /dev/null 2>&1 && echo "Module found" || echo "Module not found"

# Execute setup
echo "Running controller setup playbook..."
ansible-playbook /tmp/controller-setup.yml -i /tmp/inventory.ini -e @/tmp/track-vars.yml -v
