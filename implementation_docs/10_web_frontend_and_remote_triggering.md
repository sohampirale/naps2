# Web Frontend + Remote Scan Triggering System

## Overview

You're asking about a system where:
1. A **web frontend** interacts with a **cloud service**
2. The **cloud service** sends instructions to NAPS2 (which scanner, which folder, what settings)
3. **NAPS2** performs targeted scans to **specific folders** based on those instructions
4. The scanned PDFs are then **automatically uploaded to the cloud**

This transforms the project from "add upload capability" to **"build a remote scan management platform"** with NAPS2 as the scanning engine.

---

## System Architecture

```
┌─────────────┐     ┌──────────────────┐     ┌─────────────────────────────┐
│  Web        │────▶│  Cloud Service   │────▶│  NAPS2 (Extended)           │
│  Frontend   │     │  (Your Server)   │     │                             │
│  (React/    │     │                  │     │  ┌─────────────────────┐   │
│   Vue/etc)  │◀────│  - Auth          │◀────│  │ EmbedIO HTTP Server │   │
│             │     │  - Scan Queue    │     │  │ (REST API)           │   │
│             │     │  - Folder Mgmt   │     │  ├─────────────────────┤   │
│             │     │  - Device Mgmt   │     │  │ GET  /api/profiles  │   │
│             │     │  - File Storage  │     │  │ POST /api/scan      │   │
│             │     │  - Status/Logs   │     │  │ GET  /api/status    │   │
│             │     │                  │     │  │ POST /api/upload    │   │
│             │     │                  │     │  └─────────────────────┘   │
│             │     │                  │     │                             │
│             │     │                  │     │  ┌─────────────────────┐   │
│             │     │                  │     │  │ ScanController      │   │
│             │     │                  │     │  │ (NAPS2.Sdk)         │   │
│             │     │                  │     │  ├─────────────────────┤   │
│             │     │                  │     │  │ ExportController    │   │
│             │     │                  │     │  │ (PDF Save)          │   │
│             │     │                  │     │  └─────────────────────┘   │
│             │     │                  │     │                             │
└─────────────┘     └──────────────────┘     └─────────────────────────────┘
```

### Component Breakdown

#### 1. Web Frontend
- A web dashboard (React, Vue, or plain HTML/JS)
- Hosted by the cloud service (or separately)
- Features:
  - View available scanners across all connected NAPS2 instances
  - Create scan jobs: pick scanner, target folder, settings (DPI, color, duplex)
  - View scan history and download results
  - Monitor scan status in real-time (WebSocket or polling)

#### 2. Cloud Service (Your Server)
- A backend server (Node.js, Python, Go, or .NET)
- Manages authentication, scan queue, file storage
- REST API for the frontend
- WebSocket/SSE for real-time updates
- Stores scan configurations (which folder for which department, etc.)
- Receives completed scans from NAPS2 and serves them to the frontend

#### 3. NAPS2 Extended
- The existing NAPS2 project with additions:
  - **EmbedIO REST API** — new endpoints for remote control
  - **Daemon mode** — NAPS2 runs as a background service (not just GUI)
  - **Folder targeting** — accepts folder paths from cloud instructions
  - **Cloud upload** — uploads completed scans back to cloud service

---

## Key Architecture Decision: Polling vs. WebSocket

### Polling (Simpler)
```
NAPS2 -> GET https://cloud.example.com/api/next-job
        (returns scan instructions or 204 No Content)
NAPS2 -> executes scan -> saves to folder -> uploads result
```

**Pros:** Simple, no persistent connection, firewall-friendly
**Cons:** Delay between job creation and execution (depends on polling interval)

### WebSocket / Long-Polling (Real-time)
```
Cloud -> WebSocket connection to NAPS2
Cloud -> sends: { "command": "scan", "device": "...", "folder": "...", "settings": {...} }
NAPS2 -> executes scan -> saves -> uploads result
```

**Pros:** Real-time triggering, bidirectional
**Cons:** Requires persistent connection, NAT/firewall traversal issues

### Recommended: Hybrid
- **Cloud -> NAPS2:** Polling (simpler, more reliable across networks)
- **NAPS2 -> Cloud:** HTTP callback/POST on completion
- **Frontend -> Cloud:** WebSocket for real-time UI updates

---

## Folder Targeting Logic

The key requirement: "scanning in particular folder of folders so its not random scanning"

### How It Works

The cloud service sends instructions like:

```json
{
  "scanJobId": "job-123",
  "device": "HP LaserJet MFP",
  "settings": {
    "source": "feeder",
    "dpi": 300,
    "bitDepth": "color",
    "pageSize": "letter"
  },
  "output": {
    "localFolder": "C:\\Scans\\Invoices\\2025-01-15",
    "filenameTemplate": "invoice_{jobId}_{page}.pdf",
    "cloudTarget": "/documents/invoices/",
    "afterAction": "upload_and_notify"
  }
}
```

### Folder Determination Strategies

