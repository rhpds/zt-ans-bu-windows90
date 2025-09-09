#!/bin/bash

echo "=== Windows Workshop Setup - Converting from Instruqt Pattern ==="

# Copy root's SSH keys into the rhel user's home so Ansible/Git can authenticate
if [ -d "/root/.ssh" ] && [ "$(ls -A /root/.ssh)" ]; then
    cp -a /root/.ssh/* /home/rhel/.ssh/.
    chown -R rhel:rhel /home/rhel/.ssh
    echo "✅ SSH keys copied successfully"
else
    echo "⚠️  No SSH keys found in /root/.ssh, generating new ones..."
    su - rhel -c 'ssh-keygen -f /home/rhel/.ssh/id_rsa -q -N ""'
    chown -R rhel:rhel /home/rhel/.ssh
fi

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

# Write the Git/Gitea setup playbook (using localhost instead of gitea host)
cat <<EOF | tee /tmp/git-setup.yml
---
# Gitea config - using localhost and direct API calls
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

# Write the Controller setup playbook (using roadshow approach)
cat <<EOF | tee /tmp/controller-setup.yml
---
## Controller setup - using roadshow approach
- name: Controller config for Windows Getting Started
  hosts: localhost
  gather_facts: true
  collections:
    - ansible.controller
    
  tasks:
   # Create auth login token
    - name: get auth token and restart automation-controller if it fails
      block:
        - name: Refresh facts
          setup:

        - name: Create oauth token
          ansible.controller.token:
            description: 'Windows Workshop lab'
            scope: "write"
            state: present
            controller_host: localhost
            controller_username: "{{ controller_admin_user }}"
            controller_password: "{{ controller_admin_password }}"
            validate_certs: false
          register: _auth_token
          until: _auth_token is not failed
          delay: 3
          retries: 5
      rescue:
        - name: In rescue block for auth token
          debug:
            msg: "failed to get auth token. Restarting automation controller service"

        - name: restart the controller service
          ansible.builtin.service:
            name: automation-controller
            state: restarted

        - name: Ensure tower/controller is online and working
          uri:
            url: https://localhost/api/v2/ping/
            method: GET
            user: "{{ admin_username }}"
            password: "{{ admin_password }}"
            validate_certs: false
            force_basic_auth: true
          register: controller_online
          until: controller_online is success
          delay: 3
          retries: 5

        - name: Retry getting auth token
          ansible.controller.token:
            description: 'Windows Workshop lab'
            scope: "write"
            state: present
            controller_host: localhost
            controller_username: "{{ controller_admin_user }}"
            controller_password: "{{ controller_admin_password }}"
            validate_certs: false
          register: _auth_token
          until: _auth_token is not failed
          delay: 3
          retries: 5
      always:
        - name: Create fact.d dir
          ansible.builtin.file:
            path: "{{ custom_facts_dir }}"
            state: directory
            recurse: yes
            owner: "rhel"
            group: "rhel"
            mode: 0755
          become: true

        - name: Create _auth_token custom fact
          ansible.builtin.copy:
            content: "{{ _auth_token.ansible_facts }}"
            dest: "{{ custom_facts_dir }}/{{ custom_facts_file }}"
            owner: "rhel"
            group: "rhel"
            mode: 0644
          become: true
      check_mode: false
      when: ansible_local.custom_facts.controller_token is undefined
      tags:
        - auth-token

    - name: refresh facts
      setup:
        filter:
          - ansible_local
      tags:
        - always

    - name: create auth token fact
      ansible.builtin.set_fact:
        auth_token: "{{ ansible_local.custom_facts.controller_token }}"
        cacheable: true
      check_mode: false
      when: auth_token is undefined
      tags:
        - always
 
    - name: Ensure tower/controller is online and working
      uri:
        url: https://localhost/api/v2/ping/
        method: GET
        user: "{{ admin_username }}"
        password: "{{ admin_password }}"
        validate_certs: false
        force_basic_auth: true
      register: controller_online
      until: controller_online is success
      delay: 3
      retries: 5
      tags:
        - controller-config

# Controller objects
    - name: Add Organization
      ansible.controller.organization:
        name: "{{ lab_organization }}"
        description: "ACME Corp Organization"
        state: present
        controller_oauthtoken: "{{ auth_token }}"
        controller_host: "{{ controller_hostname }}"
        validate_certs: false
      tags:
        - controller-config
        - controller-org
  
    - name: Add Windows EE
      ansible.controller.execution_environment:
        name: "{{ controller_ee }}"
        image: "quay.io/ansible/ansible-runner:latest"
        pull: missing
        state: present
        controller_oauthtoken: "{{ auth_token }}"
        controller_host: "{{ controller_hostname }}"
        validate_certs: "{{ controller_validate_certs }}"
      tags:
        - controller-config
        - controller-ees

    - name: Create student admin user
      ansible.controller.user:
        username: "{{ student_user }}"
        password: "{{ student_password }}"
        email: student@acme.example.com
        is_superuser: true
        state: present
        controller_oauthtoken: "{{ auth_token }}"
        controller_host: "{{ controller_hostname }}"
        validate_certs: "{{ controller_validate_certs }}"
      register: student_user_result
      tags:
        - controller-config
        - controller-users

    - name: Debug student user creation
      ansible.builtin.debug:
        var: student_user_result
      tags:
        - controller-config
        - controller-users

    - name: Create Inventory
      ansible.controller.inventory:
       name: "Workshop Inventory"
       description: "Our Server environment"
       organization: "Default"
       state: present
       controller_oauthtoken: "{{ auth_token }}"
       controller_host: "{{ controller_hostname }}"
       validate_certs: "{{ controller_validate_certs }}"

    - name: Create Host for Workshop
      ansible.controller.host:
       name: windows
       description: "Windows Group"
       inventory: "Workshop Inventory"
       state: present
       controller_oauthtoken: "{{ auth_token }}"
       controller_host: "{{ controller_hostname }}"
       validate_certs: "{{ controller_validate_certs }}"

    - name: Create Host for Workshop
      ansible.controller.host:
       name: student-ansible
       description: "Ansible node"
       inventory: "Workshop Inventory"
       state: present
       controller_oauthtoken: "{{ auth_token }}"
       controller_host: "{{ controller_hostname }}"
       validate_certs: "{{ controller_validate_certs }}"

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
       controller_oauthtoken: "{{ auth_token }}"
       controller_host: "{{ controller_hostname }}"
       validate_certs: "{{ controller_validate_certs }}"

    - name: Create Project
      ansible.controller.project:
        name: "Windows Workshop"
        description: "Windows Getting Started Workshop Content"
        organization: "Default"
        scm_type: git
        scm_url: "http://gitea:3000/student/workshop_project.git"
        state: present
        controller_oauthtoken: "{{ auth_token }}"
        controller_host: "{{ controller_hostname }}"
        validate_certs: "{{ controller_validate_certs }}"
EOF

# Install necessary collections and packages
echo "Installing Ansible collections..."
ansible-galaxy collection install ansible.controller --force
ansible-galaxy collection install community.general --force
ansible-galaxy collection install microsoft.ad --force

# Install Python packages
pip3 install pywinrm

# Execute the setup playbooks
echo "=== Running Git/Gitea Setup ==="
ansible-playbook /tmp/git-setup.yml -e @/tmp/track-vars.yml -i /tmp/inventory.ini -v

echo "=== Running AAP Controller Setup ==="
echo "Finding correct AAP API endpoints..."

# Try different possible API endpoints
echo "Testing various API endpoints:"
curl -k https://localhost/api/v2/ -u admin:ansible123! > /dev/null 2>&1 && echo "✅ /api/v2/ works" || echo "❌ /api/v2/ fails"
curl -k https://localhost/api/ -u admin:ansible123! > /dev/null 2>&1 && echo "✅ /api/ works" || echo "❌ /api/ fails"
curl -k https://localhost/api/v1/ -u admin:ansible123! > /dev/null 2>&1 && echo "✅ /api/v1/ works" || echo "❌ /api/v1/ fails"
curl -k https://localhost/ansible/ -u admin:ansible123! > /dev/null 2>&1 && echo "✅ /ansible/ works" || echo "❌ /ansible/ fails"
curl -k https://localhost/awx/ -u admin:ansible123! > /dev/null 2>&1 && echo "✅ /awx/ works" || echo "❌ /awx/ fails"

# Check what the web interface shows
echo "Checking web interface response:"
curl -k https://localhost/ -u admin:ansible123! 2>/dev/null | head -20

ansible-playbook /tmp/controller-setup.yml -e @/tmp/track-vars.yml -i /tmp/inventory.ini -v

# If the playbook failed, try a simple direct approach
echo "=== Fallback: Manual Student User Creation ==="
echo "Since API endpoints are not working, let's try manual user creation..."

# Try to create user via Django management command
echo "Attempting to create student user via Django management command..."
cd /var/lib/awx/venv/awx/lib/python*/site-packages/awx 2>/dev/null || cd /opt/awx/venv/awx/lib/python*/site-packages/awx 2>/dev/null || echo "Could not find AWX directory"

