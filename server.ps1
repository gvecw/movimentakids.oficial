param(
    [int]$Port = 8080
)

$csharpCode = @"
using System;
using System.IO;
using System.Net;
using System.Threading;
using System.Collections.Generic;

public class SimpleStaticServer {
    private HttpListener _listener;
    private string _rootPath;
    private volatile bool _running;
    private static readonly Dictionary<string, string> MimeTypes = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase) {
        { ".html", "text/html; charset=utf-8" },
        { ".htm", "text/html; charset=utf-8" },
        { ".css", "text/css; charset=utf-8" },
        { ".js", "application/javascript; charset=utf-8" },
        { ".json", "application/json; charset=utf-8" },
        { ".png", "image/png" },
        { ".jpg", "image/jpeg" },
        { ".jpeg", "image/jpeg" },
        { ".webp", "image/webp" },
        { ".svg", "image/svg+xml" },
        { ".ico", "image/x-icon" },
        { ".mp4", "video/mp4" },
        { ".woff", "font/woff" },
        { ".woff2", "font/woff2" },
        { ".ttf", "font/ttf" }
    };

    public SimpleStaticServer(string rootPath, int port) {
        _rootPath = Path.GetFullPath(rootPath);
        _listener = new HttpListener();
        _listener.Prefixes.Add("http://localhost:" + port + "/");
    }

    public void Start() {
        _listener.Start();
        _running = true;
        _listener.BeginGetContext(OnContextReceived, null);
    }

    public void Stop() {
        _running = false;
        try { _listener.Stop(); } catch {}
        try { _listener.Close(); } catch {}
    }

    private void OnContextReceived(IAsyncResult ar) {
        if (!_running) return;
        try {
            var ctx = _listener.EndGetContext(ar);
            _listener.BeginGetContext(OnContextReceived, null);
            ThreadPool.QueueUserWorkItem(_ => ProcessRequest(ctx));
        } catch {
            if (_running) {
                try { _listener.BeginGetContext(OnContextReceived, null); } catch {}
            }
        }
    }

    private void ProcessRequest(HttpListenerContext ctx) {
        var req = ctx.Request;
        var res = ctx.Response;
        try {
            string raw = Uri.UnescapeDataString(req.Url.AbsolutePath);
            if (string.IsNullOrEmpty(raw) || raw == "/") raw = "/index.html";
            string rel = raw.TrimStart('/').Replace('/', Path.DirectorySeparatorChar);
            string fullPath = Path.Combine(_rootPath, rel);

            if (!File.Exists(fullPath)) {
                res.StatusCode = 404;
                res.ContentType = "text/plain; charset=utf-8";
                byte[] b = System.Text.Encoding.UTF8.GetBytes("404 Not Found");
                res.ContentLength64 = b.Length;
                res.OutputStream.Write(b, 0, b.Length);
                return;
            }

            string ext = Path.GetExtension(fullPath);
            string mime;
            if (!MimeTypes.TryGetValue(ext, out mime)) mime = "application/octet-stream";

            res.ContentType = mime;
            res.Headers["Accept-Ranges"] = "bytes";
            res.Headers["Access-Control-Allow-Origin"] = "*";

            long fileLen = new FileInfo(fullPath).Length;
            string rangeHeader = req.Headers["Range"];

            if (!string.IsNullOrEmpty(rangeHeader) && rangeHeader.StartsWith("bytes=")) {
                string[] parts = rangeHeader.Substring(6).Split('-');
                long start = 0;
                long end = fileLen - 1;
                if (!string.IsNullOrEmpty(parts[0])) long.TryParse(parts[0], out start);
                if (parts.Length > 1 && !string.IsNullOrEmpty(parts[1])) long.TryParse(parts[1], out end);

                if (start > end || start >= fileLen) {
                    res.StatusCode = 416;
                    res.Headers["Content-Range"] = "bytes */" + fileLen;
                    return;
                }

                long len = end - start + 1;
                res.StatusCode = 206;
                res.Headers["Content-Range"] = string.Format("bytes {0}-{1}/{2}", start, end, fileLen);
                res.ContentLength64 = len;

                using (var fs = new FileStream(fullPath, FileMode.Open, FileAccess.Read, FileShare.Read)) {
                    fs.Seek(start, SeekOrigin.Begin);
                    byte[] buf = new byte[65536];
                    long remaining = len;
                    while (remaining > 0) {
                        int toRead = (int)Math.Min(buf.Length, remaining);
                        int read = fs.Read(buf, 0, toRead);
                        if (read <= 0) break;
                        res.OutputStream.Write(buf, 0, read);
                        remaining -= read;
                    }
                }
            } else {
                res.StatusCode = 200;
                res.ContentLength64 = fileLen;
                if (req.HttpMethod != "HEAD") {
                    using (var fs = new FileStream(fullPath, FileMode.Open, FileAccess.Read, FileShare.Read)) {
                        fs.CopyTo(res.OutputStream);
                    }
                }
            }
        } catch {
        } finally {
            try { res.Close(); } catch {}
        }
    }
}
"@

Add-Type -TypeDefinition $csharpCode

$rootPath = $PSScriptRoot
if (-not $rootPath) { $rootPath = (Get-Location).Path }

$server = New-Object SimpleStaticServer($rootPath, $Port)
$server.Start()

Write-Host "=========================================================="
Write-Host " Servidor Local Ativo: http://localhost:$Port/"
Write-Host " Pasta: $rootPath"
Write-Host " Pressione Ctrl+C para encerrar."
Write-Host "=========================================================="

try {
    while ($true) {
        Start-Sleep -Seconds 1
    }
} finally {
    $server.Stop()
}
