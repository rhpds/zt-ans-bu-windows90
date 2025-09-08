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
    - name: Check Ansible version compatibility
      ansible.builtin.debug:
        msg: "Ansible version {{ ansible_version.full }} detected. AAP 2.5 supports Ansible 2.9-2.15"
      when: ansible_version.major == 2 and ansible_version.minor > 15

    - name: Check if controller service is running
      ansible.builtin.systemd:
        name: automation-controller
        state: started
      become: true

    - name: Wait for controller service to be ready
      ansible.builtin.wait_for:
        port: 443
        host: localhost
        delay: 10
        timeout: 300

    - name: Debug - Check controller status
      ansible.builtin.uri:
        url: "https://localhost/api/v2/ping/"
        method: GET
        user: "{{ controller_admin_user }}"
        password: "{{ controller_admin_password }}"
        validate_certs: "{{ controller_validate_certs }}"
        force_basic_auth: true
        status_code: [200, 404, 503]
      register: controller_debug
      ignore_errors: true

    - name: Display controller debug info
      ansible.builtin.debug:
        msg: "Controller response: Status {{ controller_debug.status }}, Body: {{ controller_debug.content | default('No content') }}"

    - name: Try alternative controller URLs
      ansible.builtin.uri:
        url: "{{ item }}"
        method: GET
        user: "{{ controller_admin_user }}"
        password: "{{ controller_admin_password }}"
        validate_certs: "{{ controller_validate_certs }}"
        force_basic_auth: true
        status_code: [200, 404, 503]
      register: alt_urls
      ignore_errors: true
      loop:
        - "https://localhost/api/v2/"
        - "https://localhost/"
        - "http://localhost/api/v2/ping/"
        - "http://localhost/"

    - name: Display alternative URL results
      ansible.builtin.debug:
        msg: "URL {{ item.item }}: Status {{ item.status }}"
      loop: "{{ alt_urls.results }}"

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
      retries: 20
      delay: 10

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
echo "Installing Ansible collections..."
ansible-galaxy collection install community.general --force
ansible-galaxy collection install microsoft.ad --force

# Try to install ansible.controller with specific version first, then fallback to latest
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

# Install Python packages
pip3 install pywinrm

# Fix Gitea repository issues first
echo "=== Fixing Gitea Repository ==="
echo "Waiting for Gitea to be ready..."
sleep 10

echo "Checking if student user exists in Gitea..."
STUDENT_EXISTS=$(curl -s -u 'gitea:gitea' http://gitea:3000/api/v1/users/student)
if [[ "$STUDENT_EXISTS" == *"student"* ]]; then
    echo "✅ Student user already exists in Gitea"
else
    echo "❌ Student user does not exist, creating..."
    curl -X POST -H "accept: application/json" -H "Content-Type: application/json" \
      -u 'gitea:gitea' \
      -d '{"username": "student", "password": "learn_ansible", "email": "student@acme.example.com", "must_change_password": false}' \
      http://gitea:3000/api/v1/admin/users
    echo "Student user creation attempted"
fi

echo "Checking if repository exists in Gitea..."
REPO_EXISTS=$(curl -s -u 'gitea:gitea' http://gitea:3000/api/v1/repos/student/workshop_project)
if [[ "$REPO_EXISTS" == *"workshop_project"* ]]; then
    echo "✅ Repository already exists in Gitea"
else
    echo "❌ Repository does not exist, creating..."
    curl -X POST -H "accept: application/json" -H "Content-Type: application/json" \
      -u 'gitea:gitea' \
      -d '{"name": "workshop_project", "description": "Windows Getting Started Workshop", "private": false}' \
      http://gitea:3000/api/v1/user/repos
    echo "Repository creation attempted"
fi

# Execute the controller setup
echo "=== Running AAP Controller Setup ==="
echo "Running controller setup playbook..."
ansible-playbook /tmp/controller-setup.yml -i /tmp/inventory.ini -e @/tmp/track-vars.yml -v

# Final verification
echo "=== Final Verification ==="
echo "Checking Gitea repository..."
curl -s -u 'gitea:gitea' http://gitea:3000/api/v1/repos/student/workshop_project | grep -q "workshop_project" && echo "✅ Gitea repository exists" || echo "❌ Gitea repository missing"

echo "Checking AAP student user..."
curl -s -k https://localhost/api/v2/ping/ -u student:learn_ansible > /dev/null && echo "✅ AAP student user works" || echo "❌ AAP student user not working"

echo ""
echo "=== Setup Complete ==="
echo "✅ Gitea: http://gitea:3000 (student:learn_ansible)"
echo "✅ AAP: https://localhost (student:learn_ansible)"
echo "✅ Repository: workshop_project should be visible in Gitea"

# Install additional tools
sudo dnf clean all
sudo dnf install -y ansible-navigator ansible-lint nc
pip3.9 install yamllint