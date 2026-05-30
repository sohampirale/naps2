# Reference Code Patterns

This document provides exact code examples from NAPS2 that you can follow when implementing the cloud upload feature.

## 1. IEmailProvider Interface (Model for ICloudUploadProvider)

**File:** `NAPS2.Sdk/ImportExport/Email/IEmailProvider.cs`

```csharp
// This is the EXACT pattern to follow for ICloudUploadProvider
public interface IEmailProvider
{
    string Name { get; }
    bool ShowInList { get; }
    Icon? Icon { get; }
    bool CanSelectInList { get; }
    bool IsAuthenticated { get; }
    Task SendEmail(EmailParams emailParams, ProgressHandler progress, CancellationToken cancelToken);
    Task Authenticate();
}
```

**Your ICloudUploadProvider should look like:**

```csharp
public interface ICloudUploadProvider
{
    string Name { get; }
    bool ShowInList { get; }
    string Description { get; }
    Icon? Icon { get; }
    bool IsAuthenticated { get; }
    bool CanUploadInBackground { get; }
    Task<CloudUploadResult> UploadAsync(
        Stream fileStream,
        string fileName,
        CloudUploadParams uploadParams,
        ProgressHandler progress,
        CancellationToken cancelToken);
    Task AuthenticateAsync();
    Task DeauthorizeAsync();
}
```

## 2. IEmailProviderFactory (Model for ICloudUploadProviderFactory)

**File:** `NAPS2.Lib/ImportExport/Email/IEmailProviderFactory.cs`

```csharp
public interface IEmailProviderFactory
{
    IEmailProvider Create(EmailProviderType type);
    EmailProviderType Default { get; }
    IReadOnlyDictionary<EmailProviderType, IEmailProvider> RegisteredProviders { get; }
}
```

## 3. AutofacEmailProviderFactory (Model for CloudUploadProvider Factory)

**File:** `NAPS2.Lib/ImportExport/Email/AutofacEmailProviderFactory.cs`

```csharp
public class AutofacEmailProviderFactory : IEmailProviderFactory
{
    private readonly ILifetimeScope _scope;

    public AutofacEmailProviderFactory(ILifetimeScope scope)
    {
        _scope = scope;
    }

    public IEmailProvider Create(EmailProviderType type)
    {
        return _scope.ResolveKeyed<IEmailProvider>(type);
    }

    public EmailProviderType Default { get; set; }

    public IReadOnlyDictionary<EmailProviderType, IEmailProvider> RegisteredProviders
        => _scope.Resolve<IEnumerable<KeyValuePair<EmailProviderType, IEmailProvider>>>()
            .ToDictionary(x => x.Key, x => x.Value);
}
```

## 4. OauthProvider Base Class (Reusable)

**File:** `NAPS2.Lib/ImportExport/Email/Oauth/OauthProvider.cs`

This is the most important reusable component. Key methods:

```csharp
public abstract class OauthProvider
{
    // Override these in your cloud provider:
    protected abstract string ClientId { get; }
    protected abstract string Scope { get; }
    protected abstract string TokenEndpoint { get; }
    protected abstract string AuthEndpoint { get; }
    protected virtual string? ClientSecret => null;
    protected virtual string RedirectUri => $"http://127.0.0.1:{RedirectPort}/";
    protected virtual int RedirectPort => 49873;
    protected virtual bool UsePkce => true;

    // These methods are READY TO USE from the base class:
    protected async Task<string?> GetAccessToken();
    protected async Task<string> PostAuthorized(string url, HttpContent content);
    protected async Task<string> Post(string url, HttpContent content);
    protected async Task<string> Get(string url);
    protected async Task<T> Get<T>(string url);
    protected void InvalidateToken();
}
```

**Example: GmailOauthProvider**

**File:** `NAPS2.Lib/ImportExport/Email/Oauth/GmailOauthProvider.cs`

```csharp
public class GmailOauthProvider : OauthProvider
{
    protected override string ClientId => GmailEmailProvider.GmailClientId;
    protected override string Scope => "https://mail.google.com/";
    protected override string TokenEndpoint => "https://oauth2.googleapis.com/token";
    protected override string AuthEndpoint => "https://accounts.google.com/o/oauth2/v2/auth";
    protected override int RedirectPort => 49872;
}
```

## 5. GmailEmailProvider (Model for Upload Provider with OAuth)

**File:** `NAPS2.Lib/ImportExport/Email/Gmail/GmailEmailProvider.cs`

This is the best reference for implementing a cloud upload provider because it:
1. Uses OAuth2 for auth
2. Uploads attachments via HTTP multipart
3. Reports progress
4. Handles errors

```csharp
public class GmailEmailProvider : IEmailProvider
{
    private readonly GmailOauthProvider _oauth;

    public GmailEmailProvider(GmailOauthProvider oauth)
    {
        _oauth = oauth;
    }

    public bool IsAuthenticated => _oauth.IsAuthenticated;

    public async Task SendEmail(EmailParams emailParams, ProgressHandler progress,
        CancellationToken cancelToken)
    {
        // 1. Build multipart MIME message
        // 2. Encode as base64 URL-safe
        // 3. Upload via Gmail API:
        //    POST https://gmail.googleapis.com/gmail/v1/users/me/messages/send
        //    with body: { "raw": "<base64-encoded-mime>" }
    }

    public async Task Authenticate()
    {
        await _oauth.GetAccessToken();
    }
}
```

