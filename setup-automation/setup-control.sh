############################ CONTROLLER CONFIG

cat <<EOF | tee /tmp/controller-setup.yml
## Controller setup
- name: Controller config for Windows Getting Started
  hosts: controller.acme.example.com
  gather_facts: true
    
  tasks:
   # Create auth login token
    - name: get auth token and restart automation-controller if it fails
      block:
        - name: Refresh facts
          setup:

        - name: Create oauth token
          ansible.controller.token:
            description: 'Instruqt lab'
            scope: "write"
            state: present
            controller_host: controller
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
            description: 'Instruqt lab'
            scope: "write"
            state: present
            controller_host: controller
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
            owner: "{{ ansible_user }}"
            group: "{{ ansible_user }}"
            mode: 0755
          become: true

        - name: Create _auth_token custom fact
          ansible.builtin.copy:
            content: "{{ _auth_token.ansible_facts }}"
            dest: "{{ custom_facts_dir }}/{{ custom_facts_file }}"
            owner: "{{ ansible_user }}"
            group: "{{ ansible_user }}"
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
        validate_certs: false
      tags:
        - controller-config
        - controller-org
  
    - name: Add Instruqt Windows EE
      ansible.controller.execution_environment:
        name: "{{ controller_ee }}"
        image: "quay.io/nmartins/windows_ee"
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
        superuser: true
        username: "{{ student_user }}"
        password: "{{ student_password }}"
        email: student@acme.example.com
        controller_oauthtoken: "{{ auth_token }}"
        controller_host: "{{ controller_hostname }}"
        validate_certs: "{{ controller_validate_certs }}"
      tags:
        - controller-config
        - controller-users

    - name: Create Inventory
      ansible.controller.inventory:
       name: "Workshop Inventory"
       description: "Our Server environment"
       organization: "Default"
       state: present
       controller_config_file: "/tmp/controller.cfg"

    - name: Create Host for Workshop
      ansible.controller.host:
       name: windows
       description: "Windows Group"
       inventory: "Workshop Inventory"
       state: present
       controller_config_file: "/tmp/controller.cfg"

    - name: Create Host for Workshop
      ansible.controller.host:
       name: student-ansible
       description: "Ansible node"
       inventory: "Workshop Inventory"
       state: present
       controller_config_file: "/tmp/controller.cfg"

    - name: Create Group for inventory
      ansible.controller.group:
       name: Windows
       description: Windows Server Group
       inventory: "Workshop Inventory"
       hosts:
        - windows
       variables:
         ansible_connection: winrm
         ansible_port: 5986
         ansible_winrm_server_cert_validation: ignore
       controller_config_file: "/tmp/controller.cfg"

     
       
EOF

cat <<EOF | tee /tmp/controller.cfg
host: localhost
username: admin
password: ansible123!
verify_ssl = false
EOF


ansible-galaxy collection install microsoft.ad
pip3 install pywinrm

##### Executing:

chmod +x /tmp/lab-setup.sh

#sh /tmp/lab-setup.sh
sh /tmp/lab-setup.sh

sudo dnf clean all
sudo dnf install -y ansible-navigator
sudo dnf install -y ansible-lint
sudo dnf install -y nc
pip3.9 install yamllint
