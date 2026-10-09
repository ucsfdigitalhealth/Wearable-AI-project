# Polar BLE SDK --- Sync Implementation Flowchart Notes

> **Source:** `SyncFlowchart.svg`, from the official
> `polarofficial/polar-ble-sdk` repository.\
> **Interpretation:** This is a general Polar SDK synchronization
> guideline, not a Verity Sense-only flowchart. It describes multiple
> data categories that may be supported by different Polar devices.
> Implement only the stages and data types supported by the target
> device and needed by the application.

## 1. High-level purpose

The flowchart describes how an app should synchronize data with a
connected Polar device. The app may need to:

1.  Connect to the device.
2.  Configure or continue offline recordings.
3.  Retrieve completed recordings.
4.  Fetch other available data categories, such as daily activity,
    sleep/recovery, temperature, or training sessions.
5.  Store the retrieved data locally.
6.  Delete data from the device only when it is no longer needed.
7.  Track synchronization progress and recover from interruptions.

The diagram is a template. The app can choose the order of
synchronization stages and omit categories it does not use.

## 2. Simplified overall flow

``` text
Start sync
   |
   v
Is device connected?
   | no
   +----> Connect to device
   |
   v yes
Is device ready for sync?
   | no
   +----> Retry later
   |
   v yes
Signal sync start to device
   |
   v
Process the required data categories
   |
   +--> Offline recordings
   +--> Daily activity (if needed/supported)
   +--> Sleep/nightly recovery (if needed/supported)
   +--> Skin temperature (if needed/supported)
   +--> Training sessions (if needed/supported)
   |
   v
Signal sync stop to device
   |
   v
Did sync complete successfully?
   | yes
   +----> Finish
   |
   | no
   +----> Abort this attempt; retry/recover later
```

The exact order of the data-category stages is not mandatory. An app
should record which stage it has reached so that it can resume after a
recoverable error or disconnect.

## 3. Connection and sync lifecycle

### 3.1 Connect

-   Check whether the device is connected.
-   If it is not connected, connect before attempting synchronization.
-   The diagram notes that pairing/user intervention may be required in
    some situations.

### 3.2 Check readiness and start sync

-   Check whether the device is ready for synchronization.
-   If it is not ready, retry later rather than treating the attempt as
    successful.
-   Signal the start of synchronization to the device.

### 3.3 Track progress and recover

-   Record progress through the synchronization stages.
-   If a recoverable error occurs or the device disconnects, reconnect
    and resume from the interrupted stage if the desired sync has not
    completed.
-   Handle retries and repeated connection timeouts.
-   If recovery requires user action, inform the user with an
    appropriate platform-specific notification or message.
-   Signal the end of synchronization when the stages are complete.

## 4. Offline recordings

This is the most relevant branch for an app collecting raw sensor
recordings from a Polar Verity Sense.

### 4.1 Determine recording state

-   Check whether offline recordings have been processed for all
    required data types.
-   Determine whether a recording is currently ongoing.
-   If required by the app and the device is not already recording that
    data type, start the recording.
-   If recording configuration is needed, configure the offline
    recording first.
-   If recording should not continue, stop it as appropriate.
-   The diagram mentions offline triggers as one possible way to start
    recordings automatically (for example, in response to an
    exercise-start trigger).

### 4.2 Fetch completed recordings

-   Fetch completed recordings from the device for the required data
    type.
-   Store the retrieved recordings in the app's storage.
-   Keep track of which recordings/data types have been successfully
    fetched so interrupted synchronization can resume safely.

### 4.3 Recording data types listed in the flowchart

The generic flowchart lists these offline recording types:

-   HR --- heart rate
-   ECG --- electrocardiography
-   ACC --- accelerometer
-   PPG --- photoplethysmography
-   PPI --- pulse-to-pulse interval
-   GYRO --- gyroscope
-   MAGNETOMETER
-   PRESSURE
-   LOCATION
-   TEMPERATURE
-   SKIN TEMPERATURE

**Important:** This list is generic to the flowchart. It does not mean
every Polar device supports every type, or that all types are available
in every device mode. Confirm support, settings, and output structures
in the device-specific documentation and SDK.

### 4.4 Recording configuration

The flowchart notes that offline recordings may accept data-collection
parameters. Configure them according to the application's needs. SDK
Mode may be required for settings that are not available in normal
operating mode.

For the research app, confirm the desired data types and sampling rates
with the device-specific Verity Sense documentation and project
supervisor before finalizing configuration.

### 4.5 Delete data from the device carefully

The flowchart includes deleting past offline recordings and emphasizes
cleaning up device storage once data on the device is no longer needed.

A safe implementation should not delete a recording merely because a
fetch was attempted. First confirm that the recording has been retrieved
and stored successfully, and follow the SDK's deletion semantics.
Preserve a copy in the app's intended storage before removing the device
copy.

## 5. Other synchronization branches in the generic flowchart

These sections are included for completeness. They may not be necessary
for a Verity Sense raw-PPG/ACC research app.

### 5.1 Daily activity

The flowchart lists these daily activity values:

