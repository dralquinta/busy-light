using System.Net;
using System.Net.Http;
using BusyLight.Core.Network;
using BusyLight.Platform.Network;
using Xunit;

namespace BusyLight.Platform.Tests.Network;

public sealed class WledHttpClientTests
{
    [Fact]
    public async Task SendStateAsyncDoesNotRetryHttpFailureResponses()
    {
        var handler = new CountingHandler(_ => new HttpResponseMessage(HttpStatusCode.BadRequest));
        using var client = new WledHttpClient(new HttpClient(handler), WledHttpClientOptions.Create(TimeSpan.FromSeconds(3)));

        var sent = await client.SendStateAsync(new WledDevice("mac", "192.168.1.2"), WledStateRequest.ForPreset(1));

        Assert.False(sent);
        Assert.Equal(1, handler.CallCount);
    }

    private sealed class CountingHandler(Func<HttpRequestMessage, HttpResponseMessage> responseFactory) : HttpMessageHandler
    {
        public int CallCount { get; private set; }
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            CallCount++;
            return Task.FromResult(responseFactory(request));
        }
    }
}
