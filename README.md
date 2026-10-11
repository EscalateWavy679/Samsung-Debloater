See upstream readme

This Mac fork adds a bash script to replace the .bat

You should not use the bash script. It is a vibecoded port and has never been reviewed by a human.

Prerequisites:

1. Install minimal ADB CLI (not the whole SDK) from Homebrew: `brew install android-platform-tools`
2. Run `adb` once. There will be a warning. Then go to System Settings -> Privacy & Security -> Security.  Find ADB and click "Run Anyway".  **NOTE THIS IS A SECURITY RISK. VALIDATE THE ADB BINARY IS SAFE BEFORE DOING THIS.**
3. Enable developer mode on the phone.
4. Connect USB. Unlock phone screen. Accept a million disclaimers on the phone.
5. `./Samsung_Debloater.sh`
6. `1`
7. `YES`
8. Take out the trash: `brew uninstall android-platform-tools && brew autoremove && brew cleanup`
