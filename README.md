# Distributed AI Inference on AWS

This project provisions a distributed AI inference architecture on AWS using Terraform. It deploys two EC2 instances across public and private subnets, utilizing the `iii` RPC engine for cross-language worker communication.

## 🏗️ Architecture

```text
       INTERNET
          │ (Port 3111)
          ▼
┌─────────────────────────────────────────────────────────┐
│  AWS VPC  (e.g. 10.0.0.0/16)                           │
│                                                          │
│  ┌──────────────────────┐                               │
│  │   PUBLIC SUBNET       │                               │
│  │   10.0.1.0/24         │                               │
│  │                       │                               │
│  │  ┌──────────────────┐ │                               │
│  │  │  API Gateway VM  │ │  ← Only VM with public IP    │
│  │  │  (caller-worker) │ │    Exposes POST /v1/chat/    │
│  │  │  TypeScript      │ │    completions to internet   │
│  │  │  Port 3111       │ │                               │
│  │  └────────┬─────────┘ │                               │
│  └───────────┼───────────┘                               │
│              │  RPC over WebSocket (private subnet)      │
│  ┌───────────┼───────────────────────────────────────┐  │
│  │   PRIVATE SUBNET  10.0.2.0/24                     │  │
│  │           │                                        │  │
│  │  ┌────────▼─────────┐                             │  │
│  │  │  Inference VM    │                             │  │
│  │  │ (inference-worker│                             │  │
│  │  │  Python + Gemma  │                             │  │
│  │  │  Port 49134      │                             │  │
│  │  └──────────────────┘                             │  │
│  └───────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

**Two workers, two VMs:**
- **inference-worker (Python):** Hosted in the private subnet. Loads `gemma-3-270m` GGUF model and runs inference via the RPC function `inference::run_inference`.
- **caller-worker (TypeScript):** Hosted in the public subnet. Acts as the API Gateway with an HTTP trigger on `POST /v1/chat/completions`. It calls the inference worker via RPC and returns a JSON response.

---

## 🛠️ Step-by-Step Deployment Explanation

The infrastructure is fully automated using Terraform. Here is a breakdown of what the code does and *why*:

### 1. The Network (VPC + Subnets)
We provision an isolated network (VPC). 
- **Public Subnet:** Has an Internet Gateway attached. This is where the Caller VM lives so it can accept public HTTP requests.
- **Private Subnet:** Has NO internet access, only a NAT Gateway. This is where the Inference VM lives. It can reach out to the internet to download the Python model, but nobody on the internet can reach in. This ensures strict network hygiene.

### 2. Security Groups (Firewalls)
- **API Gateway SG (Public):** Opens TCP port 3111 to the world (`0.0.0.0/0`) for the API, and TCP 22 (SSH) strictly to your specific IP address.
- **Inference SG (Private):** Completely blocked from the internet. It only opens port 49134 (for the RPC engine) and port 22 (for SSH) to the specific private IP of the Caller VM.

### 3. The EC2 Instances
- **Caller VM (`t3.micro`):** Extremely lightweight (1GB RAM) because it only runs a Node.js web server.
- **Inference VM (`c7i-flex.large`):** Requires at least 4GB of RAM because loading the PyTorch framework and the 8-bit quantized Gemma model (~270MB) requires significant memory overhead.

### 4. Bootstrapping (user_data)
When Terraform launches the VMs, it runs bash scripts automatically:
- It installs Node.js / Python3.
- It installs the `iii` RPC engine.
- It clones this repository and installs `npm` and `pip` dependencies.
- It configures `systemd` services so that the API and Inference workers start automatically and restart on failure.

---

## 🚀 How to Deploy from Scratch

1. **Find your Public IP:**
   Go to [https://checkip.amazonaws.com/](https://checkip.amazonaws.com/). This is required to whitelist your IP for SSH access.

2. **Clone this repository:**
   ```bash
   git clone <YOUR_REPO_URL>
   cd terraform
   ```

3. **Configure Terraform Variables:**
   Create a `terraform.tfvars` file (this is ignored by git for security) and add your public IP (with a `/32` CIDR block) and your AWS SSH key pair name:
   ```hcl
   your_ip_cidr = "YOUR_PUBLIC_IP/32"  # e.g., "49.47.135.128/32"
   key_pair_name = "Batch12"           # Must exist in AWS ap-south-1
   ```

4. **Deploy the infrastructure:**
   ```bash
   terraform init
   terraform plan
   terraform apply -auto-approve
   ```

5. **Wait for Bootstrap:**
   Wait ~10 minutes for the VMs to fully bootstrap (install dependencies, download the model, and start the systemd services).

---

## 🧪 API Usage

Once deployed, Terraform will output a `curl_example` command. Run it to test the API:

**Request:**
```bash
curl -X POST http://<CALLER_VM_PUBLIC_IP>:3111/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      {"role": "user", "content": "What is 2+2?"}
    ]
  }'
```

**Example Response:**
```json
{
  "result": {
    "success": "You've connected two workers...",
    "response": "4"
  }
}
```

---

## 🔒 Production Hardening & Scaling

**What I'd harden for production:**
To make this enterprise-ready, I would place an Application Load Balancer (ALB) with AWS ACM certificates in front of the Caller VM to enable HTTPS/TLS. I'd add API authentication (like JWTs or API keys) to the TypeScript worker to prevent unauthorized access. The Inference VM would remain strictly isolated in the private subnet, but I would use AWS Systems Manager (SSM) Session Manager for shell access instead of SSH, completely eliminating the need to expose port 22.

**If the model were 100x larger (e.g., Llama 70B):**
A much larger model cannot run on CPU. I would swap the `c7i-flex.large` instance for a GPU-backed instance like `g5.2xlarge` or `p4d.24xlarge`. To handle traffic spikes, I would put the Inference VMs in an Auto Scaling Group (ASG) behind an internal load balancer. Finally, instead of downloading the massive model from HuggingFace on every boot, I would cache the model weights on an Amazon EFS volume or an S3 bucket with a VPC endpoint for ultra-fast, local network retrieval.

---

## 📸 Deployment Evidence

*(Add your screenshots here before submission)*

1. **VPC & Subnets:**
   ![VPC Setup](link_to_screenshot)

2. **Running EC2 Instances:**
   ![EC2 Instances](link_to_screenshot)

3. **Security Groups (Inbound Rules):**
   ![Security Groups](link_to_screenshot)

4. **Successful API Response (cURL):**
   ![cURL Test](link_to_screenshot)
