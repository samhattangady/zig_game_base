@echo off
set executable=zig-out\bin\antbotics.exe
set dll_lib=zig-out\lib\antgineering.dll
if exist %executable% (del %executable%)
if exist %dll_lib% (del %dll_lib%)
rem Some issue with the dynamic exe that doesn't give us crash logs correctly.
rem call timecmd current_zig build -Dbuild_mode=dynamic_exe %*
rem if exist %executable% if exist %dll_lib% (call %executable%)
call timecmd current_zig build  %*
if exist %executable% (call %executable%)
goto :done

:done
