@echo off
set "SRC=%~dp0"

start /w "" "%SRC%setupssh-7.3p1-2-cygwin252.exe" /S /password=rotartsinimda /port=22 /D=C:\OpenSSH

netsh firewall add portopening TCP 22 OpenSSH

net start opensshd
