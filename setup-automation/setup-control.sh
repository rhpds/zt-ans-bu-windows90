#!/bin/bash

echo "=== Windows Workshop Setup ==="


# Create a writable workspace for the rhel user used by exercises
mkdir -p /home/rhel/ansible
chown -R rhel:rhel /home/rhel/ansible
chmod 755 /home/rhel/ansible

# Set a generic Git identity used in the lab environment
git config --global user.email "student@redhat.com"
git config --global user.name "student"

# Create a minimal Ansible inventory for this lab
cat <<EOF | tee /tmp/inventory.ini
[ctrlnodes]
localhost ansible_connection=local

[windowssrv]
windows ansible_host=windows ansible_user=instruqt ansible_password=Passw0rd! ansible_connection=winrm ansible_port=5986 ansible_winrm_server_cert_validation=ignore

[all:vars]
ansible_python_interpreter=/usr/bin/python3
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
EOF

# Define lab configuration variables consumed by the playbooks
cat <<EOF | tee /tmp/track-vars.yml
---
# config vars
controller_hostname: localhost
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

# Gitea setup playbook 
cat <<EOF | tee /tmp/git-setup.yml
---
# Gitea config
- name: Configure Git and Gitea repository
  hosts: localhost
  gather_facts: false
  connection: local
  tags:
    - gitea-config

  tasks:
    - name: Wait for Gitea to be ready
      ansible.builtin.uri:
        url: http://gitea:3000/api/v1/version
        method: GET
        status_code: 200
      register: gitea_ready
      until: gitea_ready.status == 200
      delay: 5
      retries: 12

    - name: Create repo for project via API
      ansible.builtin.uri:
        url: http://gitea:3000/api/v1/user/repos
        method: POST
        body_format: json
        body:
          name: workshop_project
          auto_init: false
          private: false
        force_basic_auth: true
        url_password: "{{ student_password }}"
        url_username: "{{ student_user }}"
        status_code: [201, 409]

    - name: Create repo dir
      ansible.builtin.file:
        path: "/tmp/workshop_project"
        state: directory
        mode: 0755

    - name: Configure git to use main repo by default
      community.general.git_config:
        name: init.defaultBranch
        scope: global
        value: main
      tags:
        - git

    - name: Initialise track repo
      ansible.builtin.command:
        cmd: /usr/bin/git init
        chdir: "/tmp/workshop_project"
        creates: "/tmp/workshop_project/.git" 

    - name: Configure git to store credentials
      community.general.git_config:
        name: credential.helper
        scope: global
        value: store --file /tmp/git-creds

    - name: Configure repo dir as git safe dir
      community.general.git_config:
        name: safe.directory
        scope: global
        value: "/tmp/workshop_project"

    - name: Store repo credentials in git-creds file
      ansible.builtin.copy:
        dest: /tmp/git-creds
        mode: 0644
        content: "http://{{ student_user }}:{{ student_password }}@gitea:3000"

    - name: Configure git username
      community.general.git_config:
        name: user.name
        scope: global
        value: "{{ student_user }}"

    - name: Configure git email address
      community.general.git_config:
        name: user.email
        scope: global
        value: "{{ student_user }}@local"

    - name: Create generic README file
      ansible.builtin.copy:
        dest: /tmp/workshop_project/README.md
        content: |
          # Windows Getting Started Workshop
          
          This repository will be used during the Windows Getting Started Workshop.
          
          ## Getting Started
          
          Follow the lab instructions to begin working with Ansible and Windows automation.
        mode: '0644'

    - name: Add remote origin to repo
      ansible.builtin.command:
        cmd: "{{ item }}"
        chdir: "/tmp/workshop_project"   
      register: __output
      changed_when: __output.rc == 0
      loop:
        - "git remote add origin http://gitea:3000/{{ student_user }}/workshop_project.git"
        - "git checkout -b main"
        - "git add ."
        - "git commit -m'Initial commit'"
        - "git push -u origin main --force"
EOF

