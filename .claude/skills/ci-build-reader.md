# CI Build Reader Skill

Read the latest GitHub Actions CI build outputs, check if commits were successful, and identify problems that need fixing.

## Overview

This skill fetches and analyzes GitHub Actions workflow runs to help you:
- Check if your latest commits passed CI
- Identify which jobs failed and why
- Read detailed logs from failed builds
- Get actionable insights to fix problems

## Usage

When invoked, this skill will:
1. Detect the current Git repository and branch
2. Fetch the latest CI workflow runs from GitHub
3. Display the status of all jobs (passed/failed)
4. For failed jobs, fetch and display detailed logs
5. Provide a summary of what needs to be fixed

## Instructions

You are now operating as the CI Build Reader. Your task is to check GitHub Actions CI status and help identify and fix build problems.

### Step 1: Gather Repository Information

First, collect the necessary repository information:

```bash
# Get the current commit SHA
git log -1 --format='%H'

# Get the current branch name
git branch --show-current

# Get repository owner and name from remote
git remote get-url origin | sed 's/.*\/git\/\([^/]*\)\/\([^/]*\)$/\1\/\2/'
```

### Step 2: Fetch Latest Workflow Runs

Use the GitHub API to fetch the latest workflow runs. The GitHub API endpoint structure is:
```
https://api.github.com/repos/{owner}/{repo}/actions/runs
```

Since `gh` CLI is not available, use `curl` to fetch data:

```bash
# Set repository info (extract from git remote)
REPO_OWNER="<owner>"
REPO_NAME="<repo>"
BRANCH="<current-branch>"

# Fetch latest workflow runs for the current branch
curl -s -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/actions/runs?branch=${BRANCH}&per_page=5" \
  > /tmp/workflow_runs.json
```

### Step 3: Parse Workflow Run Status

Parse the JSON response to extract:
- Workflow run ID
- Workflow name
- Status (completed, in_progress, queued)
- Conclusion (success, failure, cancelled)
- Created/updated timestamps
- Commit SHA
- HTML URL for viewing on GitHub

Example parsing with `jq` (if available) or Python:

```bash
# Check if the latest run exists and get its details
python3 << 'EOF'
import json
import sys

try:
    with open('/tmp/workflow_runs.json', 'r') as f:
        data = json.load(f)

    if 'workflow_runs' not in data or len(data['workflow_runs']) == 0:
        print("No workflow runs found for this branch")
        sys.exit(0)

    # Get the most recent run
    latest_run = data['workflow_runs'][0]

    print(f"Latest CI Run:")
    print(f"  Workflow: {latest_run['name']}")
    print(f"  Status: {latest_run['status']}")
    print(f"  Conclusion: {latest_run.get('conclusion', 'N/A')}")
    print(f"  Commit: {latest_run['head_sha'][:8]}")
    print(f"  URL: {latest_run['html_url']}")
    print(f"  Run ID: {latest_run['id']}")

    # Save run ID for next step
    with open('/tmp/latest_run_id.txt', 'w') as f:
        f.write(str(latest_run['id']))

    # Save conclusion for checking
    with open('/tmp/latest_run_conclusion.txt', 'w') as f:
        f.write(latest_run.get('conclusion', 'unknown'))

except Exception as e:
    print(f"Error parsing workflow runs: {e}")
    sys.exit(1)
EOF
```

### Step 4: Fetch Job Details for Failed Runs

If the conclusion is not "success", fetch detailed job information:

```bash
RUN_ID=$(cat /tmp/latest_run_id.txt)
REPO_OWNER="<owner>"
REPO_NAME="<repo>"

# Fetch jobs for this run
curl -s -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/actions/runs/${RUN_ID}/jobs" \
  > /tmp/workflow_jobs.json
```

Parse job details:

