
# 📘 GCP Workstation Setup Guide: **AA-SI Environment**

This guide provides step-by-step instructions to set up a Google Cloud Platform (GCP) Workstation for use with the **AA-SI (Advanced Acoustics - Scientific Integration)** toolset.

---

## 🚀 Step-by-Step Setup Instructions

This setup asdsumes you maintain a NOAA gmail account and you have been authorized to deploy GCP workstations hosted by nmfs - Office of Science and Technology.

### 1️⃣ Navigate to the GCP Workstations Console  
Go to:  
🔗 [https://console.cloud.google.com/workstations/overview](https://console.cloud.google.com/workstations/overview)

---

### 2️⃣ Create a Workstation  
Use the GCP interface to configure and create your workstation:

![Create Workstation](assets/instruction_4.png)

---

### 3️⃣ Launch the Workstation  
Once created, launch your workstation:

![Launch Workstation](assets/instruction_5.png)

---

### 4️⃣ Open the Terminal  
Click to open a terminal session inside the running GCP workstation:

![Open Terminal](assets/instruction_2.png)

---

## ⚙️ Initialization Script

This command block will:

- Download the AA-SI initialization script  
- Set the appropriate permissions  
- Execute the script  
- Activate the Python virtual environment  
- Start GCP authentication

Paste and run the following in your terminal:

```bash
cd /opt && \
sudo rm -f init.sh && \
sudo wget https://raw.githubusercontent.com/nmfs-ost/AA-SI_GPCSetup/main/init.sh && \
sudo chmod +x init.sh && \
./init.sh && \
cd ~ && \
source aa_si/bin/activate && \
gcloud auth application-default login && \
gcloud config set account {{ACCOUNT}} && \
gcloud config set project ggn-nmfs-aa-dev-1
```

📌 **Note**: Replace `{{ACCOUNT}}` with your NOAA Google account email.

![Terminal Authentication](assets/instruction_3.png)

If needed later, you can always reactivate the environment using:

```bash
source aa_si/bin/activate
```

Follow the browser prompts to authenticate via your NOAA Google credentials.

---

## 🐟 Using the AA-SI Environment

### 🔍 View Available Tools

To see available AA-SI commands and modules, run:

```bash
aa-help
```

---

### 📈 Example: Download & Plot Raw File

```bash
aa-raw --file_name "2107RL_CW-D20210813-T220732.raw" --file_type "raw" --ship_name "Reuben_Lasker" --survey_name "RL2107" --echosounder "EK80" --data_source "NCEI" | aa-plot
```

---

## 📜 Disclaimer

This repository is a scientific product and is not official communication of the National Oceanic and Atmospheric Administration, or the United States Department of Commerce. All NOAA GitHub project code is provided on an ‘as is’ basis and the user assumes responsibility for its use. Any claims against the Department of Commerce or Department of Commerce bureaus stemming from the use of this GitHub project will be governed by all applicable Federal law. Any reference to specific commercial products, processes, or services by service mark, trademark, manufacturer, or otherwise, does not constitute or imply their endorsement, recommendation or favoring by the Department of Commerce. The Department of Commerce seal and logo, or the seal and logo of a DOC bureau, shall not be used in any manner to imply endorsement of any commercial product or activity by DOC or the United States Government.