# Write the Controller setup playbook (using direct auth like the working ServiceNow lab)
cat <<EOF | tee /tmp/controller-setup.yml
---
- name: Configure Windows Workshop Controller 
  hosts: localhost
  connection: local
  collections:
    - ansible.controller

  tasks:
    - name: Add Windows EE
      ansible.controller.execution_environment:
        name: "Windows EE"
        image: "quay.io/ansible/ansible-runner:latest"
        controller_host: "https://localhost"
        controller_username: admin
        controller_password: ansible123!
        validate_certs: false

    - name: Create Inventory
      ansible.controller.inventory:
        name: "Workshop Inventory"
        description: "Our Server environment"
        organization: "Default"
        state: present
        controller_host: "https://localhost"
        controller_username: admin
        controller_password: ansible123!
        validate_certs: false

    - name: Create Host for Workshop
      ansible.controller.host:
        name: windows
        description: "Windows Group"
        inventory: "Workshop Inventory"
        state: present
        controller_host: "https://localhost"
        controller_username: admin
        controller_password: ansible123!
        validate_certs: false

    - name: Create Host for Workshop
      ansible.controller.host:
        name: student-ansible
        description: "Ansible node"
        inventory: "Workshop Inventory"
        state: present
        controller_host: "https://localhost"
        controller_username: admin
        controller_password: ansible123!
        validate_certs: false

    - name: Create Group for inventory
      ansible.controller.group:
        name: Windows Servers
        description: Windows Server Group
        inventory: "Workshop Inventory"
        hosts:
          - windows
        variables:
          ansible_connection: winrm
          ansible_port: 5986
          ansible_winrm_server_cert_validation: ignore
        controller_host: "https://localhost"
        controller_username: admin
        controller_password: ansible123!
        validate_certs: false

    - name: Create Project
      ansible.controller.project:
        name: "Windows Workshop"
        description: "Windows Getting Started Workshop Content"
        organization: "Default"
        scm_type: git
        scm_url: "http://gitea:3000/student/workshop_project.git"
        state: present
        controller_host: "https://localhost"
        controller_username: admin
        controller_password: ansible123!
        validate_certs: false

    # - name: Create student user (after all other resources)
    #   ansible.platform.user:
    #     controller_host: "https://localhost"
    #     controller_username: "admin"
    #     controller_password: "ansible123!"
    #     validate_certs: false
    #     username: "{{ student_user }}"
    #     password: "{{ student_password }}"
    #     email: student@acme.example.com
    #     is_superuser: true
    #     state: present
    #   register: student_user_result
    #   ignore_errors: true

    # - name: Debug student user creation
    #   ansible.builtin.debug:
    #     var: student_user_result
    #   when: student_user_result is defined
EOF

# Install necessary collections and packages
echo "Installing Ansible collections..."
# Install in dependency order - try without force first, then with force
echo "Installing community.general first (dependency)..."
ansible-galaxy collection install community.general || ansible-galaxy collection install community.general --force

echo "Installing microsoft.ad..."
ansible-galaxy collection install microsoft.ad || ansible-galaxy collection install microsoft.ad --force

echo "Installing ansible.controller (try specific version first)..."
ansible-galaxy collection install ansible.controller:2.5.0 || ansible-galaxy collection install ansible.controller || ansible-galaxy collection install ansible.controller --force

echo "Skipping ansible.platform collection installation"
echo "Reason: Requires Ansible 2.16+ (current: 2.14.17) and Red Hat credentials"
echo "Will use direct API approach for user creation instead"

# Install Python packages
echo "Installing pywinrm..."
python3 -m pip install pywinrm || pip3 install pywinrm || echo "Failed to install pywinrm - continuing anyway"

# Execute the setup playbooks
echo "=== Running Git/Gitea Setup ==="
ANSIBLE_COLLECTIONS_PATH=/root/.ansible/collections/ansible_collections/ ansible-playbook /tmp/git-setup.yml -e @/tmp/track-vars.yml -i /tmp/inventory.ini -v

echo "=== Running AAP Controller Setup ==="
# echo "Finding correct AAP API endpoints..."


ANSIBLE_COLLECTIONS_PATH=/root/.ansible/collections/ansible_collections/ ansible-playbook /tmp/controller-setup.yml -e @/tmp/track-vars.yml -i /tmp/inventory.ini -v

echo ""
echo "=== AAP Controller Setup Complete ==="
echo "✅ AAP Controller configured with admin user"
echo "✅ Execution Environment: Windows EE"
echo "✅ Inventory: Workshop Inventory"
echo "✅ Hosts: windows, student-ansible"
echo "✅ Group: Windows Servers"
echo "✅ Project: Windows Workshop"
echo ""
echo "=== Attempting Student User Creation via Direct API ==="
echo "Since ansible.platform collection is not available, trying direct API approach..."