-   Steps
-   Distance
-   Active time
-   Calories
-   24/7 HR
-   24/7 PPI

The simplified flow is:

1.  Decide whether daily activity data is needed.
2.  Fetch today's activity data if required.
3.  Fetch historical activity for the desired date range if required.
4.  Store/update the activity data in the app.
5.  Delete old activity data from the device when it is no longer
    needed.

The flowchart notes that today's activity changes as the day progresses.
Re-fetch it only as needed to avoid unnecessary battery use. Historical
data is expected not to change, so it can be fetched once and then
removed from the device when appropriate.

### 5.2 Sleep and nightly recovery

The flowchart separates sleep and nightly-recovery data.

Sleep data may include:

-   Sleep start and stop
-   Duration
-   Sleep stages

Nightly-recovery data may include values such as:

-   ANS status/rate
-   Recovery indicator and recovery sub-level
-   Mean RRI and RMSSD
-   Mean respiration interval
-   Baseline RRI, RMSSD, and respiration-interval statistics
-   Sleep, vitality, and exercise tips
-   Date

Simplified flow:

1.  Decide whether sleep data is needed; fetch it for the required
    dates.
2.  Decide whether nightly-recovery data is needed; fetch it if
    required.
3.  Store the results.
4.  Delete device-side data only when it is no longer needed.

The flowchart warns that sleep data for the previous night may not be
available immediately after waking because sleep detection must first
determine that sleep has ended. It mentions that sleep state can be
observed and sleep can be stopped using the Sleep API.

### 5.3 Skin temperature

The generic flowchart describes fetching and storing skin-temperature
data when the app needs it, then deleting device-side data when
appropriate.

It notes that the Temperature API provides automatically collected
skin-temperature values at a rate of one sample every five minutes. More
specific skin-temperature collection may use offline-recording API
methods.

Confirm whether this branch applies to the target device before
implementing it.

### 5.4 Training sessions

The generic flowchart describes fetching new training sessions, storing
them, and optionally deleting device-side training data after it is no
longer needed.

Depending on the device, training data may contain aggregate raw and
processed information such as:

-   Sport and duration
-   Distance and calories
-   Training load
-   Heart-rate samples
-   Location samples

The diagram mentions `getTrainingSessionReferences` and
`getTrainingSession` as related API operations. Training sessions can be
started/stopped by the device, Polar apps, or SDK methods; some devices
support automatic training detection.

This branch is likely unnecessary unless the research app explicitly
needs training-session data.

## 6. Recommended interpretation for the Verity Sense research app

Based on the current project goal---collect raw PPG and accelerometer
data, process signals, and export research data---the likely first
implementation scope is:

1.  Connect to the Verity Sense.
2.  Configure and start the required offline recordings.
3.  Stop recordings when appropriate.
4.  List and fetch completed recordings for the required sensor types.
5.  Preserve raw recordings on the phone.
6.  Validate the fetched data and record metadata such as timestamps,
    data type, sampling rate, and device/recording identifiers where
    available.
7.  Process raw PPG into derived metrics (such as estimated heart rate)
    and raw accelerometer samples into movement features.
8.  Export raw and derived data to the agreed CSV format.
9.  Upload the files to Dropbox.
10. Only delete device-side recordings after successful retrieval and
    storage, according to the SDK's supported workflow.

This is a project-specific interpretation, not a claim that every step
is already implemented or that every data type is supported in every
mode.

## 7. Questions to resolve before implementation

-   Which Verity Sense recording mode will the project use?
-   Which raw data types are required initially: PPG and ACC only, or
    others as well?
-   What sampling rates and recording parameters should be configured?
-   What exact data structures and timestamp conventions does the SDK
    return?
-   Where should raw-data processing happen: on the phone or in a
    separate research pipeline after upload?
-   Should raw files be preserved alongside derived CSVs?
-   What does a successful local save/upload mean before a device-side
    recording can be deleted?
-   How should interrupted downloads, duplicate fetches, and partial
    uploads be handled?
-   What participant identifier and file naming convention should be
    used?

## 8. Practical implementation checklist

-   [ ] Read the device-specific Verity Sense documentation.
-   [ ] Read the SDK's offline-recording documentation.
-   [ ] Identify the SDK methods for listing, fetching, and deleting
    offline recordings.
-   [ ] Confirm the raw PPG and ACC sample structures, units, and
    timestamps.
-   [ ] Define the app's recording metadata and CSV schema.
-   [ ] Implement a safe fetch → validate → save workflow.
-   [ ] Track sync stage/status so interrupted sync can resume.
-   [ ] Add error handling for disconnects, retries, and insufficient
    device readiness.
-   [ ] Test with public/example data before the physical device
    arrives.
-   [ ] Validate the pipeline against an actual Verity Sense recording
    when available.

## Source

-   [Polar BLE SDK --- Sync Implementation
    Guideline](https://github.com/polarofficial/polar-ble-sdk/blob/master/documentation/SyncImplementationGuideline.md)
-   [Polar BLE SDK --- Verity Sense product
    documentation](https://github.com/polarofficial/polar-ble-sdk/blob/master/documentation/products/PolarVeritySense.md)
