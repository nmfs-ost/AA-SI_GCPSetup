# Post-Build Setup Instructions

This guide walks you through setting up your development environment after a build. It includes setting permissions, executing the `init.sh` script, activating the Python virtual environment, authenticating with Google Cloud, and running validation tests.

---

## 🚀 Step-by-Step Instructions


### 1. Download and Run Initialization Script -> Activate AA-SI enviornment -> Authenticate

```bash
sudo wget https://raw.githubusercontent.com/spacetimeengineer/AA-SI_init/main/init.sh && \
sudo chmod +x init.sh && \
./init.sh && \
cd ~ && \
source aa_lab/bin/activate && \
gcloud auth application-default login && \
gcloud config set account {ACCOUNT} && \ 
gcloud config set project ggn-nmfs-aa-dev-1 
```

Follow the browser-based instructions to complete authentication.

---

### 2. Explore Available Commands

Run the following to see available operations:

```bash
aa-help
```

This will list available tools, scripts, or modules you can run within the environment.

---

## ✅ You're Ready!

You’ve completed the setup and verified that everything is working. You can now start using the tools provided in your environment.

---

# Disclaimer
This repository is a scientific product and is not official communication of the National Oceanic and Atmospheric Administration, or the United States Department of Commerce. All NOAA GitHub project code is provided on an ‘as is’ basis and the user assumes responsibility for its use. Any claims against the Department of Commerce or Department of Commerce bureaus stemming from the use of this GitHub project will be governed by all applicable Federal law. Any reference to specific commercial products, processes, or services by service mark, trademark, manufacturer, or otherwise, does not constitute or imply their endorsement, recommendation or favoring by the Department of Commerce. The Department of Commerce seal and logo, or the seal and logo of a DOC bureau, shall not be used in any manner to imply endorsement of any commercial product or activity by DOC or the United States Government.
