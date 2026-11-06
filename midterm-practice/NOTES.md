# Midterm Practice -- Notes

## Task 5: git hygiene

Deleting the .tfstate file and the credential string in my latest commit is not sufficient by itself, because both remain in the repository's history (the starting-point commit is still there and the repo is public), so anyone can recover them with `git show` or by checking out that commit, which means the key must be treated as leaked and revoked/rotated, and the history rewritten if the files must disappear completely.
