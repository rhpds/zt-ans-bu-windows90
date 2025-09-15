#!/bin/bash
echo "=== Windows Workshop Setup ==="

# Create a writable workspace for the rhel user used by exercises
mkdir -p /home/rhel/ansible
chown -R rhel:rhel /home/rhel/ansible
chmod 755 /home/rhel/ansible

# Set a generic Git identity used in the lab environment
git config --global user.email "student@redhat.com"
git config --global user.name "student"

# Create Ansible inventory
cat <<EOF | tee /tmp/inventory.ini
[ctrlnodes]
localhost ansible_connection=local

[windowssrv]
windows ansible_host=windows ansible_user=Administrator ansible_password=Ansible123! ansible_connection=winrm ansible_port=5986 ansible_winrm_scheme=https ansible_winrm_transport=ntlm ansible_winrm_server_cert_validation=ignore

[all:vars]
ansible_python_interpreter=/usr/bin/python3
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
EOF

# Create lab variables
cat <<EOF | tee /tmp/track-vars.yml
---
# config vars
controller_hostname: localhost
controller_validate_certs: false
ansible_python_interpreter: /usr/bin/python3
controller_ee: Windows Workshop Execution Environment
student_user: student
win_student_password: Passw0rd!
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
admin_windows_user: '.\\Administrator'
admin_windows_password: 'Ansible123!'
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

# Controller setup playbook
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
        name: "Windows Workshop Execution Environment"
        image: "quay.io/nmartins/windows_ee"
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
        name: Windows_Servers
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

    # - name: Create Project
    #   ansible.controller.project:
    #     name: "Windows Workshop"
    #     description: "Windows Getting Started Workshop Content"
    #     organization: "Default"
    #     scm_type: git
    #     scm_url: "http://gitea:3000/student/workshop_project.git"
    #     state: present
    #     controller_host: "https://localhost"
    #     controller_username: admin
    #     controller_password: ansible123!
    #     validate_certs: false

    # - name: Create student user
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

# Install necessary collections
ansible-galaxy collection install community.general
ansible-galaxy collection install microsoft.ad
ansible-galaxy collection install ansible.windows
ansible-galaxy collection install ansible.controller
ansible-galaxy collection install community.windows

# Install pip3 and pywinrm for Windows connectivity
dnf install -y python3-pip
pip3 install pywinrm

# Set collections path for playbook execution
export ANSIBLE_COLLECTIONS_PATH=/root/.ansible/collections/ansible_collections/

# Bootstrap Windows user using known admin credentials (best effort)
cat <<EOF | tee /tmp/windows-bootstrap.yml
---
- hosts: windows
  gather_facts: false
  vars:
    ansible_connection: winrm
    ansible_port: 5986
    ansible_winrm_scheme: https
    ansible_winrm_transport: ntlm
    ansible_winrm_server_cert_validation: ignore
    ansible_user: "{{ admin_windows_user }}"
    ansible_password: "{{ admin_windows_password }}"
  tasks:
    - name: Download WinRM setup script
      ansible.windows.win_get_url:
        url: https://raw.githubusercontent.com/nmartins0611/windows_getting_started_instruqt/main/winrm_setup.ps1
        dest: C:\\winrm_setup.ps1

    - name: Execute WinRM setup script
      ansible.windows.win_shell: PowerShell -ExecutionPolicy Bypass -File C:\\winrm_setup.ps1

    - name: Ensure student user exists
      ansible.windows.win_user:
        name: "{{ student_user }}"
        password: "{{ win_student_password }}"
        state: present
        password_never_expires: yes
    - name: Ensure student is local admin
      ansible.windows.win_group_membership:
        name: Administrators
        members:
          - "{{ student_user }}"
        state: present

    - name: Ensure .NET Framework 4.8 feature is installed
      ansible.windows.win_shell: |
        Import-Module ServerManager
        $feature = Get-WindowsFeature -Name NET-Framework-45-Features
        if (-not $feature.Installed) {
          Install-WindowsFeature -Name NET-Framework-45-Features -IncludeAllSubFeature -IncludeManagementTools
        }
      args:
        executable: powershell.exe

    - name: Install Chocolatey
      ansible.windows.win_shell: |
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
      args:
        executable: powershell.exe

    - name: Reboot after Chocolatey/.NET installation
      ansible.windows.win_reboot:
        msg: "Reboot to finalize Chocolatey/.NET installation"
        pre_reboot_delay: 5

    - name: Install Microsoft Edge via Chocolatey
      ansible.windows.win_shell: choco install microsoft-edge -y --no-progress
      args:
        executable: powershell.exe
EOF

# Execute the setup playbooks
echo "=== Running Git/Gitea Setup ==="
ansible-playbook /tmp/git-setup.yml -e @/tmp/track-vars.yml -i /tmp/inventory.ini -v

echo "=== Bootstrapping Windows local user (best effort) ==="
ansible-playbook /tmp/windows-bootstrap.yml -e @/tmp/track-vars.yml -i /tmp/inventory.ini -v || true

echo "=== Running AAP Controller Setup ==="
ansible-playbook /tmp/controller-setup.yml -e @/tmp/track-vars.yml -i /tmp/inventory.ini -v
