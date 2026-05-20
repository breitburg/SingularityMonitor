# Privacy Policy

**App:** Singularity
**Developer:** Ilia Breitburg
**Contact:** ilya.breytburg@gmail.com
**Effective:** 21 May 2026

Singularity is designed to work without collecting any personal data. This policy describes, plainly, what the app does and does not do.

## Data the app collects

**None.**

Singularity does not collect, transmit, sell, share, or store any personal data about you. There is no account, no sign-in, no analytics SDK, no advertising SDK, no crash reporter, and no tracker of any kind.

## Network activity

The app makes exactly one type of network request: it downloads a public benchmark file from METR at the following URL.

`https://metr.org/assets/benchmark_results_1_1.yaml`

This request is sent to METR's servers each time the app refreshes the benchmark. The request contains only the standard information that any HTTPS client sends (such as your IP address and a generic user-agent string); the app does not attach any identifier of you, your device, or your usage of the app.

METR is an independent third party. Their handling of incoming requests is governed by their own policies, which the developer of Singularity does not control. Please consult [metr.org](https://metr.org) for their terms.

## Data stored on your device

The app stores the following data locally on your device, inside the app's own sandbox and a shared App Group container used by the Singularity widget:

- The most recent copy of the public METR benchmark file, cached so the app and widget can display the latest known data without re-fetching every time.
- Your in-app preferences: the success-rate metric (50% or 80%) and the curve fit you have selected.

This data never leaves your device. It is removed when you delete the app.

## Children

The app is not directed at children and does not knowingly collect information from anyone.

## Third-party services

Singularity does not embed any third-party analytics, advertising, attribution, or tracking services.

The only third-party server the app contacts is `metr.org`, solely to download the public benchmark file described above.

## Your rights

Because the app does not collect, store, or transmit personal data, there is nothing for the developer to access, correct, export, or delete on your behalf. Uninstalling the app removes all locally cached data.

## Changes to this policy

If this policy changes, the updated version will be published at the same URL where you found this document, with an updated effective date. Material changes will be reflected in a subsequent app update.

## Contact

Questions about this policy may be sent to ilya.breytburg@gmail.com.
