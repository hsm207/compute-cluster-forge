# 🛠️ Compute Cluster Forge

**Compute Cluster Forge** is a modular infrastructure-as-code (IaC) framework that leverages **Terraform** to provision secure, auto-healing, and cost-optimized AI/ML compute clusters. While currently configured for **Google Cloud Platform (GCP)**, the architecture is designed for seamless extension to AWS and Azure.

---

## 🌟 Core Architectural Principles

This implementation adheres to industry-standard DevOps practices, moving beyond static scripting toward a dynamic, policy-driven infrastructure:

*   🔒 **Zero-Trust Security (Google IAP):** Implements a strict security model where all public ingress is disabled. Management access (SSH/Web) is limited to authorized users via Google Identity-Aware Proxy (IAP) TCP forwarding.
*   🩹 **Auto-Healing Spot VM Orchestration:** Leverages Google's cost-effective Spot instances (saving up to 80%) while utilizing Managed Instance Groups (MIGs) to provide automated health-checking and self-healing.
*   🗺️ **Dynamic Infrastructure Discovery:** Implements automated resource discovery. The system queries regional metadata to identify zones supporting specific hardware requirements (e.g., NVIDIA L4 GPUs) and restricts deployment to compatible areas.
*   🥞 **Modular Layered Configuration:** Utilizes a decoupled configuration model where base environment templates are combined with specific hardware layers at runtime via an orchestrated CLI.
*   ⚙️ **Contextual Metadata Injection:** Resource metadata is dynamically modified based on the requested hardware profile (e.g., automated NVIDIA driver installation is only injected for GPU-enabled nodes).
*   🔄 **Stateful Data Persistence:** Provisions dedicated Google Cloud Storage (GCS) buckets for persistent model and dataset synchronization across cluster lifecycles.

---

## 📂 Repository Structure

```text
/compute-cluster-forge
├── /modules                # Infrastructure-as-Code (IaC) Modules
│   ├── /aws                # [Planned] AWS Provider Module
│   ├── /azure              # [Planned] Azure Provider Module
│   └── /gcp                # Active GCP Provider Module
│       ├── main.tf         # Resource Orchestration (MIG, Firewalls, APIs)
│       ├── variables.tf    # Input Schema & Secure Defaults
│       ├── outputs.tf      # Validated Resource References
│       └── startup-script.sh # Native Bootstrapping Logic
├── run.sh                  # CLI Orchestration & Execution Wrapper
└── /templates              # Environment & Hardware Profiles
    ├── training.tfvars     # High-compute Base Profile
    ├── inference.tfvars    # Low-latency Base Profile
    ├── spike.tfvars        # General-purpose Burst Profile
    └── gpu-l4.tfvars       # Hardware Layer: NVIDIA L4 GPU / G2 Family
```

---

## 🛠️ Step 1: Prerequisites

Ensure the following toolchains are available in your environment:
1.  **Terraform** (v1.0+)
2.  **Google Cloud CLI (`gcloud`)**

Authenticate your local machine to generate Application Default Credentials (ADC):
```bash
gcloud auth application-default login
```

---

## 🚀 Step 2: Provisioning Your Cluster

Utilize the `run.sh` orchestrator to provision clusters. The interface supports combining environment templates with hardware layers and runtime variable overrides.

**Example: Provisioning a Spot Cluster with NVIDIA L4 Acceleration:**
```bash
./run.sh --cloud gcp --type spike --layer gpu-l4 --var project_id=[PROJECT_ID] --action apply
```

**What happens behind the scenes?**
1.  **Isolation:** Terraform initializes within an isolated workspace.
2.  **Discovery:** Executes dynamic zone discovery based on hardware requirements.
3.  **Provisioning:** Deploys IAM policies, networking, storage, and compute resources.
4.  **Verification:** Automated status verification monitors the Instance Group until version targets are reached and health checks pass.
5.  **Reporting:** Generates instance-specific connection strings for secure access.

---

## 💻 Step 3: Cluster Interaction

Internal services must be accessed through the established IAP tunnel.

### ⚠️ Important: Network Binding Requirement
To ensure accessibility via IAP TCP forwarding, all applications (e.g., Jupyter Lab, Tensorboard) **MUST** bind to **`0.0.0.0`**. Applications listening exclusively on `127.0.0.1` will be unreachable.

*   ✅ **Jupyter Lab:** `jupyter lab --ip=0.0.0.0 --port=8888 --no-browser`
*   ✅ **HTTP Server:** `python3 -m http.server 8080 --bind 0.0.0.0`

### 🌐 Connection Reference

Once the cluster is live, `run.sh` provides dynamically resolved connection commands:

**Secure SSH Access:**
```bash
gcloud compute ssh [INSTANCE_NAME] --tunnel-through-iap --project=[PROJECT_ID] --zone=[ZONE]
```

**IAP Port Forwarding (Remote 8888 ➔ Local 8888):**
```bash
gcloud compute start-iap-tunnel [INSTANCE_NAME] 8888 --local-host-port=localhost:8888 --project=[PROJECT_ID] --zone=[ZONE]
```

---

## 🔥 Step 4: Resource Decommissioning

To prevent unnecessary billing, decommission all provisioned resources upon task completion:

```bash
./run.sh --cloud gcp --type spike --layer gpu-l4 --var project_id=[PROJECT_ID] --action destroy
```

> **🛑 Safety Note:** This operation performs a forceful deletion of all regional resources, including the stateful GCS bucket. Ensure all datasets and trained models are synchronized to local storage prior to execution.
