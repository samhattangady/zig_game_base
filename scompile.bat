@echo off
echo "might have to update sokol-shdc to new version"
rem compile shaders
sokol-shdc.exe --input src\shaders\standard.glsl --output src\shaders\standard.zig --slang glsl330:glsl300es:hlsl5 --format sokol_zig
