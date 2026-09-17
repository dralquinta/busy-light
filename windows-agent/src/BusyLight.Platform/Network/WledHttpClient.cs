using System.Net.Http;
using System.Text;
using BusyLight.Core.Network;

namespace BusyLight.Platform.Network;

/// <summary>HTTP transport for WLED's JSON API. HTTP responses are never retried.</summary>
public sealed class WledHttpClient(HttpClient client, WledHttpClientOptions options) : IWledHttpClient, IDisposable
{
    public async Task<bool> SendStateAsync(WledDevice device, WledStateRequest request, CancellationToken cancellationToken = default)
    {
        return await SendAsync(() => new HttpRequestMessage(HttpMethod.Post, BuildUri(device, "json/state"))
        {
            Content = new StringContent(request.ToJson(), Encoding.UTF8, "application/json"),
        }, cancellationToken).ConfigureAwait(false);
    }

    public async Task<bool> IsHealthyAsync(WledDevice device, CancellationToken cancellationToken = default)
    {
        return await SendAsync(() => new HttpRequestMessage(HttpMethod.Get, BuildUri(device, "json/info")), cancellationToken).ConfigureAwait(false);
    }

    private async Task<bool> SendAsync(Func<HttpRequestMessage> createMessage, CancellationToken cancellationToken)
    {
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        linked.CancelAfter(options.Timeout);
        for (var attempt = 1; attempt <= options.MaxAttempts; attempt++)
        {
            try
            {
                using var message = createMessage();
                using var response = await client.SendAsync(message, linked.Token).ConfigureAwait(false);
                return response.IsSuccessStatusCode;
            }
            catch (HttpRequestException) when (attempt < options.MaxAttempts)
            {
                await Task.Delay(TimeSpan.FromMilliseconds(100 * (1 << (attempt - 1))), linked.Token).ConfigureAwait(false);
            }
            catch (HttpRequestException) { return false; }
            catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested) { return false; }
        }
        return false;
    }

    private static Uri BuildUri(WledDevice device, string path) =>
        new($"http://{device.Address}:{device.Port}/{path}", UriKind.Absolute);

    public void Dispose() => client.Dispose();
}
