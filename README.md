# 🛠️ Compute Cluster Forge

Welcome to Compute Cluster Forge! This tool allows you to spin up highly secure, auto-healing, and cost-effective AI/ML compute clusters on demand.Currently, this project is configured for Google Cloud Platform (GCP), but the repository is architected to easily expand to AWS and Azure.

# 🌟 Features

This isn't a standard, brittle Terraform script. It implements industry-standard DevOps practices:

1. Zero-Trust Security (Google IAP): Instead of messing with public IPs or VPNs, this uses Google Identity-Aware Proxy. The firewall blocks all public traffic and only allows SSH connections tunneled through Google's secure OAuth servers. You can connect securely from a coffee shop, office, or home without changing configs.

2. Auto-Healing Spot Instances: By using an Instance Group Manager, we use Google's cheapest Spot VMs (saving up to 80%). If Google reclaims the VM, the Manager automatically spins up a replacement to resume your workload.

3. Decoupled Software Setup (Cloud-Init): Infrastructure is kept clean in .tf files, while software installations (Git, Python, CUDA drivers) are handled by a declarative cloud-init.yaml file on boot.

4. Persistent Data Sync: A dedicated Google Cloud Storage (GCS) bucket is spun up alongside your cluster. The VM is granted an IAM Service Account allowing it to automatically pull your latest scripts and data from this bucket when it boots.

# 📂 Repository Structure
```
/compute-cluster-forge
├── /modules                # The "How" (Cloud-specific Infrastructure)
│   ├── /aws                # Placeholder for AWS expansion
│   ├── /azure              # Placeholder for Azure expansion
│   └── /gcp                # Active GCP setup
│       ├── main.tf         # Core logic (Instance Groups, Firewalls)
│       ├── variables.tf    # Accepted inputs
│       ├── outputs.tf      # Console outputs
│       └── cloud-init.yaml # Server software setup script
├── run.sh                  # The execution wrapper script
└── /templates              # The "What" (Cluster configurations)
    ├── training.tfvars     # High CPU/GPU configuration
    ├── inference.tfvars    # Low latency configuration
    └── spike.tfvars        # Cheap, burst CPU configuration
```
## 🛠️ Step 1: Prerequisites

Before you forge your first cluster, you need two standard tools installed on your local machine:

1. Install Terraform
2. Install Google Cloud CLI (gcloud)

Once installed, link your local machine to your Google Cloud Billing Account by running this in your terminal:
```bash
gcloud auth application-default login
```
(This will pop open a web browser for you to log into your Google Account).

## ⚙️ Step 2: Configuration

1. Open `/templates/training.tfvars` (or `spike.tfvars`).

2. Replace `your-gcp-project-id` with your actual Google Cloud Project ID.

3. (Optional) Tweak the `machine_type` or `gpu_count` depending on how much horsepower you need for this specific run.

## 🚀 Step 3: Spin Up Your Cluster

To create your cluster, simply use the run.sh script. You specify the target cloud (--cloud gcp) and the template flavor you want to use (--type spike):
```bash
../run.sh --cloud gcp --type spike --action apply
```

What happens next?Terraform safely initializes in an isolated workspace.It builds the IAP firewall, GCS bucket, and Instance Group.The script waits 15 seconds for Google to boot the VM and locate its generated name.The script prints out the exact gcloud commands you need to connect.

## 💻 Step 4: Working on Your Cluster

Instead of using a standard IP address, you will use Google's secure IAP tunnel.To SSH into the machine:(Copy the exact command printed by the run.sh script)

```bash
gcloud compute ssh hpc-worker-abcd --tunnel-through-iap --zone=us-central1-c
```

To access Jupyter Notebooks or Web Apps:If you start a service on port 8080 on the VM, you can securely tunnel it to your local machine:

```bash
gcloud compute start-iap-tunnel hpc-worker-abcd 8080 --local-host-port=localhost:8888 --zone=us-central1-c
```

Then just open http://localhost:8888 in your laptop's web browser!

## 🔥 Step 5: Tear Down (Stop the Billing!)

When your model is done training, don't leave the cluster running. Destroy it entirely with one command:

```bash
./run.sh --cloud gcp --type spike --action destroy
```

Safety Note: This will destroy the Compute instances and the attached GCS Storage Bucket. Ensure you have downloaded any trained models to your local machine before running the destroy command!