# ConnectIQ Development Deployment

## The Problem with Manual .prg Copying

Copying the compiled `.prg` binary directly to the watch filesystem (`GARMIN/APPS/` via USB)
**does NOT work** for companion app communication. This method:

- Does not register the app with Garmin Connect Mobile (GCM)
- Prevents `showDeviceSelection()` from presenting the watch
- Prevents message forwarding between the phone and watch apps
- The watch app will run standalone, but all `Communications.transmit()` calls will silently fail

## Correct Development Workflow

### Option 1: VS Code ConnectIQ Extension (Recommended)

1. Install the [Monkey C VS Code extension](https://marketplace.visualstudio.com/items?itemName=garmin.monkey-c)
2. Open `gympanion_watch/` in VS Code
3. Connect your watch via USB
4. Use **Run > Run Without Debugging** (or the "Run on Device" button)
5. The extension uses `monkeydo` under the hood, which properly registers the companion relationship

### Option 2: monkeydo CLI

```bash
# Build the project
monkeyc -d fr265 -f gympanion_watch/monkey.jungle -o gympanion_watch/bin/gympanion_watch.prg

# Deploy to connected device (registers companion relationship with GCM)
monkeydo gympanion_watch/bin/gympanion_watch.prg fr265
```

### Option 3: ConnectIQ Simulator + Companion Bridge

For testing companion communication without a physical watch:

1. Launch the ConnectIQ simulator from the SDK
2. Start the companion app bridge (connects simulator to GCM on the phone)
3. Load the `.prg` in the simulator
4. GCM on the phone will see the simulated device

## Verifying Companion Registration

After deploying via `monkeydo` or the VS Code extension:

1. Open Garmin Connect Mobile on your phone
2. Navigate to the ConnectIQ Store section
3. Your development app should appear under "My Apps" or "Sideloaded"
4. In the GymPanion iOS app, tap "Connect via Garmin Connect" — GCM should now present the device selection UI
5. After selecting the device, messages should flow in both directions

## Troubleshooting

- **GCM shows no device selection UI:** Ensure the watch app was deployed via `monkeydo`, not manual file copy. Re-deploy if needed.
- **Messages not received on phone:** Check that `register(forAppMessages:delegate:)` is called with the correct app UUID (`f98a251f-fbbe-4b0b-85de-d893670af9fe`). This UUID must match `manifest.xml`.
- **Watch shows "transmit error":** Verify the phone is connected via Bluetooth and GCM is running in the background.
