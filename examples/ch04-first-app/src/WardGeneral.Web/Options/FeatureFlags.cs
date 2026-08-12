namespace WardGeneral.Web.Options;

/// <summary>
/// Toggles for progressively-revealed chart features, bound from the "Features"
/// section of configuration.
///
/// Every flag defaults <b>OFF</b>. The reader turns each one on in the chapter that
/// teaches it — <b>without editing source</b>: deploy that chapter's <c>.sql</c>,
/// flip the flag, and the panel lights up. This is why the app never needs
/// per-chapter code deltas: the <i>database</i> evolves (CREATE OR ALTER), the app
/// stays put.
///
/// Chapter 4 features are <b>not</b> flags. The base chart — including the in-engine
/// <c>REGEXP_*</c> note-signal card — is simply part of the app.
///
/// The panels also self-hide when their backing SQL isn't deployed — the chart DAL
/// reads the backing columns column-tolerantly (see <c>GetOptionalJson</c>), so a
/// <c>false</c> flag and a not-yet-created view both degrade gracefully.
/// </summary>
public sealed class FeatureFlags
{
    /// <summary>AI assistance card — vector search + gpt-5 (Ch 5). Backing: <c>clinical.GenerateClinicalAssistance</c>.</summary>
    public bool AiAssistance { get; set; }

    /// <summary>In-app clinical assistant dock (Ch 6 — Microsoft Agent Framework + DAB SQL MCP). Requires DAB running + an Azure OpenAI endpoint.</summary>
    public bool Assistant { get; set; }
}