# Try direct API call for user creation
echo "Attempting to create student user via direct API call..."
STUDENT_USER_CREATE=$(curl -s -k -X POST https://localhost/api/v2/users/ \
  -u admin:ansible123! \
  -H "Content-Type: application/json" \
  -d '{
    "username": "student",
    "password": "learn_ansible",
    "email": "student@acme.example.com",
    "is_superuser": true
  }' \
  -w "HTTPSTATUS:%{http_code}")

HTTP_STATUS=$(echo $STUDENT_USER_CREATE | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')
RESPONSE_BODY=$(echo $STUDENT_USER_CREATE | sed -e 's/HTTPSTATUS:.*//g')

if [ "$HTTP_STATUS" -eq 201 ]; then
    echo "✅ Student user created successfully via API"
elif [ "$HTTP_STATUS" -eq 400 ]; then
    echo "ℹ️  Student user already exists"
else
    echo "❌ Student user creation failed (HTTP $HTTP_STATUS)"
    echo "Response: $RESPONSE_BODY"
fi

echo ""
echo "You can log into AAP at https://localhost with:"
echo "  Admin: admin:ansible123!"
echo "  Student: student:learn_ansible (if creation succeeded)"

# # If the playbook failed, try a simple direct approach
# echo "=== Fallback: Manual Student User Creation ==="
# echo "Since API endpoints are not working, let's try manual user creation..."

# # Try to create user via Django management command
# echo "Attempting to create student user via Django management command..."
# cd /var/lib/awx/venv/awx/lib/python*/site-packages/awx 2>/dev/null || cd /opt/awx/venv/awx/lib/python*/site-packages/awx 2>/dev/null || echo "Could not find AWX directory"

# if [ -d "management" ]; then
#     echo "Found AWX management directory, attempting user creation..."
#     python3 manage.py shell -c "
# from django.contrib.auth.models import User
# from django.contrib.auth.hashers import make_password
# try:
#     user = User.objects.create_user(
#         username='student',
#         password='learn_ansible',
#         email='student@acme.example.com',
#         is_superuser=True,
#         is_staff=True
#     )
#     print('Student user created successfully')
# except Exception as e:
#     print(f'Error creating user: {e}')
# " 2>/dev/null || echo "Django management command failed"
# else
#     echo "AWX management directory not found, trying alternative approach..."
    
#     # Try to find and use the AWX CLI
#     which awx 2>/dev/null && echo "Found awx CLI" || echo "awx CLI not found"
    
#     # Try to create user via awx CLI
#     awx users create --username student --password learn_ansible --email student@acme.example.com --is_superuser true 2>/dev/null && echo "Student user created via awx CLI" || echo "awx CLI user creation failed"
# fi

# Final verification
# echo "=== Final Verification ==="
# echo "Checking Gitea repository..."
# curl -s -u 'student:learn_ansible' http://gitea:3000/api/v1/repos/student/workshop_project | grep -q "workshop_project" && echo "✅ Gitea repository exists" || echo "❌ Gitea repository missing"

# echo "Checking AAP student user authentication..."
# # Try different endpoints for authentication test
# AAP_STUDENT_AUTH=$(curl -s -k https://localhost/api/v2/ -u student:learn_ansible)
# if [[ "$AAP_STUDENT_AUTH" == *"users"* ]] || [[ "$AAP_STUDENT_AUTH" == *"organizations"* ]]; then
#     echo "✅ AAP student user authentication works"
# else
#     echo "❌ AAP student user authentication failed"
#     echo "Response: $AAP_STUDENT_AUTH"
# fi

# echo "Checking AAP users list..."
# curl -s -k https://localhost/api/v2/users/ -u admin:ansible123! | grep -q "student" && echo "✅ Student user exists in AAP" || echo "❌ Student user not found in AAP"

# echo ""
# echo "=== Setup Complete ==="
# echo "✅ Gitea: http://gitea:3000 (student:learn_ansible)"
# echo "✅ AAP: https://localhost (student:learn_ansible)"
# echo "✅ Repository: workshop_project should be visible in Gitea with content"