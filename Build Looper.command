#!/bin/bash
# Double-click in Finder to build Looper (arm64 + x86_64) and open the result.
cd "$(dirname "$0")"
./build_local.sh --open && open "build/$(grep -o 'static let version = "[^"]*"' Sources/Looper/Model/LooperController.swift | cut -d'"' -f2)"
echo
read -n 1 -s -r -p "Done. Press any key to close this window."
