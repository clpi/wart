#!/usr/bin/env bash
# Validate GitHub Actions workflow files
# This script ensures all workflow YAML files are syntactically valid

set -euo pipefail

echo "Validating GitHub Actions workflow files..."
echo "==========================================="
echo

failed=0
total=0

for workflow in .github/workflows/*.yml; do
    total=$((total + 1))
    echo -n "Checking $(basename "$workflow")... "
    
    if python3 -c "import yaml; yaml.safe_load(open('$workflow'))" 2>/dev/null; then
        echo "✓ Valid"
    else
        echo "✗ Invalid"
        failed=$((failed + 1))
    fi
done

echo
echo "==========================================="
echo "Results: $((total - failed))/$total workflows valid"

if [ $failed -gt 0 ]; then
    echo "❌ $failed workflow(s) failed validation"
    exit 1
else
    echo "✅ All workflows are valid!"
    exit 0
fi
