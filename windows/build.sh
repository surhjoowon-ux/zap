#!/bin/zsh
# zap Windows판 빌드 → dist/zap-windows.zip (zap.exe 하나)
# 맥에서도 됨: .NET 8 SDK만 있으면 .NET Framework 4.8용 exe가 나온다.
set -e
cd "$(dirname "$0")"
DOTNET=$(command -v dotnet || echo ~/.dotnet/dotnet)
DOTNET_CLI_TELEMETRY_OPTOUT=1 "$DOTNET" build -c Release -nologo
mkdir -p ../dist && rm -f ../dist/zap-windows.zip
(cd bin/Release && zip -q ../../../dist/zap-windows.zip zap.exe)
echo "완료: dist/zap-windows.zip"
