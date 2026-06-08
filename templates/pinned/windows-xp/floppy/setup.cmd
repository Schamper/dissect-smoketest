@echo off
for %%d in (D E F G H I J) do if exist "%%d:\setup-ssh.cmd" (
    call "%%d:\setup-ssh.cmd"
    goto :eof
)
