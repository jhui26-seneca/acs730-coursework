# ACS730 — Course Project Repository

This is the template repository for ACS730 (Cloud Automation and Operational Security). At the start of the course, create your own repository from this template and do all of your work there.

## Structure

Each folder below corresponds to one deliverable. Instructions for each one will be given in class and posted on Blackboard as the course progresses — this template intentionally does not include starter code or instructions ahead of time.

- `lab1/` through `lab8/` — the weekly labs. **The lab number is not the week number** after Lab 4 — there are 14 weeks but 8 labs. Put each lab's work in the folder named below, not in the folder matching the week number:

  | Folder | Week | Topic |
  |---|---|---|
  | `lab1/` | Week 1 | Version control and the AWS CLI |
  | `lab2/` | Week 2 | Linux administration, deploying a web app to EC2 |
  | `lab3/` | Week 3 | GitHub Actions, Terraform basics, session-scoped credentials |
  | `lab4/` | Week 4 | Docker fundamentals |
  | `lab5/` | Week 6 | Terraform introduction and reliable CI |
  | `lab6/` | Week 8 | Configuration management with Ansible and golden AMIs |
  | `lab7/` | Week 12 | Security and policy-as-code |
  | `lab8/` | Weeks 9–10 | Kubernetes fundamentals and CI/CD to Kubernetes |

  Weeks 5, 7, 11 and 13 have no separate lab folder — that week's hands-on work feeds into an assignment or the final project instead. Note that `lab7/` is the security lab: the grading pipeline requires it to have **no HIGH or CRITICAL `tfsec` findings**, which is the whole point of that exercise. Every other folder's scan results are informational.
- `assignment1/` — Assignment 1
- `assignment2/` — Assignment 2
- `final-project/` — Final Project
- `midterm-practice/` and `final-practice/` — the hands-on component of the Midterm and Final exams. These stay empty until the exam window opens; do not put anything here early.
- `scripts/refresh-gha-creds.sh` — shared helper you'll run at the start of **every AWS Academy lab session** from Week 3 onward: it pushes your current session credentials to GitHub Actions secrets so your pipelines can deploy. If a deploy workflow fails with `ExpiredToken`, your session ended — start a new one and re-run this script.

## What to Submit

Follow the normal Git workflow you'll learn in Week 1: commit your work to your own repository as you go. There is nothing to upload to Blackboard separately — every deliverable is graded directly from this repository. Do not delete or rename any of the folders above; the grading pipeline expects them at these exact paths.