if [ -d "management" ]; then
    echo "Found AWX management directory, attempting user creation..."
    python3 manage.py shell -c "
from django.contrib.auth.models import User
from django.contrib.auth.hashers import make_password
try:
    user = User.objects.create_user(
        username='student',
        password='learn_ansible',
        email='student@acme.example.com',
        is_superuser=True,
        is_staff=True
    )
    print('Student user created successfully')
except Exception as e:
    print(f'Error creating user: {e}')
" 2>/dev/null || echo "Django management command failed"
else
    echo "AWX management directory not found, trying alternative approach..."
    
    # Try to find and use the AWX CLI
    which awx 2>/dev/null && echo "Found awx CLI" || echo "awx CLI not found"
    
    # Try to create user via awx CLI
    awx users create --username student --password learn_ansible --email student@acme.example.com --is_superuser true 2>/dev/null && echo "Student user created via awx CLI" || echo "awx CLI user creation failed"
fi

# Final verification
echo "=== Final Verification ==="
echo "Checking Gitea repository..."
curl -s -u 'student:learn_ansible' http://gitea:3000/api/v1/repos/student/workshop_project | grep -q "workshop_project" && echo "✅ Gitea repository exists" || echo "❌ Gitea repository missing"

echo "Checking AAP student user authentication..."
# Try different endpoints for authentication test
AAP_STUDENT_AUTH=$(curl -s -k https://localhost/api/v2/ -u student:learn_ansible)
if [[ "$AAP_STUDENT_AUTH" == *"users"* ]] || [[ "$AAP_STUDENT_AUTH" == *"organizations"* ]]; then
    echo "✅ AAP student user authentication works"
else
    echo "❌ AAP student user authentication failed"
    echo "Response: $AAP_STUDENT_AUTH"
fi

echo "Checking AAP users list..."
curl -s -k https://localhost/api/v2/users/ -u admin:ansible123! | grep -q "student" && echo "✅ Student user exists in AAP" || echo "❌ Student user not found in AAP"

echo ""
echo "=== Setup Complete ==="
echo "✅ Gitea: http://gitea:3000 (student:learn_ansible)"
echo "✅ AAP: https://localhost (student:learn_ansible)"
echo "✅ Repository: workshop_project should be visible in Gitea with content"