| Strategy | Description | Use Case |
|----------|-------------|----------|
| **Static** | Cloud specifies exact folder path | User selects folder from web UI |
| **Rule-based** | Cloud sends rules: "if document type = invoice, folder = /Invoices" | Automated document routing |
| **User-based** | Folder derived from authenticated user | Multi-tenant environments |
| **Date-based** | Auto-generated from date | Archival workflows |
| **QR/Barcode** | Scan a cover sheet, barcode determines folder | Physical document routing |

### Implementation in NAPS2

The `AutoSaveSettings.FilePath` field already supports placeholders. Extend it to accept dynamic values from the cloud:

```csharp
// Current:
"C:\\Scans\\$(YYYY)-$(MM)-$(DD)\\scan_$(nnnn).pdf"

// Extended with cloud variable injection:
cloudJob.Output.LocalFolder + "\\" + cloudJob.Output.FilenameTemplate
// Where cloudJob replaces $(jobId), $(page), $(type), etc.
```

---

## REST API to Add to NAPS2 (via EmbedIO)

The existing `EsclServer` already runs EmbedIO. Add a new controller for remote scan management.

### Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/v1/status` | NAPS2 status (running, scanning, idle, scanner connected) |
| `GET` | `/api/v1/profiles` | List scan profiles |
| `GET` | `/api/v1/devices` | List connected scanners |
| `POST` | `/api/v1/scan` | Trigger a scan with full parameters |
| `GET` | `/api/v1/scan/{jobId}/status` | Check scan job status |
| `POST` | `/api/v1/scan/{jobId}/cancel` | Cancel a running scan |
| `GET` | `/api/v1/jobs` | List recent scan jobs |
| `POST` | `/api/v1/upload-complete` | Acknowledgment from cloud that file was received |
| `GET` | `/api/v1/config` | Get current NAPS2 config (anonymized) |

### POST /api/v1/scan — Request Body

```json
{
  "deviceName": "HP LaserJet MFP",
  "driver": "wia",
  "profileName": null,
  "settings": {
    "source": "feeder",
    "dpi": 300,
    "bitDepth": "color",
    "paperSize": "letter",
    "duplex": true,
    "deskew": true,
    "blankPageRemoval": true
  },
  "output": {
    "format": "pdf",
    "localFolder": "C:\\Scans\\Invoices",
    "filename": "invoice_{datetime}_{id}",
    "uploadUrl": "https://cloud.example.com/api/upload",
    "uploadToken": "eyJhbGciOiJIUzI1NiIs..."
  },
  "callback": {
    "url": "https://cloud.example.com/api/scan-complete",
    "method": "POST",
    "headers": {
      "Authorization": "Bearer token123"
    }
  }
}
```

### POST /api/v1/scan — Response

```json
{
  "jobId": "naps2-job-456",
  "status": "accepted",
  "estimatedPages": 10,
  "checkStatusUrl": "/api/v1/scan/naps2-job-456/status"
}
```

### Scan Callback (NAPS2 -> Cloud)

When scan completes, NAPS2 POSTs to the callback URL:

```json
{
  "jobId": "naps2-job-456",
  "cloudJobId": "job-123",
  "status": "completed",
  "pages": 5,
  "file": {
    "name": "invoice_20250115_143022_1.pdf",
    "size": 1234567,
    "localPath": "C:\\Scans\\Invoices\\invoice_20250115_143022_1.pdf",
    "checksum": "sha256:abc123..."
  },
  "uploadResult": {
    "success": true,
    "cloudUrl": "https://cloud.example.com/documents/invoice_20250115_143022_1.pdf"
  },
  "errors": null,
  "startedAt": "2025-01-15T14:30:00Z",
  "completedAt": "2025-01-15T14:30:45Z"
}
```

---

## Daemon/Service Mode

NAPS2 currently runs as a GUI app or a one-shot CLI. For this system, you need a **persistent background mode**.

### Implementation Approaches

#### A. NAPS2 as a Windows Service / Linux Daemon (Recommended)

Create a new project: `NAPS2.App.Daemon`

```csharp
public class Naps2Daemon
{
    private EmbedIO.WebServer _httpServer;
    private ScanController _scanController;
    private CloudUploadController _cloudUpload;

    public async Task StartAsync()
    {
        // 1. Initialize ScanningContext
        // 2. Start EmbedIO HTTP server with /api/* endpoints
        // 3. Start polling cloud for jobs (or connect WebSocket)
        // 4. Process scan jobs as they arrive
        // 5. Upload results to cloud
    }

    public async Task StopAsync()
    {
        await _httpServer.StopAsync();
    }
}
```

**Windows:** Use `System.ServiceProcess.ServiceBase`
**Linux:** Use systemd unit file
**macOS:** Use launchd plist

#### B. NAPS2 GUI + Background HTTP Server

The existing GUI app also starts an EmbedIO HTTP server in the background. This is simpler but requires the user to be logged in.

**Current ESCL server already does this** — `ScanServer.RunAsync()` starts the HTTP server. Extend it with new controllers.

---

## Web Frontend Options

### Option 1: Standalone Web App (Recommended)

Build as a separate project that talks to the cloud service:

