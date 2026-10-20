using System.Diagnostics;
using Microsoft.Data.SqlClient;
using WardGeneral.Data;

if (args.Length is < 2 or > 4)
{
    Console.Error.WriteLine("Usage: RetryProbe <server> <database> [interval-ms] [duration-seconds]");
    return 2;
}

var server = args[0];
var database = args[1];
var interval = TimeSpan.FromMilliseconds(args.Length >= 3 ? ParsePositive(args[2], "interval-ms") : 1000);
var duration = TimeSpan.FromSeconds(args.Length == 4 ? ParsePositive(args[3], "duration-seconds") : 120);
var deadline = DateTimeOffset.UtcNow + duration;
// A success without retries that takes this long is reported as DELAYED (the book's "delayed success").
const double DelayedThresholdMs = 1000;
var measurementStarted = false;
var requestCount = 0;
var successCount = 0;
var recoveredCount = 0;
var delayedCount = 0;
var failureCount = 0;
var retryCount = 0;
var normalLatencies = new List<double>();
var maxLatencyMs = 0.0;

var builder = new SqlConnectionStringBuilder
{
    DataSource = server,
    InitialCatalog = database,
    Encrypt = SqlConnectionEncryptOption.Mandatory,
    TrustServerCertificate = false,
    Authentication = SqlAuthenticationMethod.ActiveDirectoryDefault,
    ConnectTimeout = 30,
    ApplicationName = "wardgeneral-failover-probe",
    ApplicationIntent = ApplicationIntent.ReadWrite
};

using var cancellation = new CancellationTokenSource();
Console.CancelKeyPress += (_, eventArgs) =>
{
    eventArgs.Cancel = true;
    cancellation.Cancel();
};

Console.WriteLine($"Target={database} @ {server}");
Console.WriteLine($"IntervalMs={interval.TotalMilliseconds:N0}");
Console.WriteLine($"DurationSeconds={duration.TotalSeconds:N0}");
Console.WriteLine("Press Ctrl+C to stop early.");
Console.WriteLine();

while (!cancellation.IsCancellationRequested && DateTimeOffset.UtcNow < deadline)
{
    requestCount++;
    var operationRetries = 0;
    var stopwatch = Stopwatch.StartNew();

    try
    {
        await using var connection = new SqlConnection(builder.ConnectionString);
        var connectionProvider = RetryPolicy.CreateConnectionProvider();
        connectionProvider.Retrying += OnRetry;
        connection.RetryLogicProvider = connectionProvider;
        await connection.OpenAsync(cancellation.Token);

        const string sql = "SELECT SYSUTCDATETIME() AS ServerUtc, @@SPID AS SessionId;";
        await using var command = new SqlCommand(sql, connection);
        var commandProvider = RetryPolicy.CreateReadOnlyCommandProvider();
        commandProvider.Retrying += OnRetry;
        command.RetryLogicProvider = commandProvider;

        await using var reader = await command.ExecuteReaderAsync(cancellation.Token);
        if (!await reader.ReadAsync(cancellation.Token))
            throw new InvalidOperationException("The probe query returned no row.");

        var serverUtc = DateTime.SpecifyKind(reader.GetDateTime(0), DateTimeKind.Utc);
        var sessionId = reader.GetInt16(1);
        stopwatch.Stop();
        successCount++;

        var elapsedMs = stopwatch.Elapsed.TotalMilliseconds;
        maxLatencyMs = Math.Max(maxLatencyMs, elapsedMs);
        string state;
        if (operationRetries > 0) { state = "RECOVERED"; recoveredCount++; }
        else if (elapsedMs >= DelayedThresholdMs) { state = "DELAYED"; delayedCount++; }
        else { state = "OK"; normalLatencies.Add(elapsedMs); }
        Console.WriteLine(
            $"{DateTimeOffset.UtcNow:O} {state,-9} {elapsedMs,8:N0} ms " +
            $"retries={operationRetries} session={sessionId} serverUtc={serverUtc:O}");

        if (!measurementStarted)
        {
            measurementStarted = true;
            deadline = DateTimeOffset.UtcNow + duration;
            Console.WriteLine($"MeasurementEndsUtc={deadline:O}");
        }
    }
    catch (OperationCanceledException) when (cancellation.IsCancellationRequested)
    {
        break;
    }
    catch (Exception exception)
    {
        stopwatch.Stop();
        failureCount++;
        Console.WriteLine(
            $"{DateTimeOffset.UtcNow:O} FAILED    {stopwatch.Elapsed.TotalMilliseconds,8:N0} ms " +
            $"retries={operationRetries} error={Describe(exception)}");
    }

    var remaining = deadline - DateTimeOffset.UtcNow;
    if (remaining <= TimeSpan.Zero) break;

    try
    {
        await Task.Delay(remaining < interval ? remaining : interval, cancellation.Token);
    }
    catch (OperationCanceledException)
    {
        break;
    }

    void OnRetry(object? _, SqlRetryingEventArgs eventArgs)
    {
        operationRetries++;
        retryCount++;
        var lastException = eventArgs.Exceptions.Count > 0 ? eventArgs.Exceptions[^1] : null;
        Console.WriteLine(
            $"{DateTimeOffset.UtcNow:O} RETRY     attempt={eventArgs.RetryCount} " +
            $"delayMs={eventArgs.Delay.TotalMilliseconds:N0} error={Describe(lastException)}");
    }
}

Console.WriteLine();
Console.WriteLine("--- Probe summary ---");
Console.WriteLine($"Requests={requestCount}");
Console.WriteLine($"Succeeded={successCount}");
Console.WriteLine($"DelayedSuccess={delayedCount}");
Console.WriteLine($"RecoveredAfterRetry={recoveredCount}");
Console.WriteLine($"FailedAfterRetries={failureCount}");
Console.WriteLine($"RetryEvents={retryCount}");
Console.WriteLine($"DelayedThresholdMs={DelayedThresholdMs:0}");
if (normalLatencies.Count > 0)
{
    normalLatencies.Sort();
    Console.WriteLine($"NormalLatencyMedianMs={Percentile(normalLatencies, 50):0.0}");
    Console.WriteLine($"NormalLatencyAverageMs={normalLatencies.Average():0.0}");
    Console.WriteLine($"NormalLatencyP95Ms={Percentile(normalLatencies, 95):0.0}");
}
if (successCount > 0)
    Console.WriteLine($"MaxSuccessLatencyMs={maxLatencyMs:0}");
return failureCount == 0 ? 0 : 1;

// Nearest-rank percentile over an already sorted list.
static double Percentile(List<double> sorted, int percentile)
{
    var rank = (int)Math.Ceiling(percentile / 100.0 * sorted.Count);
    return sorted[Math.Clamp(rank - 1, 0, sorted.Count - 1)];
}

static int ParsePositive(string value, string name)
{
    if (!int.TryParse(value, out var result) || result <= 0)
        throw new ArgumentException($"{name} must be a positive integer.");
    return result;
}

static string Describe(Exception? exception) => exception switch
{
    SqlException sqlException => $"SqlException {sqlException.Number}: {OneLine(sqlException.Message)}",
    null => "unknown",
    _ => $"{exception.GetType().Name}: {OneLine(exception.Message)}"
};

static string OneLine(string value) => value.Replace('\r', ' ').Replace('\n', ' ').Trim();
