# Architecture Overview: Cloud Upload Feature

## High-Level Flow

```
User clicks "Scan & Upload"
         |
         v
[1] ScanPerformer.DoScan()
    |-- Scans pages via IScanDriver (WIA/TWAIN/SANE/ESCL)
    |-- PostProcesses (transform, OCR, blank page removal)
    |-- Returns ProcessedImage[]
         |
         v
[2] SavePdfOperation.Start()
    |-- PdfExporter.Export() -> generates PDF to MemoryStream
    |-- Writes PDF to local disk
         |
         v
[3] CloudUploadOperation.Start()
    |-- ICloudUploadProvider.UploadAsync(stream, filename, progress)
    |-- Reports progress via IOperation status events
    |-- On success: marks upload as complete
    |-- On failure: shows error, offers retry
```

## Key Components

### 1. Interface Layer (`NAPS2.Sdk/ImportExport/Cloud/`)

```
ICloudUploadProvider
    |-- Name (string) - "Google Drive", "Dropbox", etc.
    |-- Icon (Icon)      - Provider icon for UI
    |-- IsAuthenticated  - Whether user has authenticated
    |-- AuthenticateAsync() - OAuth2 or API key flow
    |-- UploadAsync(Stream, fileName, progressCallback) - Upload a file
    |-- CanUploadInBackground - Whether supported in headless/auto mode
    |-- SettingsControl - Optional embedded settings widget

CloudUploadParams
    |-- ProviderType
    |-- TargetPath      - Cloud folder/filename template
    |-- OverwritePolicy - Ask, Overwrite, Rename
    |-- AfterUpload     - Nothing, OpenInBrowser, CopyLink

CloudUploadResult
    |-- Success
    |-- RemoteUrl       - Shareable link to uploaded file
    |-- ErrorMessage
```

### 2. Controller Layer (`NAPS2.Lib/ImportExport/Cloud/`)

```
CloudUploadController
    |-- ICloudUploadProviderFactory (resolves providers by type)
    |-- Upload(processedImages, params) -> CloudUploadResult
    |-- Upload(filePath, params) -> CloudUploadResult  (for already-saved files)
    |-- Events: UploadProgress, UploadComplete, UploadError

ICloudUploadProviderFactory
    |-- Create(CloudProviderType) -> ICloudUploadProvider
    |-- RegisteredProviders -> IEnumerable<ICloudUploadProvider>
    |-- Default -> ICloudUploadProvider (based on user settings)
```

### 3. Operation Layer (`NAPS2.Lib/ImportExport/Cloud/`)

```
SaveAndUploadOperation : IOperation
    |-- Combines SavePdfOperation + CloudUploadOperation
    |-- Progress shows: "Saving PDF... (50%)" then "Uploading... (75%)"
    |-- Supports cancellation between save and upload phases
    |-- On completion: shows result dialog with link if available
```

### 4. UI Layer

**New buttons/options:**
- "Scan and Upload" button next to existing "Scan" button
- "Upload" context menu item on scanned documents
- "Cloud Upload" as a save option (alongside Save, Email)

**Settings panel additions:**
- Cloud provider dropdown selector
- "Authenticate" button for selected provider
- Target folder path input (with variable support: `{date}`, `{time}`, `{scanner}`, etc.)
- Filename template input
- After-upload action selector

### 5. Autofac Module

```
CloudUploadModule : Module
    |-- Registers ICloudUploadProviderFactory
    |-- Registers each ICloudUploadProvider implementation
    |-- Registers CloudUploadController
    |-- Registers SaveAndUploadOperation
```

## Design Patterns Used

| Pattern | Where | Why |
|---------|-------|-----|
| **Strategy** | `ICloudUploadProvider` implementations | Swap providers without changing upload logic |
| **Factory** | `ICloudUploadProviderFactory` | Encapsulate provider instantiation |
| **Decorator** | `SaveAndUploadOperation` | Wrap save + upload into single operation |
| **Observer** | `IOperation` status events | UI observes operation progress |
| **Template Method** | `OauthProvider` base class | Shared OAuth2 flow for all providers |
| **DI** | Autofac modules | Decouple component registration |

## File Locations

```
NAPS2.Sdk/ImportExport/Cloud/
    ICloudUploadProvider.cs
    CloudUploadParams.cs
    CloudUploadResult.cs
    Providers/
        WebDavCloudProvider.cs
        GoogleDriveCloudProvider.cs
        DropboxCloudProvider.cs
        OneDriveCloudProvider.cs
        CustomHttpCloudProvider.cs

NAPS2.Lib/ImportExport/Cloud/
    CloudUploadController.cs
    ICloudUploadProviderFactory.cs
    AutofacCloudUploadProviderFactory.cs
    SaveAndUploadOperation.cs
    Modules/
        CloudUploadModule.cs

NAPS2.Lib/EtoForms/Desktop/
    DesktopController.cs         (modified: add upload buttons)
    ImageListActions.cs           (modified: add upload action)
    Settings/
        CloudUploadSettingsPanel.cs   (new)
        CloudUploadSettingsViewModel.cs (new)
```
