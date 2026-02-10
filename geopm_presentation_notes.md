# GEOPM Presentation Notes

## Reference Links

- GEOPM Web Page: https://geopm.github.io
- GitHub Repository: https://github.com/geopm/geopm

---

## 1. What is GEOPM

(Source: https://geopm.github.io/overview.html)

**What is GEOPM?**

- Global Extensible Open Power Manager (GEOPM) is a framework for safely and
  securely modifying hardware settings for the duration of a process session.
- A **software-defined power management layer** for server platforms.
- Enables dynamic, user-driven power and performance tuning.
- Open source (BSD-3-Clause), $0 BOM cost impact.
- Deployed on large-scale systems (e.g., Aurora supercomputer).

---

## 2. GEOPM for Server Platform Vendors

**The Problem: Power Density**
- Modern data center platforms — especially AI/GPU-dense systems — are
  thermally and electrically constrained. Power management is no longer
  optional; it is a requirement in customer (OEM/hyperscaler) RFPs.
- Customers increasingly demand Prometheus-compatible telemetry, power
  capping, and energy-aware scheduling as platform features.

**Competitive Differentiation**
- Shipping servers with integrated, open power management provides
  immediate value over competitors who leave this to the end customer.
- GEOPM is open source — no licensing cost, no vendor lock-in. Platform
  vendors retain full control over the integration and can contribute upstream.

**Key Value Propositions:**
- **Platform Feature**: GEOPM becomes part of the server's software stack,
  shipping alongside BMC firmware and OS images.
- **Customer Value**: OEMs and hyperscalers get power telemetry, power
  capping, and workload-targeted optimization out of the box.
- **Sustainability / ESG**: Power capping and energy-aware scheduling help
  customers meet sustainability targets — increasingly required in procurement.
- **Extensible**: The IOGroup plugin architecture enables exposing
  platform-specific sensors and controls (board-level power, custom voltage
  regulators, fan controllers, GPU power domains) through a unified API.
- **Safe by Design**: Session-based controls revert automatically — reduces
  support burden and eliminates risk of misconfiguring customer hardware.

---

## 3. Architecture — Integration Points

(Source: https://geopm.github.io/service.html#architecture)

**Key Components:**
- **IOGroups**: C++ classes that abstract hardware interfaces (e.g., MSR, Sysfs,
  NVML). They provide a **plugin mechanism** to extend GEOPM's functionality to
  new hardware.
  - Platform vendors write custom IOGroups for platform-specific hardware —
    board-level sensors, voltage regulators, fan controllers, proprietary
    management interfaces, GPU power domains.
  - This is the primary engineering work for platform integration.
- **PlatformIO**: The container for all IOGroups. It serves as the **unified
  API** for users/tools to interact with hardware.
  - End-customers get a single interface regardless of underlying hardware
    details.
- **DBus Interface (`io.github.geopm`)**: Provides a secure gateway to
  privileged PlatformIO features (option to run over UDS with gRPC protocol).
  - Fits into standard Linux server management stacks. Can coexist with
    Redfish/IPMI/BMC interfaces.
- **Batch Server**: A low-latency interface created via DBus that validates
  permissions once at creation time, enabling high-performance monitoring and
  control.

**Workflow:**
1. **User Tools** (`geopmread`, `geopmwrite`, APIs) interact with `PlatformIO`.
2. **PlatformIO** routes requests to the appropriate **IOGroup**.
3. If privileges are required, requests go through the **DBus Interface**.
4. **Admin Control**: The `geopmaccess` tool allows admins to manage
   fine-grained access lists for specific signals and controls.

The architecture is designed for hardware vendors to plug in their own
platform knowledge while giving end-customers a standard interface.

---

## 4. Platform Topology + Telemetry + Control

(Source: https://geopm.github.io/tutorial.html)

The following demonstrates the end-customer experience out of the box.

**I. Platform Topology**
- Understanding the hardware hierarchy (Board -> Package -> Core -> CPU).
- Tools: `geopmread --domain`
- APIs: `PlatformTopo` (C/C++/Python/Go) to query system structure.

**II. Reading Telemetry**
- **Signals**: Reading hardware counters (e.g., `CPU_FREQUENCY_STATUS`,
  `MSR::PERF_STATUS:FREQ`).
- **Domains**: Signals have native domains (e.g., CPU) but can be aggregated.
- **Aggregation**: Automatic up-scaling of metrics (e.g., average frequency
  across a package or board).
- **Tools**: `geopmread` CLI.
  ```bash
  # Read CPU frequency for CPU 0
  geopmread CPU_FREQUENCY_STATUS cpu 0
  ```
- Custom IOGroups can expose additional platform-specific signals
  (e.g., board inlet temperature, VR efficiency, per-rail power).

---

## 5. Prometheus Exporter — Cloud-Native Telemetry

(Source: https://geopm.github.io/geopmexporter.1.html)

GEOPM integrates with cloud-native monitoring stacks to provide high-resolution
hardware telemetry. This can ship as part of a platform's telemetry stack —
hyperscalers increasingly require Prometheus-compatible hardware telemetry from
their server vendors.

- **Kubernetes Integration**:
  https://github.com/geopm/geopm/tree/dev/integration/k8
- **Grafana Integration**:
  https://github.com/geopm/geopm/tree/dev/integration/grafana

**Relevance**: Exposes hardware signals (power, frequency, thermal, etc.) to
standard monitoring tools like Prometheus. Any custom IOGroup signals are
automatically available through the exporter.

---

## 6. `geopmopt` — Workload-Targeted Auto-Tuning

(Source: https://geopm.github.io/geopmopt.1.html)

**Overview**:
`geopmopt` is a command-line tool for **Bayesian optimization** of GEOPM control
parameters. It automatically finds optimal settings to maximize/minimize metrics
(e.g., maximize performance, minimize energy). This enables application targeted
optimizations based on running benchmarks that provide a figure of merit.

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

`geopmopt` can also be used during platform validation — run it on reference
workloads to characterize optimal power/performance envelopes and ship
recommended configurations.

---

## 7. Integration Model

**Pre-installed on Factory Images**
- Include GEOPM packages on the platform's default Linux image.
- `geopm.service` enabled by default via systemd with sensible access defaults.

**Custom IOGroup Development**
- Platform engineers write IOGroups for platform-specific hardware (board-level
  sensors, voltage regulators, fan controllers, GPU power domains, proprietary
  management interfaces).
- IOGroups are C++ shared libraries loaded as plugins — no need to modify
  GEOPM core.
- Can be maintained as a separate package that layers on top of the base
  GEOPM packages.

**Validation & QA**
- Use `geopmread` to verify sensor accuracy during manufacturing QA.
- Use `geopmopt` to characterize power/performance envelopes for reference
  workloads.
- GEOPM can be part of the hardware validation pipeline.

**Coexistence with Existing Management**
- GEOPM operates alongside Redfish/IPMI/BMC — it is an OS-level service,
  not a firmware replacement.
- Can complement out-of-band management with in-band, low-latency,
  application-aware power control.

---

## 8. Installation & Packaging

(Source: https://geopm.github.io/install.html)

**Methods:**
- **Linux Packages**: Pre-built packages available for major distributions:
  - **Fedora / OpenSUSE**: Available from upstream distro repos
  - **Ubuntu / RHEL / Rocky / CentOS**: Public package repositories maintained
    in OBS and Launchpad
- **Spack**: Supported for HPC environments to manage dependencies and versions.
- **Source Build**: For custom configurations, unsupported OSs, or development.

**Key Packages:**
- `geopmd`: GEOPM Access Service daemon
- `python3-geopmdpy`: Python implementation for GEOPM Access service user
  interfaces (CLI)
- `libgeopmd`: PlatformIO and GEOPM Access Service C++ implementation
- `libgeopm`: GEOPM HPC Runtime C++ implementation
- `python3-geopmpy`: Python implementation for GEOPM HPC Runtime launch and
  analysis

**Service Enablement:**
Once installed, the service must be enabled by an admin:
```bash
sudo systemctl enable --now geopm
# Configure access lists (example: allow all features for all users)
geopmaccess -a | sudo geopmaccess -w
geopmaccess -ac | sudo geopmaccess -wc
```

For factory images, this enablement would be part of the image build process.
Access lists can be pre-configured to match the platform's capabilities.

---

## 9. Next Steps

**Questions to explore:**
- Which server platforms are being considered for GEOPM integration?
  (AI/GPU-dense servers vs. general-purpose)
- Who are the target customers for these platforms?
  (Hyperscalers, enterprise, HPC)
- Is there existing power telemetry exposed through Redfish/IPMI that GEOPM
  should complement?
- Is there custom board management firmware that GEOPM would need to
  interface with via a custom IOGroup?
- Are customers currently asking for power capping or power budgeting
  features in RFPs?

**Business case summary:**
- **BOM cost**: $0 — GEOPM is open source (BSD-3-Clause)
- **Engineering effort**: Custom IOGroup development + validation
- **Customer value**: Power management as a shipping platform feature,
  telemetry compliance
- **Competitive position**: First ODM to ship integrated open power management
- **Sustainability**: Helps customers meet ESG/sustainability commitments

---

## Appendix A: GEOPM HPC Runtime

(Source: https://geopm.github.io/runtime.html)

**Overview:**
The GEOPM Runtime is designed to enhance energy efficiency through active
hardware configuration coupled with an application's execution.

**Key Concepts:**
- **Application Feedback**: Uses application instrumentation (profiling) to
  drive hardware decisions.
- **Agents**: Control algorithms implemented as plugins (e.g.,
  `power_balancer`). Define what data is collected and how controls are set.
- **Controller**: A thread/process created on each compute node that loads the
  Agent and manages the control loop.
- **`geopmlaunch`**: A wrapper for the MPI launcher (like `mpiexec`) that sets
  up the GEOPM infrastructure alongside the application.
  https://geopm.github.io/geopmlaunch.1.html
- **Scalable Hierarchical**: Agents coordinate through non-blocking
  communication over a balanced tree hierarchy.

**Use Case: Power Balancer Agent**
- Distributes power across nodes in an MPI job to maximize aggregate
  performance under a global power cap.
- Identifies critical path and shifts power from waiting nodes to those doing
  useful work.

---

## Appendix B: Automatic Instrumentation — OMPT & PMPI

GEOPM enables automatic instrumentation of applications without source code
modification.

- **OMPT (OpenMP Tools Interface)**: Automatically detects OpenMP parallel
  regions.
- **PMPI (Profiling MPI)**: Intercepts MPI calls to profile communication
  phases.
- This allows GEOPM to correlate hardware telemetry with application phases
  (compute vs. communication) for context-aware optimization.

POC to apply similar methodology to pytorch:
https://github.com/cmcantalupo/geopm/tree/python-prof-torch