```bash
python3 << 'EOF'
import json

try:
    with open('/tmp/workflow_jobs.json', 'r') as f:
        data = json.load(f)

    jobs = data.get('jobs', [])

    print("\nJob Details:")
    print("=" * 80)

    failed_jobs = []

    for job in jobs:
        status_icon = "✓" if job['conclusion'] == 'success' else "✗"
        print(f"\n{status_icon} {job['name']}")
        print(f"  Status: {job['status']}")
        print(f"  Conclusion: {job.get('conclusion', 'N/A')}")
        print(f"  Duration: {job.get('started_at', '')} -> {job.get('completed_at', '')}")

        if job['conclusion'] != 'success' and job['conclusion'] is not None:
            failed_jobs.append({
                'id': job['id'],
                'name': job['name'],
                'conclusion': job['conclusion']
            })

            # Show failed steps
            print(f"  Failed Steps:")
            for step in job.get('steps', []):
                if step.get('conclusion') == 'failure':
                    print(f"    ✗ {step['name']}")

    # Save failed job IDs for log fetching
    if failed_jobs:
        with open('/tmp/failed_jobs.json', 'w') as f:
            json.dump(failed_jobs, f)
        print(f"\n\nFound {len(failed_jobs)} failed job(s)")
    else:
        print("\n\nAll jobs passed! ✓")

except Exception as e:
    print(f"Error parsing jobs: {e}")
EOF
```

### Step 5: Fetch and Display Logs for Failed Jobs

For each failed job, fetch the logs:

```bash
# Check if there are failed jobs
if [ -f /tmp/failed_jobs.json ]; then
    python3 << 'EOF'
import json
import subprocess
import os

REPO_OWNER = "<owner>"
REPO_NAME = "<repo>"

try:
    with open('/tmp/failed_jobs.json', 'r') as f:
        failed_jobs = json.load(f)

    for job in failed_jobs:
        job_id = job['id']
        job_name = job['name']

        print(f"\n{'=' * 80}")
        print(f"LOGS FOR: {job_name}")
        print(f"{'=' * 80}\n")

        # Fetch job logs
        log_url = f"https://api.github.com/repos/{REPO_OWNER}/{REPO_NAME}/actions/jobs/{job_id}/logs"
        result = subprocess.run(
            ['curl', '-s', '-L', '-H', 'Accept: application/vnd.github+json', log_url],
            capture_output=True,
            text=True
        )

        if result.returncode == 0:
            logs = result.stdout

            # Display the logs (may be long, show last 100 lines)
            log_lines = logs.split('\n')
            if len(log_lines) > 100:
                print(f"... (showing last 100 lines of {len(log_lines)} total)")
                print('\n'.join(log_lines[-100:]))
            else:
                print(logs)
        else:
            print(f"Failed to fetch logs for job {job_id}")

except Exception as e:
    print(f"Error fetching logs: {e}")
EOF
fi
```

### Step 6: Provide Summary and Recommendations

After analyzing the CI results, provide a clear summary:

1. **Overall Status**: Did the CI pass or fail?
2. **Failed Jobs**: List which specific jobs failed
3. **Error Analysis**: Identify the key errors from the logs
4. **Recommended Fixes**: Based on common failure patterns:
   - Build errors: Check for compilation issues, missing dependencies
   - Test failures: Identify which tests failed and why
   - Lint errors: List lint violations that need fixing
   - Configuration issues: Missing files, wrong paths, permission errors

### Step 7: Offer to Fix Problems

After presenting the analysis, ask the user if they want you to:
1. Fix the identified issues automatically
2. Get more details about a specific failure
3. Re-run the CI after fixes

## Common CI Failure Patterns and Fixes

### Android Build Failures
- **Missing dependencies**: Check `build.gradle` files
- **Compilation errors**: Review Kotlin/Java syntax errors
- **Resource errors**: Verify resource files exist and are properly formatted

### Test Failures
- **Unit test failures**: Read test output, fix broken assertions
- **Integration test failures**: Check test setup, mocks, dependencies

### Lint Failures
- **Code style violations**: Apply formatting rules
- **Deprecated API usage**: Update to newer APIs
- **Unused imports/variables**: Clean up code

### Mock Server Test Failures
- **Server not starting**: Check Python dependencies, port conflicts
- **Endpoint failures**: Verify mock server routes and responses

## Notes

- The GitHub API has rate limits (60 requests/hour unauthenticated)
- Logs can be large; focus on error messages and context
- Always check the most recent run for the current branch
- Consider checking runs for specific commits with: `/repos/{owner}/{repo}/actions/runs?head_sha={sha}`

## Cleanup

After analysis, clean up temporary files:

```bash
rm -f /tmp/workflow_runs.json /tmp/workflow_jobs.json /tmp/failed_jobs.json /tmp/latest_run_id.txt /tmp/latest_run_conclusion.txt
```

---

Remember: Your goal is to help identify CI problems quickly and offer to fix them autonomously!