## 6. PdfExporter Stream Export

**File:** `NAPS2.Sdk/Pdf/PdfExporter.cs`

```csharp
// There is a private method that exports to MemoryStream:
private byte[] SaveDocument(PdfDocument document, PdfExportParams pdfExportParams)
{
    using var ms = new MemoryStream();
    // ... writes PDF to ms
    return ms.ToArray();
}

// Public export to file:
public void Export(string path, IEnumerable<ProcessedImage> images,
    PdfExportParams pdfExportParams, OcrParams ocrParams,
    ProgressHandler progress)
{
    // Internally generates to MemoryStream then writes to path
}
```

For cloud upload, you want to get the byte array/stream BEFORE it's written to disk, or after. Either way works.

## 7. IOperation Interface

**File:** `NAPS2.Lib/Operation/IOperation.cs`

```csharp
public interface IOperation
{
    string ProgressTitle { get; }
    bool AllowCancel { get; }
    bool AllowBackground { get; }
    OperationStatus Status { get; }
    OperationError? Error { get; }
    Task<bool> Success { get; }
    Exception? Exception { get; }
    void Cancel();
    Task Wait();
    event EventHandler<OperationStatus> StatusChanged;
    event EventHandler<OperationError> ErrorOccurred;
}
```

## 8. SavePdfOperation (Model for SaveAndUploadOperation)

**File:** `NAPS2.Lib/Pdf/SavePdfOperation.cs`

```csharp
public class SavePdfOperation : OperationBase
{
    private readonly ISavePdfOperation _operation;

    public SavePdfOperation(ISavePdfOperation operation)
    {
        _operation = operation;
    }

    public void Start(string saveLocation, PdfSettings pdfSettings,
        IList<ProcessedImage> Images, bool isPreview)
    {
        // ... wraps PdfExporter.Export with progress/cancellation
    }
}
```

## 9. Autofac Module Registration

**File:** `NAPS2.Lib/Modules/EmailModule.cs`

```csharp
public class EmailModule : Module
{
    protected override void Load(ContainerBuilder builder)
    {
        // Register OAuth providers
        builder.RegisterType<GmailOauthProvider>().SingleInstance();
        builder.RegisterType<OutlookWebOauthProvider>().SingleInstance();

        // Register email providers keyed by type
        builder.RegisterType<GmailEmailProvider>()
            .Keyed<IEmailProvider>(EmailProviderType.Gmail)
            .SingleInstance();
        builder.RegisterType<OutlookWebEmailProvider>()
            .Keyed<IEmailProvider>(EmailProviderType.OutlookWeb)
            .SingleInstance();

        // Register factory
        builder.RegisterType<AutofacEmailProviderFactory>()
            .As<IEmailProviderFactory>()
            .SingleInstance();
    }
}
```

## 10. ProgressHandler Usage

**File:** `NAPS2.Sdk/Util/ProgressHandler.cs`

```csharp
// ProgressHandler is a delegate-based progress reporter
public delegate void ProgressHandler(double progress, string message);

// Usage:
ProgressHandler progress = (pct, msg) =>
{
    // Update UI
};

// In upload provider:
progress?.Invoke(0.5, "Uploading... 50%");
```

## 11. WebClientExtensions (Upload Progress)

**File:** `NAPS2.Sdk/Util/WebClientExtensions.cs`

```csharp
// Extension method for tracking upload progress
public static class WebClientExtensions
{
    public static Task<string> UploadStringTaskAsync(
        this WebClient webClient, string address, string data,
        ProgressHandler progress);
}
```

## Summary of Patterns to Follow

| Your Component | Reference Component | File |
|---------------|-------------------|------|
| `ICloudUploadProvider` | `IEmailProvider` | `NAPS2.Sdk/ImportExport/Email/IEmailProvider.cs` |
| `ICloudUploadProviderFactory` | `IEmailProviderFactory` | `NAPS2.Lib/ImportExport/Email/IEmailProviderFactory.cs` |
| `AutofacCloudUploadProviderFactory` | `AutofacEmailProviderFactory` | `NAPS2.Lib/ImportExport/Email/AutofacEmailProviderFactory.cs` |
| `GoogleDriveCloudProvider` | `GmailEmailProvider` | `NAPS2.Lib/ImportExport/Email/Gmail/GmailEmailProvider.cs` |
| `CloudUploadModule` | `EmailModule` | `NAPS2.Lib/Modules/EmailModule.cs` |
| `SaveAndUploadOperation` | `SavePdfOperation` | `NAPS2.Lib/Pdf/SavePdfOperation.cs` |
| OAuth2 for cloud providers | `GmailOauthProvider` | `NAPS2.Lib/ImportExport/Email/Oauth/GmailOauthProvider.cs` |
