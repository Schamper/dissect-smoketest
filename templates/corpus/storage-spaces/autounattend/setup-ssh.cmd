@echo off
set "SRC=%~dp0"

start /w "" msiexec /i "%SRC%OpenSSH-Win64.msi" /qn /norestart

netsh advfirewall firewall add rule name=sshd dir=in action=allow protocol=TCP localport=22 profile=any

sc config sshd start= auto
net start sshd
