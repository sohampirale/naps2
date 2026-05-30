# Implementation Plan: Phase by Phase

## Phase 1: Foundation (Core Interfaces & DI)

### Goal
Establish the interface contracts and dependency injection wiring so that the rest of the implementation builds on a solid foundation.

### Tasks

**1.1 Create SDK Interfaces and Data Types**

Files to create:
- `NAPS2.Sdk/ImportExport/Cloud/ICloudUploadProvider.cs`
- `NAPS2.Sdk/ImportExport/Cloud/CloudUploadParams.cs`
- `NAPS2.Sdk/ImportExport/Cloud/CloudUploadResult.cs`

Key decisions:
- `ICloudUploadProvider` should follow `IEmailProvider` closely
- All upload methods should be async (`Task<CloudUploadResult>`)
- Support progress reporting via `IProgress<UploadProgress>` or `ProgressHandler`

**1.2 Create Factory Interface**

File: `NAPS2.Lib/ImportExport/Cloud/ICloudUploadProviderFactory.cs`
- Modeled after `IEmailProviderFactory`
- Methods: `Create(CloudProviderType)`, `RegisteredProviders`, `Default`

**1.3 Create First Provider (WebDAV)**

File: `NAPS2.Sdk/ImportExport/Cloud/Providers/WebDavCloudProvider.cs`
- Simplest provider: just PUT to a URL with basic auth or no auth
- No OAuth2 needed, good for testing
- Validates the interface design before tackling OAuth providers

**1.4 Create Autofac Module**

File: `NAPS2.Lib/ImportExport/Cloud/Modules/CloudUploadModule.cs`
- Register `ICloudUploadProvider`, `ICloudUploadProviderFactory`, `CloudUploadController`
- Include in `AutoFacHelper.FromModules()` in `AutoFacHelper.cs`

### Deliverables
- `ICloudUploadProvider` interface defined and stable
- WebDAV upload working end-to-end via unit test
- DI wiring complete

---

## Phase 2: OAuth2 Cloud Providers

### Goal
Implement upload providers for real cloud services using OAuth2 authentication.

### Tasks

**2.1 Google Drive Provider**

File: `NAPS2.Sdk/ImportExport/Cloud/Providers/GoogleDriveCloudProvider.cs`

Steps:
1. Create `GoogleDriveOauthProvider` extending `OauthProvider` base class
2. Implement `AuthenticateAsync()` using OAuth2 code flow with PKCE
3. Implement `UploadAsync()` using Google Drive API v3:
   - Create multipart upload request
   - POST to `https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart`
   - Handle 200/201 response, extract file ID
   - Optionally set permissions to "Anyone with link can view"
4. Implement `GetShareLink()` using Drive API v3 permissions endpoint

**2.2 Dropbox Provider**

File: `NAPS2.Sdk/ImportExport/Cloud/Providers/DropboxCloudProvider.cs`

Steps:
1. Create `DropboxOauthProvider` extending `OauthProvider`
2. Use Dropbox API v2:
   - POST `https://content.dropboxapi.com/2/files/upload`
   - Requires `Dropbox-API-Arg` header with path/mode JSON
   - Returns `{ "id": "...", "name": "...", "path_display": "..." }`
3. Get shareable link via `https://api.dropboxapi.com/2/sharing/create_shared_link_with_settings`

**2.3 OneDrive Provider**

File: `NAPS2.Sdk/ImportExport/Cloud/Providers/OneDriveCloudProvider.cs`

Steps:
1. Create `OneDriveOauthProvider` extending `OauthProvider` (follow `OutlookWebOauthProvider`)
2. Use Microsoft Graph API:
   - PUT `https://graph.microsoft.com/v1.0/me/drive/root:/{path}:/content`
   - Returns item metadata with `webUrl` for sharing

### Deliverables
- Google Drive, Dropbox, OneDrive all working
- OAuth token storage and refresh working
- Progress reporting during upload

---

## Phase 3: Custom HTTP Endpoint Provider

### Goal
Allow users to upload to any HTTP API (their own server, S3-compatible storage, etc.)

### Task

**3.1 Custom HTTP Provider**

File: `NAPS2.Sdk/ImportExport/Cloud/Providers/CustomHttpCloudProvider.cs`

Features:
- Configurable HTTP method (PUT, POST)
- Configurable headers (for API keys, custom auth)
- Configurable body format (binary, multipart, base64 JSON)
- Pre-upload webhook/script support
- Response validation (status code, JSON path)
- No OAuth2 required by default (but configurable headers allow Bearer tokens)

Settings UI will have:
- URL template (supports `{filename}`, `{date}`, `{size}` variables)
- HTTP method selector
- Headers table (key-value pairs)
- Success criteria (status code range, response body contains string)

