@echo off
call timecmd current_zig build -Dbuild_mode=hotreload %*
if errorlevel 1 goto :compilefail
rem we play the success sound from the executable, so that it only plays once the
rem dll has been reloaded
goto :done

:compilefail
call playsound local\audio\compile_fail.mp3
goto :done

:done
