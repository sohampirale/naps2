# Getting Started: How to Begin Implementation

## Prerequisites

1. **Development environment:**
   - .NET 9 SDK
   - Visual Studio 2022 (or JetBrains Rider, or VS Code with C# extension)
   - Git

2. **Build the project first:**
   ```bash
   dotnet build NAPS2.sln
   ```
   Or for Linux:
   ```bash
   dotnet build NAPS2.sln -p:BuildingInsideNaps2=true
   ```

3. **Run the tests to verify:**
   ```bash
   dotnet test NAPS2.Lib.Tests
   dotnet test NAPS2.Sdk.Tests
   ```

## First Steps (Recommended Order)

### Step 1: Understand the Codebase (1-2 hours)

Read these key files to understand the patterns:
```
NAPS2.Sdk/ImportExport/Email/IEmailProvider.cs
NAPS2.Lib/ImportExport/Email/IEmailProviderFactory.cs
NAPS2.Lib/ImportExport/Email/AutofacEmailProviderFactory.cs
NAPS2.Lib/Modules/EmailModule.cs
NAPS2.Lib/Pdf/SavePdfOperation.cs
NAPS2.Lib/ImportExport/ExportController.cs
NAPS2.Lib/ImportExport/AutoSaver.cs
```

### Step 2: Create the SDK Interface Layer

Create files in `NAPS2.Sdk/ImportExport/Cloud/`:
1. `ICloudUploadProvider.cs`
2. `CloudUploadParams.cs`
3. `CloudUploadResult.cs`

### Step 3: Implement WebDAV Provider

Create `NAPS2.Sdk/ImportExport/Cloud/Providers/WebDavCloudProvider.cs`

This is the simplest provider and will validate your interface design.

### Step 4: Create Factory + Controller

1. `NAPS2.Lib/ImportExport/Cloud/ICloudUploadProviderFactory.cs`
2. `NAPS2.Lib/ImportExport/Cloud/AutofacCloudUploadProviderFactory.cs`
3. `NAPS2.Lib/ImportExport/Cloud/CloudUploadController.cs`

### Step 5: Wire Up DI

Create `NAPS2.Lib/ImportExport/Cloud/Modules/CloudUploadModule.cs`
Modify `NAPS2.Lib/AutoFacHelper.cs` to include the module.

### Step 6: Write Tests

Create tests in `NAPS2.Lib.Tests/ImportExport/Cloud/`:
- Mock `ICloudUploadProvider`
- Test `CloudUploadController` with mock
- Test WebDAV provider with a local test server

### Step 7: Implement OAuth2 Providers

1. Google Drive (uses `OauthProvider` base class)
2. Dropbox
3. OneDrive

### Step 8: Add Custom HTTP Provider

For maximum flexibility.

### Step 9: Create SaveAndUploadOperation

Wrap save + upload in a single operation with progress.

### Step 10: Add UI

1. Cloud Upload settings panel
2. "Scan & Upload" button
3. Context menu action
4. Upload result notification

## Verification at Each Step

| Step | How to Verify |
|------|--------------|
| Step 2 | Write a unit test that creates a mock `ICloudUploadProvider` |
| Step 3 | Run the WebDAV provider against a local WebDAV server (use `npm install -g webdav` for a test server) |
| Step 5 | Ensure the app starts without DI errors |
| Step 6 | All tests pass |
| Step 7 | Authenticate with Google Drive and upload a test file |
| Step 10 | End-to-end scan -> save -> upload flow works |

## Quick Test: WebDAV Local Server

```bash
# Install a simple WebDAV server
npm install -g webdav

# Start it
webdav --host 0.0.0.0 --port 8080 --path ./webdav-data

# In NAPS2 settings:
# URL: http://localhost:8080/
# Username: (leave blank)
# Password: (leave blank)
```

## Useful Commands

```bash
# Build
dotnet build NAPS2.sln

# Run tests
dotnet test NAPS2.Lib.Tests
dotnet test NAPS2.Sdk.Tests

# Run NAPS2 (Linux GTK)
dotnet run --project NAPS2.App.Gtk

# Run NAPS2 (Console)
dotnet run --project NAPS2.App.Console
```
