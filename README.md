# Lab Setup Instructions

> **Note:** Do not do this if you have already set a private key up before for a lab.

## Getting Started

1. Click **CREATE** to spin up the lab environment

2. Click **DOWNLOAD SSH KEY** button when they're enabled (lab is running)

3. Open a terminal in your local machine

4. On your terminal, go to your ssh folder:
   ```bash
   cd ~/.ssh
   ```

5. If it's not your first time doing this, you can skip this step and go to step 6.

6. Move the downloaded file to ~/.ssh, either with your files explorer or with the command line:
   ```bash
   mv ~/Downloads/rht_classroom.rsa ~/.ssh/
   chmod 0600 ~/.ssh/rht_classroom.rsa
   ssh-add ~/.ssh/rht_classroom.rsa
   ```

7. ssh into lab:
   ```bash
   ssh -i ~/.ssh/rht_classroom.rsa -J cloud-user@148.62.94.60:22022 student@172.25.252.1 -p 53009
   ```

You will be SSHing into the workstation VM as the student user. If you are asked for a password, use `student`