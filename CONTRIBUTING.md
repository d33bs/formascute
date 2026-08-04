# Contributing

formascute is intentionally small. Contributions should preserve that shape:
simple entry points, reproducible experiments, explicit validation, and clear
provenance.

## Development Checks

Run these before opening a pull request:

```bash
make check
make lint
```

If `prek` or `pre-commit` is installed, also run:

```bash
make prek
```

`make check` verifies that the repository is ready to clone and use on Alpine.
`make lint` covers shell syntax, ShellCheck when available, Markdown, and
best-effort Nextflow config checks.

## Contribution Guidelines

- Keep experiments small and bounded.
- Do not commit real HPC usernames, private paths, allocation names, SSH key
  paths, production data paths, or Slurm job identifiers.
- Use placeholders such as `<allocation>`, `<username>`, and `<repo-url>` in
  documentation.
- Do not use production NF1 data in this repository.
- Add or update documentation when a command, assumption, or Alpine observation
  changes.
- Prefer Make targets and `bin/formascute` entry points over one-off scripts.
- Keep CPU and GPU assumptions separate.

## Experiment Criteria

Every experiment should:

- change one thing relative to the baseline
- run quickly at small scale
- validate correctness
- write outputs under `results/<run-id>/`
- preserve enough provenance to interpret the run later
- document remaining uncertainty

## Pull Requests

Pull requests should describe:

- what changed
- how it was validated
- whether Alpine behavior or assumptions changed
- any follow-up questions for HPC support

Do not include generated `results/` outputs unless there is a specific reason to
review a tiny artifact.
