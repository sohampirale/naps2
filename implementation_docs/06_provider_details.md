# Cloud Provider Implementation Details

This document details the technical implementation of each cloud upload provider.

---

## 1. WebDAV Provider (Simplest / Best for Testing)

### When to Use
- User has a self-hosted WebDAV server (Nextcloud, ownCloud, Synology, etc.)
- Simplest to implement, no OAuth2
- Good for testing your infrastructure end-to-end

### API Details
```
PUT /{basePath}/{filename}
Headers:
    Authorization: Basic {base64(username:password)}
    Content-Type: application/pdf
Body: binary file bytes

Success: 201 Created
Response: (empty body or XML)
```

### Implementation

```csharp
public class WebDavCloudProvider : ICloudUploadProvider
{
    private readonly HttpClient _httpClient;

    public string Name => "WebDAV";
    public bool ShowInList => true;
    public bool IsAuthenticated => !string.IsNullOrEmpty(_password);
    public bool CanUploadInBackground => true;

    // Settings (stored in NAPS2 config):
    // - ServerUrl: string (e.g., "https://nextcloud.example.com/remote.php/dav/files/user/")
    // - Username: string
    // - Password: string (stored in OS keychain, not plaintext)
    // - TargetPath: string (e.g., "Scans/")

    public async Task<CloudUploadResult> UploadAsync(
        Stream fileStream, string fileName, CloudUploadParams uploadParams,
        ProgressHandler progress, CancellationToken ct)
    {
        var url = $"{_serverUrl.TrimEnd('/')}/{uploadParams.TargetPath.Trim('/')}/{fileName}";

        var request = new HttpRequestMessage(HttpMethod.Put, url);
        request.Content = new ProgressStreamContent(fileStream, progress, ct);
        request.Headers.Authorization = new AuthenticationHeaderValue(
            "Basic", Convert.ToBase64String(Encoding.ASCII.GetBytes($"{_username}:{_password}")));

        var response = await _httpClient.SendAsync(request, ct);
        response.EnsureSuccessStatusCode();

        return CloudUploadResult.Success();
    }
}
```

---

## 2. Google Drive Provider

### OAuth2 Setup
1. Go to https://console.cloud.google.com/apis/credentials
2. Create OAuth 2.0 Client ID (Desktop application type)
3. Add redirect URI: `http://127.0.0.1:49874/`
4. Enable Google Drive API

### Scopes
```
https://www.googleapis.com/auth/drive.file
```
(Per-file access - only sees files created by the app)

### API Endpoints

**Upload:**
```
POST https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart
Authorization: Bearer {token}
Content-Type: multipart/related; boundary=foo

--foo
Content-Type: application/json; charset=UTF-8

{
  "name": "scan-2025-01-15.pdf",
  "parents": ["{folderId}"]
}

--foo
Content-Type: application/pdf

{binary file data}
--foo--
```

**Get shareable link:**
```
POST https://www.googleapis.com/drive/v3/files/{fileId}/permissions
Authorization: Bearer {token}
Content-Type: application/json

{
  "role": "reader",
  "type": "anyone"
}

Then:
GET https://www.googleapis.com/drive/v3/files/{fileId}?fields=webViewLink
```

### Implementation Notes
- Maximum upload size: 5 TB (essentially unlimited for scans)
- Use resumable upload for files > 5 MB:
  ```
  POST https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable
  ```
- Rate limit: 10 queries per second per user

---

## 3. Dropbox Provider

### OAuth2 Setup
1. Go to https://www.dropbox.com/developers/apps
2. Create app with "Full Dropbox" or "App folder" access
3. Set redirect URI: `http://127.0.0.1:49875/`

### Scopes
```
files.content.write
sharing.write
account_info.read
```

### API Endpoints

**Upload:**
```
POST https://content.dropboxapi.com/2/files/upload
Authorization: Bearer {token}
Dropbox-API-Arg: {
  "path": "/Scans/scan-2025-01-15.pdf",
  "mode": "add",
  "autorename": true,
  "mute": false
}
Content-Type: application/octet-stream

{binary file data}

Success: 200 OK
Response:
{
  "name": "scan-2025-01-15.pdf",
  "path_lower": "/scans/scan-2025-01-15.pdf",
  "id": "id:abc123"
}
```

**Get shareable link:**
```
POST https://api.dropboxapi.com/2/sharing/create_shared_link_with_settings
Authorization: Bearer {token}
Content-Type: application/json

{
  "path": "/Scans/scan-2025-01-15.pdf",
  "settings": {
    "access": "viewer",
    "allow_download": true
  }
}

Response:
{
  "url": "https://www.dropbox.com/s/abc123/scan.pdf?dl=0"
}
```

### Implementation Notes
- Maximum upload size: 350 GB
- Use `Dropbox-API-Arg` header, not query params
- Progress: use content-length vs bytes-sent
- `mode: "add"` with `autorename: true` handles filename collisions

---

## 4. OneDrive Provider

### OAuth2 Setup
1. Go to https://portal.azure.com -> App registrations
2. Create app with "Mobile and desktop applications" platform
3. Redirect URI: `http://127.0.0.1:49876/`
4. API permissions: `Files.ReadWrite`

### Scopes
```
Files.ReadWrite
offline_access
```

### API Endpoint

**Upload:**
```
PUT https://graph.microsoft.com/v1.0/me/drive/root:/Scans/scan-2025-01-15.pdf:/content
Authorization: Bearer {token}
Content-Type: application/pdf

{binary file data}

Success: 201 Created
Response:
{
  "id": "FILE_ID",
  "name": "scan-2025-01-15.pdf",
  "webUrl": "https://onedrive.live.com/...",
  "@content.downloadUrl": "https://..."
}
```

### Implementation Notes
- Maximum upload size: 4 GB (use upload session for > 4 MB)
- Upload session: `POST /me/drive/root:/Scans/scan.pdf:/createUploadSession`
- Rate limit: 10,000 requests per 10 minutes per app

---

## 5. Custom HTTP Endpoint Provider

### When to Use
- User has their own server/API
- Want to integrate with S3, Backblaze B2, etc.
- Need to trigger a webhook after scanning

### Implementation

Settings stored in NAPS2 config:
```
- Method: PUT | POST
- URL: string (supports variables)
- Headers: [{key, value}, ...]
- BodyType: Binary | Multipart | Base64Json
- SuccessCodes: [200, 201, 202, 204]
- SuccessBodyContains: string (optional)
```

### URL Variables
```
{filename}        - "scan-2025-01-15.pdf"
{filenameNoExt}   - "scan-2025-01-15"
{extension}       - "pdf"
{date}            - "2025-01-15"
{time}            - "143022"
{timestamp}       - "1736951422"
{year}            - "2025"
{month}           - "01"
{day}             - "15"
{pageCount}       - "5"
{fileSize}        - "1234567"
{guid}            - "a1b2c3d4-..."
```

### Example Configuration

**S3-compatible storage:**
```
Method: PUT
URL: https://s3.us-east-1.amazonaws.com/mybucket/scans/{filename}
Headers:
  Authorization: AWS {accessKey}:{signature}
  x-amz-acl: private
  Content-Type: application/pdf
```

**Custom webhook:**
```
Method: POST
URL: https://api.example.com/scans
Headers:
  X-API-Key: sk-abc123
  Content-Type: multipart/form-data
Body: Multipart (file as form field "file")
```

**Base64 JSON API:**
```
Method: POST
URL: https://api.example.com/documents
Headers:
  Authorization: Bearer token
  Content-Type: application/json
Body: {"filename": "{filename}", "content": "{base64}", "pages": {pageCount}}
```