---

## Phase 4: CloudUploadController & Operation

### Goal
Orchestrate the full scan -> save -> upload pipeline with proper progress reporting.

### Tasks

**4.1 Create CloudUploadController**

File: `NAPS2.Lib/ImportExport/Cloud/CloudUploadController.cs`

```csharp
public class CloudUploadController
{
    private readonly ICloudUploadProviderFactory _factory;

    // Upload from already-saved file path
    public async Task<CloudUploadResult> UploadFileAsync(
        string filePath, CloudUploadParams uploadParams,
        CancellationToken ct, ProgressHandler progress);

    // Upload from stream (no local save needed)
    public async Task<CloudUploadResult> UploadStreamAsync(
        Stream fileStream, string fileName, CloudUploadParams uploadParams,
        CancellationToken ct, ProgressHandler progress);
}
```

**4.2 Create SaveAndUploadOperation**

File: `NAPS2.Lib/ImportExport/Cloud/SaveAndUploadOperation.cs`

```csharp
public class SaveAndUploadOperation : IOperation
{
    // Stages:
    //   1. Save PDF to local disk (delegates to SavePdfOperation)
    //   2. Upload to cloud (delegates to CloudUploadController)
    //   3. On completion: show link / open browser

    public ProgressStatus Status { get; }
    public Task<bool> Success { get; }
    public void Cancel();
}
```

**4.3 Modify AutoSaver**

File: `NAPS2.Lib/ImportExport/AutoSaver.cs`

Add upload capability to the auto-save pipeline:
```csharp
if (profile.CloudUpload.Enabled)
{
    var result = await _cloudUploadController.UploadFileAsync(
        savedPath, profile.CloudUpload, ct, progress);
}
```

### Deliverables
- `CloudUploadController` working with all providers
- `SaveAndUploadOperation` with progress and cancellation
- Auto-save + auto-upload working in single-click mode

---

## Phase 5: UI Integration

### Goal
Add UI elements for cloud upload: buttons, menus, settings panel.

### Tasks

**5.1 Settings Panel**

File: `NAPS2.Lib/EtoForms/Desktop/Settings/CloudUploadSettingsPanel.cs`

Controls:
- Enable/disable cloud upload toggle
- Provider dropdown (WebDAV, Google Drive, Dropbox, OneDrive, Custom HTTP)
- Authenticate button (triggers OAuth2 flow)
- Deauthorize button
- Target folder path text input
- Filename template input (variables: `{date}`, `{time}`, `{scanner_name}`, `{page_count}`)
- After-upload action: Nothing / Open in Browser / Copy Link to Clipboard

**5.2 Scan Button**

Modify `DesktopScanController.cs` to add:
- "Scan & Upload" button near existing scan buttons
- If auto-save + cloud upload are configured, a single "Scan & Upload" click does everything

**5.3 Context Menu**

Modify `ImageListActions.cs` to add:
- Right-click -> "Upload to Cloud..."
- Opens provider selector if multiple configured

**5.4 Result Notification**

After upload completes:
- Success: show notification with link (clickable to open in browser)
- Failure: show error with retry button

### Deliverables
- Settings panel fully functional
- "Scan & Upload" button working
- Context menu upload action working
- Upload result notifications

---

## Phase 6: Polish & Edge Cases

### Goal
Handle errors, large files, retries, and edge cases.

### Tasks

**6.1 Error Handling**
- Network errors: auto-retry (3 attempts with exponential backoff)
- Auth token expired: auto-refresh and retry
- File too large: show meaningful error (provider limits vary)
- Rate limiting: respect Retry-After headers

**6.2 Large File Support**
- For providers that support it: chunked upload (Google Drive supports resumable upload)
- Progress reporting: bytes uploaded / total bytes
- Memory management: stream directly from file, not MemoryStream

**6.3 Filename Collision Handling**
- Provider returns conflict error -> auto-rename with suffix, or overwrite based on user preference

**6.4 Cancellation**
- User cancels during upload -> provider-specific cleanup
- Partial upload: delete partial file from cloud if possible

**6.5 Testing**
- Unit tests for each provider (mock HTTP)
- Integration test with WebDAV (local test server)
- Manual tests: Google Drive, Dropbox, OneDrive

### Deliverables
- Production-ready error handling
- Large file support
- All edge cases documented and handled
- Test suite

---

## Summary Timeline

```
Phase 1: Foundation      | Week 1
Phase 2: OAuth Providers | Weeks 2-3
Phase 3: Custom HTTP     | Week 4
Phase 4: Controller      | Week 4
Phase 5: UI Integration  | Week 5
Phase 6: Polish & Tests  | Week 6
-------------------------|--------
Total                    | ~6 weeks (full-time)
```
