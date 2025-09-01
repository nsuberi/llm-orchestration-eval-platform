# ClinTestbench (Scaffold)

Monorepo skeleton for an **LLM orchestration + evidence-linked evaluation** platform.

## Packages
- apps/frontend – Next.js frontend
- services/api – FastAPI stub with pytest
- workers/runner – Python worker stub with pytest
- packages/schemas – shared types & schema stubs
- packages/prompts – versioned prompt stubs

## Dev Scripts
See `package.json` at root and each package-level `package.json`.

## Quick start (local, with kind Kubernetes)
Prereqs: Docker Desktop, kind, kubectl, Node >= 18.17.0. Python via conda is recommended for running tests.

1) One-command local setup:
```bash
./scripts/setup_local.sh
```
This will:
- Install npm deps, build Docker images for API and frontend
- Create a local kind cluster `ctb-local` with `dev` and `prod` namespaces
- Load images into kind, apply `infra/k8s/local/dev.yaml`, and port-forward frontend to http://localhost:3000

2) Verify endpoints from the UI at http://localhost:3000

3) Run tests (optional):
```bash
conda env create -f environment.yml && conda activate ctb
npm test
```

## Python with conda
We use a conda env for Python tooling/tests.

1) Install Miniconda or Mambaforge
2) Create env: `conda env create -f environment.yml`
3) Activate: `conda activate ctb`
4) Run Python tests: `pytest` (or via npm scripts which call `conda run -n ctb ...`)

## Local Kubernetes (manual)
If you prefer manual steps, see `docs/local-testing.md` for commands to create kind, build/load images, apply manifests, and port-forward services.

## TDD loop
1) Write a failing test
2) Implement minimal code
3) Refactor

## Git worktrees
Use `scripts/worktree.sh NEW CTB-123 short-slug` to spin an isolated worktree.
