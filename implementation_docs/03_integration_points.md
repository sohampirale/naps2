# Integration Points: Where to Hook Into NAPS2

This document identifies the exact files and line numbers where cloud upload functionality should be integrated.

## 1. PDF Generation Hook (Stream-Based)

**File:** `NAPS2.Sdk/Pdf/PdfExporter.cs`
**Lines:** 41-43 (method signature)

```csharp
public void Export(string path, IEnumerable<ProcessedImage> images,
    PdfExportParams pdfExportParams, OcrParams ocrParams,
    ProgressHandler progress)
```

The `PdfExporter` already supports `Stream` output internally. The export pipeline writes to a `MemoryStream` first, then to file. This means we can:

1. Call `PdfExporter.Export()` to a MemoryStream
2. Save that stream to local file
3. **Upload the same stream to cloud** without re-reading from disk

## 2. ExportController Extension Point

**File:** `NAPS2.Lib/ImportExport/ExportController.cs`
**Method:** `SavePdf()` (around line 80-90)

This is the primary method that saves scanned pages as PDF. After the PDF is saved to disk, we add cloud upload logic.

**Current flow:**
```
SavePdf(options)
    -> SavePdfOperation.Start(images, path, ...)
    -> returns success/failure
```

**Target flow:**
```
SavePdf(options, uploadToCloud: true)
    -> SavePdfOperation.Start(images, path, ...)
    -> if uploadToCloud:
         CloudUploadController.Upload(path, ...)
```

## 3. AutoSave Integration (Headless/One-Click Scan)

**File:** `NAPS2.Lib/ImportExport/AutoSaver.cs`
**Method:** `Save()` (around line 50-70)

The `AutoSaver` runs during scanning when "Auto-save" is enabled. This is the ideal place for "scan and auto-upload" in a single-click workflow.

**Current flow:**
```
AutoSaver.Save(images, profile, scanParams)
    -> determines save format (PDF/images)
    -> calls ExportController.SavePdf() or SaveImages()
    -> returns saved file path(s)
```

**Target flow:**
```
AutoSaver.Save(images, profile, scanParams)
    -> determines save format
    -> calls save
    -> if cloud upload enabled in profile:
         CloudUploadController.Upload(savedPath, ...)
```

## 4. Email Provider Pattern (Reference Implementation)

**Files (to follow as template):**
- `NAPS2.Sdk/ImportExport/Email/IEmailProvider.cs` - Interface definition
- `NAPS2.Lib/ImportExport/Email/IEmailProviderFactory.cs` - Factory interface
- `NAPS2.Lib/ImportExport/Email/EmailProviderController.cs` - Provider orchestration
- `NAPS2.Lib/Modules/EmailModule.cs` - DI registration

**Providers that demonstrate OAuth2 + HTTP upload:**
- `NAPS2.Lib/ImportExport/Email/Gmail/GmailEmailProvider.cs` - Gmail API draft upload
- `NAPS2.Lib/ImportExport/Email/OutlookWeb/OutlookWebEmailProvider.cs` - Microsoft Graph upload

These demonstrate:
1. How to acquire OAuth2 tokens using the base `OauthProvider` class
2. How to make authenticated multipart HTTP uploads
3. How to report upload progress
4. How to handle token refresh
5. How to register via Autofac

## 5. OAuth2 Infrastructure (Reusable)

**File:** `NAPS2.Lib/ImportExport/Email/Oauth/OauthProvider.cs`

This base class handles:
- Authorization code flow with PKCE
- Local HTTP server for redirect URI capture
- Token storage and refresh
- `Get()`, `Post()`, `PostAuthorized()` HTTP helper methods

**To reuse for cloud upload providers:**
```csharp
public class GoogleDriveOauthProvider : OauthProvider
{
    protected override string ClientId => "...";
    protected override string Scope => "https://www.googleapis.com/auth/drive.file";
    protected override string TokenEndpoint => "https://oauth2.googleapis.com/token";
    protected override string AuthEndpoint => "https://accounts.google.com/o/oauth2/v2/auth";
    // ... flows inherited from base
}
```

## 6. UI Integration - DesktopController

**File:** `NAPS2.Lib/EtoForms/Desktop/DesktopController.cs`

This is the main UI controller. Key methods to extend:

- `SavePdf()` - Add optional upload parameter
- `ScanDefault()` or `ScanWithProfile()` - Add "Scan & Upload" variant
- New method: `ScanAndUpload(ScanProfile)` - Chains scan -> save -> upload

## 7. UI Integration - ImageListActions

**File:** `NAPS2.Lib/EtoForms/Desktop/ImageListActions.cs`

This handles context menu actions on scanned images. Add:
- `Upload` action
- `UploadVisible` / `UploadEnabled` properties

## 8. Settings Integration

**File:** `NAPS2.Lib/EtoForms/Settings/` (directory)

Look at existing settings panels for pattern:
- `EmailSettingsPanel.cs` - Provider selection, auth button
- `SaveSettingsPanel.cs` - File format, path, naming

New file: `CloudUploadSettingsPanel.cs`

## 9. Autofac Registration

**File:** `NAPS2.Lib/Modules/CommonModule.cs` (or new `CloudUploadModule.cs`)

Registration pattern:
```csharp
builder.RegisterType<GoogleDriveCloudProvider>()
    .As<ICloudUploadProvider>()
    .SingleInstance();

builder.RegisterType<AutofacCloudUploadProviderFactory>()
    .As<ICloudUploadProviderFactory>()
    .SingleInstance();

builder.RegisterType<CloudUploadController>()
    .SingleInstance();
```

## 10. Console Mode Integration

**File:** `NAPS2.App.Console/` - If you want CLI support for headless scan+upload

## Summary of Files to Create

```
NAPS2.Sdk/ImportExport/Cloud/
    ICloudUploadProvider.cs                    (NEW)
    CloudUploadParams.cs                       (NEW)
    CloudUploadResult.cs                       (NEW)
    Providers/
        WebDavCloudProvider.cs                 (NEW)
        GoogleDriveCloudProvider.cs            (NEW)
        DropboxCloudProvider.cs                (NEW)
        OneDriveCloudProvider.cs               (NEW)
        CustomHttpCloudProvider.cs             (NEW)

NAPS2.Lib/ImportExport/Cloud/
    CloudUploadController.cs                   (NEW)
    ICloudUploadProviderFactory.cs             (NEW)
    AutofacCloudUploadProviderFactory.cs       (NEW)
    SaveAndUploadOperation.cs                  (NEW)
    Modules/
        CloudUploadModule.cs                   (NEW)

NAPS2.Lib/EtoForms/Desktop/
    DesktopController.cs                       (MODIFY)
    DesktopScanController.cs                   (MODIFY)
    ImageListActions.cs                        (MODIFY)
    Settings/
        CloudUploadSettingsPanel.cs            (NEW)

## Summary of Files to Modify

```
NAPS2.Lib/ImportExport/ExportController.cs     (MODIFY: add upload after save)
NAPS2.Lib/ImportExport/AutoSaver.cs             (MODIFY: add auto-upload)
NAPS2.Lib/EtoForms/Desktop/DesktopController.cs (MODIFY: add upload buttons)
NAPS2.Lib/EtoForms/Desktop/ImageListActions.cs  (MODIFY: add upload action)
NAPS2.Lib/Modules/CommonModule.cs               (MODIFY: register cloud services)
```
