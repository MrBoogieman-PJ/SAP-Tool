# SAP Logon Repair GUI

A Windows PowerShell GUI for checking SAP GUI and landscape access, setting SAP's XML configuration path for the current user, running a refresh utility, and reopening SAP Logon.

## Configure

Copy `SAP_Logon_Repair.config.example.json` to `SAP_Logon_Repair.config.json` and set the required SAP GUI version, landscape share, XML file path, and local support instructions. The local configuration file is ignored by Git and should not be committed.

Run `Run_SAP_Logon_Repair_GUI.bat` to open the tool. The script uses Windows PowerShell and Windows Forms.

## Clone in PowerShell

```powershell
git clone https://github.com/MrBoogieman-PJ/SAP-Tool.git
Set-Location .\SAP-Tool
Copy-Item .\SAP_Logon_Repair.config.example.json .\SAP_Logon_Repair.config.json
notepad .\SAP_Logon_Repair.config.json
```

To download later changes from GitHub:

```powershell
Set-Location .\SAP-Tool
git pull
```