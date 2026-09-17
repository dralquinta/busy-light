using System.Text.Json;

namespace BusyLight.Core.Network;

public readonly record struct WledStateRequest(int Preset, bool V = true)
{
    public static WledStateRequest ForPreset(int preset) => preset is >= 1 and <= 250 ? new(preset) : throw new ArgumentOutOfRangeException(nameof(preset));
    public string ToJson() => JsonSerializer.Serialize(new { ps = Preset, v = V });
}
public sealed record WledStateSendResult(string State, int DeliveredCount, int TotalCount);
public sealed record WledDevice(string Mac, string Address, string? Name = null, int Port = 80, int? LastPresetSent = null);
public interface IWledHttpClient { Task<bool> SendStateAsync(WledDevice device, WledStateRequest request, CancellationToken cancellationToken = default); Task<bool> IsHealthyAsync(WledDevice device, CancellationToken cancellationToken = default); }