```
naps2-web-frontend/
├── index.html
├── src/
│   ├── App.jsx / App.vue
│   ├── components/
│   │   ├── ScannerList.vue
│   │   ├── ScanJobForm.vue
│   │   ├── ScanHistory.vue
│   │   └── FolderSelector.vue
│   ├── api/
│   │   └── cloudService.js
│   └── views/
│       ├── Dashboard.vue
│       ├── ScanConfig.vue
│       └── Logs.vue
└── package.json
```

### Option 2: Embedded in NAPS2 (Eto.Forms WebView)

For a desktop-integrated approach, use Eto.Forms `WebView` control to embed the web frontend directly inside the NAPS2 window:

```csharp
var webView = new WebView();
webView.Url = new Uri("http://localhost:3000"); // Local web frontend dev server
// Or load from embedded resources
```

### Option 3: Cloud-Hosted Frontend Only

The simplest approach: host the frontend on your cloud server. It doesn't need to be part of the NAPS2 codebase at all. NAPS2 just needs the EmbedIO REST API; the frontend communicates via the cloud service, which forwards commands to NAPS2.

---

## Cloud Service Options

### Option A: Build from Scratch (Most Control)

| Technology | Why |
|-----------|-----|
| **Node.js + Express** | Easy prototyping, WebSocket support, large ecosystem |
| **Python + FastAPI** | Great for ML/document processing pipelines |
| **.NET + ASP.NET Core** | Same language as NAPS2, share models/types |
| **Go + Gin** | Lightweight, good for high-concurrency |

### Option B: Use Existing Platform

| Platform | Pros | Cons |
|----------|------|------|
| **Firebase** | Auth, DB, Storage, Serverless | Vendor lock-in |
| **Supabase** | Open-source, PostgreSQL, Auth, Storage | Self-host or cloud |
| **AWS + API Gateway + Lambda** | Scalable, managed | Complex setup |

### Option C: Serverless / Edge

For simpler use cases, use a serverless function to receive callbacks from NAPS2:

```
NAPS2 -> Cloud Function (AWS Lambda / Cloudflare Worker) -> S3 / Database
Frontend -> Reads from Database / CDN
```

---

## End-to-End Flow (Complete Example)

```
1. User opens web frontend (https://scans.mycompany.com)
2. User selects "Scan Invoices" from the dashboard
3. Frontend calls Cloud Service: POST /api/jobs
   {
     "department": "accounting",
     "documentType": "invoice",
     "targetFolder": "Invoices/Q1-2025",
     "scanner": "HP-LaserJet-Office",
     "settings": { "duplex": true, "dpi": 300 }
   }
4. Cloud Service enqueues the job, returns job ID
5. NAPS2 (running as daemon on the office PC) polls:
   GET https://scans.mycompany.com/api/jobs/next?device=HP-LaserJet-Office
6. Cloud returns: { "jobId": "abc123", "output": { "folder": "Invoices/Q1-2025", ... } }
7. NAPS2 performs scan using ScanController
8. NAPS2 saves PDF to C:\Scans\Invoices\Q1-2025\invoice_abc123.pdf
9. NAPS2 uploads PDF to cloud: POST https://scans.mycompany.com/api/upload
10. Cloud stores PDF, updates job status to "completed"
11. Frontend shows job as completed, user can download/view
```

---

## Implementation Timeline

### Phase 1: Core REST API in NAPS2 (1-2 weeks)
- Extend EmbedIO server with `/api/*` controllers
- POST /api/v1/scan endpoint
- GET /api/v1/status endpoint
- Scan job queue within NAPS2
- Folder targeting from API parameters

### Phase 2: Cloud Upload from NAPS2 (1 week)
- After scan, upload result to cloud API endpoint
- Callback on completion
- Retry logic for failed uploads

### Phase 3: Cloud Service (1-2 weeks)
- REST API for frontend (create jobs, list jobs, upload/download files)
- Job queue management
- Authentication
- File storage

### Phase 4: Web Frontend (1-2 weeks)
- Dashboard UI
- Scan job creation form
- Folder/device selection
- Scan history view
- Real-time status updates

### Phase 5: Daemon/Service Mode (1 week)
- Background service wrapper
- Auto-start on system boot
- Logging and health monitoring

### Phase 6: Production Hardening (1-2 weeks)
- Error handling and recovery
- Security review
- Documentation
- Deployment scripts

**Total: ~8-12 weeks** (full-time team)

---

## Feasibility Summary

| Question | Answer |
|----------|--------|
| Can NAPS2 be extended with a REST API? | **Yes** — EmbedIO already exists in the project (`EsclServer.cs`) |
| Can NAPS2 scan to specific folders? | **Yes** — `AutoSaveSettings.FilePath` supports dynamic paths |
| Can NAPS2 run in background/daemon mode? | **Yes** — need to build it, but all infra exists |
| Can NAPS2 receive remote commands? | **Yes** — EmbedIO REST API handles this |
| Can we build a web frontend? | **Yes** — separate from NAPS2, talks to cloud service |
| Is this more complex than cloud upload? | **Significantly** — this is a full client-server-platform with daemon, API, web UI, and cloud service |
| Is AI coding useful here? | **Very** — the EmbedIO REST controllers, web frontend, and cloud service are well-suited for AI generation |
