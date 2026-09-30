##################################################
# Publish Module for Typst Packages
#
packages_repo := clean(justfile_directory() / ".." / "packages")
project_dir   := justfile_directory()
ignore_file   := project_dir / ".publishignore"
branch_prefix := "release/"

# List all publish recipes
@default:
  just --list publish

# Preview files that would be copied for a given version
[linux]
[macos]
dry-run version:
  #!/usr/bin/env sh
  set -eu

  pkg_name=$(grep -E '^name\s*=' typst.toml 2>/dev/null | head -n1 | sed -E 's/name\s*=\s*["'"'"']([^"'"'"']+)["'"'"']/\1/' | tr '[:upper:]' '[:lower:]' || true)
  if [ -z "$pkg_name" ]; then
    pkg_name=$(basename "{{project_dir}}" | tr '[:upper:]' '[:lower:]')
  fi

  dest_dir="{{packages_repo}}/packages/preview/${pkg_name}/{{version}}"

  echo "=== DRY RUN: Publish ${pkg_name} {{version}} ==="
  echo "Target destination: $dest_dir"
  echo "Excluded patterns from: {{ignore_file}}"
  echo ""

  if [ -f "{{ignore_file}}" ]; then
    rsync -avn --delete --exclude-from="{{ignore_file}}" "{{project_dir}}/" "$dest_dir/"
  else
    rsync -avn --delete --exclude='.*' --exclude='justfile' --exclude='cliff.toml' "{{project_dir}}/" "$dest_dir/"
  fi

# Alias for to-packages
@copy version: (to-packages version)

# Publish a release to the packages repository
[linux]
[macos]
to-packages version:
  #!/usr/bin/env sh
  set -eu

  # 1. Safety check: ensure current working directory is clean
  if [ -n "$(git status --porcelain)" ]; then
    echo "Error: Current repository has uncommitted changes. Please commit or stash them first."
    exit 1
  fi

  # 2. Check packages repository exists
  if [ ! -d "{{packages_repo}}/.git" ]; then
    echo "Error: Packages repository not found at {{packages_repo}}."
    exit 1
  fi

  # 3. Check packages repository is clean
  if [ -n "$(git -C "{{packages_repo}}" status --porcelain)" ]; then
    echo "Error: Target packages repository at {{packages_repo}} has uncommitted changes."
    exit 1
  fi

  # 4. Resolve package name (lowercase)
  pkg_name=$(grep -E '^name\s*=' typst.toml 2>/dev/null | head -n1 | sed -E 's/name\s*=\s*["'"'"']([^"'"'"']+)["'"'"']/\1/' | tr '[:upper:]' '[:lower:]' || true)
  if [ -z "$pkg_name" ]; then
    pkg_name=$(basename "{{project_dir}}" | tr '[:upper:]' '[:lower:]')
  fi

  # 5. Checkout release branch in current repository
  branch="{{branch_prefix}}{{version}}"
  echo "==> Switching current repository to branch '$branch'..."
  if ! git checkout "$branch"; then
    echo "Error: Failed to checkout branch '$branch' in current repository."
    exit 1
  fi

  # 6. Prepare branch in packages repository: <pkg_name>/<version>
  target_branch="${pkg_name}/{{version}}"
  echo "==> Preparing branch '$target_branch' in packages repository..."
  if git -C "{{packages_repo}}" rev-parse --verify --quiet "refs/heads/$target_branch" > /dev/null; then
    echo "    Branch exists, checking out '$target_branch'..."
    git -C "{{packages_repo}}" checkout "$target_branch"
  else
    echo "    Creating and checking out branch '$target_branch'..."
    git -C "{{packages_repo}}" checkout -b "$target_branch"
  fi

  # 7. Copy files to target packages folder
  dest_dir="{{packages_repo}}/packages/preview/${pkg_name}/{{version}}"
  echo "==> Copying files to $dest_dir..."
  mkdir -p "$dest_dir"

  if [ -f "{{ignore_file}}" ]; then
    rsync -av --delete --exclude-from="{{ignore_file}}" "{{project_dir}}/" "$dest_dir/"
  else
    rsync -av --delete --exclude='.*' --exclude='justfile' --exclude='cliff.toml' "{{project_dir}}/" "$dest_dir/"
  fi

  # 8. Validate publication
  if [ ! -f "$dest_dir/typst.toml" ]; then
    echo "Error: typst.toml not found in $dest_dir!"
    exit 1
  fi

  toml_version=$(grep -E '^version\s*=' "$dest_dir/typst.toml" | head -n1 | sed -E 's/version\s*=\s*["'"'"']([^"'"'"']+)["'"'"']/\1/')
  if [ "$toml_version" != "{{version}}" ]; then
    echo "Warning: Version in typst.toml ('$toml_version') does not match requested version '{{version}}'!"
  fi

  echo ""
  echo "=================================================="
  echo "Package '${pkg_name}' version {{version}} copied successfully!"
  echo "  Current branch       : $branch"
  echo "  Packages branch      : $target_branch"
  echo "  Destination directory: $dest_dir"
  echo "=================================================="
