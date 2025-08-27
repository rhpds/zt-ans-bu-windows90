
#. { iwr -useb https://raw.githubusercontent.com/nmartins0611/windows_getting_started_instruqt/main/winrm_setup.ps1 -OutFile .\winrm_setup.ps1 } 

Invoke-WebRequest -Uri https://raw.githubusercontent.com/nmartins0611/windows_getting_started_instruqt/main/winrm_setup.ps1 -OutFile .\winrm_setup.ps1; .\winrm_setup.ps1