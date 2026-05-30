# Settings & UI Design

## Settings Storage

### Configuration Model

Add a `CloudUploadSettings` class to the existing NAPS2 settings system.

**File:** `NAPS2.Lib/Config/CloudUploadSettings.cs`

```csharp
public class CloudUploadSettings
{
    public bool Enabled { get; set; }
    public CloudProviderType ProviderType { get; set; }
    public string TargetFolder { get; set; } = "NAPS2 Scans";
    public string FilenameTemplate { get; set; } = "scan-{date}-{time}";
    public AfterUploadAction AfterAction { get; set; } = AfterUploadAction.Nothing;

    // Provider-specific stored in a Dictionary<string, string>
    public Dictionary<string, string> ProviderSettings { get; set; } = new();
}
```

### How ProviderSettings Maps to Each Provider

| Provider    | Key                | Description                    |
|------------|---------------------|--------------------------------|
| WebDAV     | `server_url`        | WebDAV server base URL         |
| WebDAV     | `username`          | WebDAV username                |
| WebDAV     | `password_ref`      | OS keychain reference (not stored in config!) |
| Google Drive| `target_folder_id` | Google Drive folder ID (empty = root) |
| Dropbox    | `target_path`       | Dropbox path (e.g., `/Apps/NAPS2`) |
| OneDrive   | `target_path`       | OneDrive path (e.g., `Documents/Scans`) |
| Custom HTTP| `method`            | HTTP method (PUT/POST)         |
| Custom HTTP| `url`               | URL template                   |
| Custom HTTP| `headers`           | JSON array of {key,value}      |
| Custom HTTP| `body_type`         | binary/multipart/base64json    |

## Settings UI Panel (Eto.Forms)

### Layout

```
┌─────────────────────────────────────────────────────┐
│  Cloud Upload Settings                               │
│                                                     │
│  ☑ Enable automatic cloud upload after scanning     │
│                                                     │
│  Provider: [Google Drive        ▼]                   │
│                                                     │
│  ┌─────────────────────────────────────────────────┐│
│  │  Status: Not authenticated                      ││
│  │  [Authenticate with Google Drive]               ││
│  └─────────────────────────────────────────────────┘│
│                                                     │
│  Target Folder: [NAPS2 Scans          ] 🗀           │
│                                                     │
│  Filename Template: [scan-{date}-{time}]            │
│                                                     │
│  After upload: [Copy link to clipboard  ▼]          │
│                                                     │
│  [Test Upload]                                      │
└─────────────────────────────────────────────────────┘
```

### Settings Location

Add "Cloud Upload" as a new tab in the existing Settings dialog.

**File to examine for pattern:** `NAPS2.Lib/EtoForms/Settings/SettingsDialog.cs`

The settings dialog uses a TabControl with panels like:
- `GeneralSettingsPanel`
- `ScanSettingsPanel`
- `SaveSettingsPanel`
- `EmailSettingsPanel` (reference for CloudUpload)
- `AdvancedSettingsPanel`
- `NotificationsSettingsPanel`

Add: `CloudUploadSettingsPanel`

## Button Integration

### 1. Main Toolbar - "Scan & Upload" Button

In `DesktopScanController.cs` or `DesktopController.cs`:

```csharp
// Existing: Scan button calls ScanDefault()
// New: Scan & Upload button calls ScanDefault(upload: true)

public void ScanDefault(bool uploadToCloud = false)
{
    // ... existing scan logic ...

    if (uploadToCloud)
    {
        var cloudSettings = _config.Get(c => c.CloudUploadSettings);
        if (cloudSettings.Enabled)
        {
            // After scanning completes, trigger upload
            _cloudController.UploadAsync(lastSavedPath, ...);
        }
    }
}
```

### 2. Context Menu - "Upload to Cloud"

In `ImageListActions.cs`:

```csharp
public bool UploadVisible => _config.Get(c => c.CloudUploadSettings.Enabled);
public bool UploadEnabled => _imageList.SelectedImages.Any();

public void Upload()
{
    var images = _imageList.SelectedImages.ToList();
    var op = _operationFactory.Create<SaveAndUploadOperation>();
    op.Start(images, ...);
}
```

### 3. Save Dialog Integration

In the save dialog, add a checkbox or dropdown:
```
Save As: [scan-2025-01-15.pdf        ] [Browse...]
Format: [PDF (.pdf) ▼]
☑ Also upload to [Google Drive ▼]
```

## Notification After Upload

### Success Notification

Show using existing notification system:

**File:** `NAPS2.Lib/EtoForms/Desktop/DesktopController.cs`

```csharp
private void OnUploadComplete(CloudUploadResult result)
{
    if (result.Success && result.RemoteUrl != null)
    {
        _notificationManager.ShowNotification(
            "Upload Complete",
            $"File uploaded to {result.ProviderName}",
            NotificationAction.Create("Open Link", () => OpenUrl(result.RemoteUrl)),
            NotificationAction.Create("Copy Link", () => CopyToClipboard(result.RemoteUrl))
        );
    }
}
```
