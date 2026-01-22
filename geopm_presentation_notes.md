# GEOPM Presentation Notes

## Reference Links

- GEOPM Web Page: https://geopm.github.io
- GitHub Repository: https://github.com/geopm/geopm

## High Level Overview

(Source: https://geopm.github.io/overview.html)

**What is GEOPM?**

- Global Extensible Open Power Manager (GEOPM) is a framework for safely and
  securely modifying hardware settings for the duration of a process session.
- Enables dynamic, user-driven power and performance tuning.
- Deployed on large-scale systems (e.g., Aurora).

**Why Use GEOPM?**

- **Secure Userspace Interface**: Safely adjust hardware limits (power,
  frequency) without affecting system stability.
- **Session-based**: Changes are reverted automatically when the session ends.
- **Fine-grained Control**: Admins retain control over access.

**Key Value Propositions:**
- For **HPC/Cloud Users**: Optimize performance per watt.
- For **Admins**: Enable user tuning securely.
- **Sustainability**: Power capping and energy-aware scheduling.
- **Example**: Reducing CPU power limits for memory-bound workloads to save
  energy with minimal performance impact.

## Use Cases

### A. GEOPM Prometheus Exporter (Telemetry & Monitoring)

(Source: https://geopm.github.io/geopmexporter.1.html)

GEOPM integrates with cloud-native monitoring stacks to provide high-resolution
hardware telemetry.

- **Kubernetes Integration**:
  https://github.com/geopm/geopm/tree/dev/integration/k8
- **Grafana Integration**:
  https://github.com/geopm/geopm/tree/dev/integration/grafana

**Relevance**: Demonstrates GEOPM's capability to expose hardware signals
  (power, frequency, thermal, etc.) to standard monitoring tools like
  Prometheus, useful for cluster-wide analysis.

### B. `geopmopt` (Workload Targeted Static Optimization)

(Source: https://geopm.github.io/geopmopt.1.html)

**Overview**:
`geopmopt` is a command-line tool for **Bayesian optimization** of GEOPM control
parameters. It automatically finds optimal settings to maximize/minimize metrics
(e.g., maximize performance, minimize energy). This enables application targeted
optimizations based running benchmarks that provide a figure of merit.

**Capabilities**:
- **Parameter Tuning**: Optimizes CPU frequency, uncore frequency, power limits,
  GPU settings, etc.
- **Objective Functions**: Can target Performance, Energy, or Efficiency.
- **Online Learning**: Uses active learning to explore the parameter space
  while repeating benchmark execution.

**Example Scenarios**:
1. **Performance**: Maximize application performance by tuning frequency.
2. **Efficiency**: Minimize energy while maintaining a performance threshold.
3. **Per-Component Tuning**: Possible to tune components independently.

## Tutorial Walkthrough

(Source: https://geopm.github.io/tutorial.html)

**I. Platform Topology**
- Understanding the hardware hierarchy (Board -> Package -> Core -> CPU).
- Tools: `geopmread --domain`
- APIs: `PlatformTopo` (C/C++/Python/Go) to query system structure.

**II. Reading Telemetry**
- **Signals**: Reading hardware counters (e.g., `CPU_FREQUENCY_STATUS`, `MSR::PERF_STATUS:FREQ`).
- **Domains**: Signals have native domains (e.g., CPU) but can be aggregated.
- **Aggregation**: Automatic up-scaling of metrics (e.g., average frequency
  across a package or board).

- **Tools**: `geopmread` CLI.
  ```bash
  # Read CPU frequency for CPU 0
  geopmread CPU_FREQUENCY_STATUS cpu 0
  ```

## GEOPM Access Service Architecture

(Source: https://geopm.github.io/service.html#architecture)

**Key Components:**
- **IOGroups**: C++ classes that abstract hardware interfaces (e.g., MSR, Sysfs,
  NVML). They provide a plugin mechanism to extend GEOPM's functionality to new
  hardware.
- **PlatformIO**: The container for all IOGroups. It serves as the main
  interface for users/tools to interact with hardware.
- **DBus Interface (`io.github.geopm`)**: Provides a secure gateway to
  privileged PlatformIO features (option to run over UDS with gRPC protocol)
- **Batch Server**: A low-latency interface created via DBus that validates
  permissions once at creation time, enabling high-performance monitoring and
  control.

**Workflow:**
1. **User Tools** (`geopmread`, `geopmwrite`, APIs) interact with `PlatformIO`.
2. **PlatformIO** routes requests to the appropriate **IOGroup**.
3. If privileges are required, requests go through the **DBus Interface**.
4. **Admin Control**: The `geopmaccess` tool allows admins to manage
  fine-grained access lists for specific signals and controls.

## GEOPM HPC Runtime

(Source: https://geopm.github.io/runtime.html)

**Overview:**
The GEOPM Runtime is designed to enhance energy efficiency through active hardware
configuration coupled with the application's execution.

**Key Concepts:**
- **Application Feedback**: Uses application instrumentation (profiling) to
  drive hardware decisions.
- **Agents**: Control algorithms implemented as plugins (e.g., `power_balancer`).
  Define what data is collected and how controls are set.
- **Controller**: A thread/process created on each compute node that loads the
  Agent and manages the control loop.
- **`geopmlaunch`**: A wrapper for the MPI launcher (like `mpiexec`) that sets
  up the GEOPM infrastructure alongside the application.
  https://geopm.github.io/geopmlaunch.1.html
- **Scalable Hierarchical**: Agents coordinate through non-blocking communication
  over a balanced tree hierarchy.

**Use Case: Power Balancer Agent**
- Distributes power across nodes in an MPI job to maximize aggregate
  performance under a global power cap.
- Identifies critical path and shifts power from waiting nodes to those doing
  useful work.


## Automatic Instrumentation (OMPT & PMPI)

GEOPM enables automatic instrumentation of applications without source code
modification.

- **OMPT (OpenMP Tools Interface)**: Automatically detects OpenMP parallel regions.
- **PMPI (Profiling MPI)**: Intercepts MPI calls to profile communication phases.
- This allows GEOPM to correlate hardware telemetry with application phases
  (compute vs. communication) for context-aware optimization.

POC to apply similar methodology to pytorch:
https://github.com/cmcantalupo/geopm/tree/python-prof-torch

## Installing GEOPM

(Source: https://geopm.github.io/install.html)

**Methods:**
- **Linux Packages**: Pre-built packages available for major distributions:
  - **Fedora / OpenSUSE Hardware repo** Available from upstream distro
  - **Ubuntu / RHEL / Rocky / CentOS**: Public package repositories maintained in OBS and Launchpad
- **Spack**: Supported for HPC environments to manage dependencies and versions.
- **Source Build**: For custom configurations, unsupported OSs, or development.

**Key Packages:**
- `geopmd`: GEOPM Access Service daemon
- `python3-geopmdpy`: Python implementation for GEOPM Access service user interfaces (CLI)
- `libgeopmd`: PlatformIO and GEOPM Access Service C++ implementation
- `libgeopm`: GEOPM HPC Runtime C++ implementation
- `python3-geopmpy`: Python implementation for GEOPM HPC Runtime launch and analysis.

**Service Enablement:**
Once installed, the service must be enabled by an admin:
```bash
sudo systemctl enable --now geopm
# Configure access lists (example: allow all features for all users)
geopmaccess -a | sudo geopmaccess -w
geopmaccess -ac | sudo geopmaccess -wc

```



## Next Steps (Interactive Discussion)

- These building blocks (Topology + Telemetry + Control) enable the `geopmopt`,
  `geopmlaunch`, and `geopmexporter` features described earlier.
