# Midterm Practice -- Starter Project

A small Dockerized JSON API with a broken CI/CD setup. Your job is described in
`assessments/Midterm-Practice.md`; this file only tells you what is here.

## What is in this folder

| Path | What it is |
|---|---|
| `app.py` | The application. A version endpoint (`/`) and a health endpoint (`/healthz`). **Correct -- do not change it.** |
| `requirements.txt` | Its two dependencies. **Correct.** |
| `Dockerfile` | How the app is containerised. |
| `.dockerignore` | Build-context exclusions. **Correct.** |
| `terraform/main.tf` | A LocalStack-targeted network: VPC, two public subnets, internet gateway, route table, security group, artifact bucket. |
| `terraform/localstack.tfvars` | Flips the provider onto LocalStack. **Correct.** |
| `scripts/deploy.sh` | Records a release manifest in the artifact bucket. |
| `NOTES.md` | Where your written answer goes. |
| `evidence/` | Where any screenshots or command output you want to submit go. |

The application listens on **port 8000**. Everything in this folder that refers
to a port should agree with that.

## Running things locally

```bash
# Container
docker build -t acs730-midterm:local midterm-practice
docker run --rm -d --name acs730-midterm -p 8080:8000 acs730-midterm:local
curl -fsS http://localhost:8080/healthz
docker rm -f acs730-midterm

# LocalStack (same image and the same four commands as your Week 6 lab)
docker run --rm -d --name localstack -p 4566:4566 localstack/localstack:3
cd midterm-practice/terraform
terraform init
terraform validate
terraform plan -var-file=localstack.tfvars -out=tfplan
terraform apply -auto-approve tfplan
```

**You do not need AWS credentials for any part of this exam.** If anything asks
you for one, you have pointed something at real AWS by mistake.

## Workflows

The two workflow files that come with this starter belong at the **root of your
course repository**, in `.github/workflows/`, not in this folder -- GitHub only
reads workflows from there.

- `midterm-practice-ci.yml` -- lints the application and builds the image.
- `midterm-practice-terraform.yml` -- the LocalStack-based Terraform check.
