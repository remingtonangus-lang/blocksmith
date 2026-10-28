# Meta Horizon Store checks (P360 (c))

Checked against Meta's hz-store-submit skill (github.com/meta-quest/agentic-tools, skills/hz-store-submit) on
2026-10-18. `quest/tools/storecheck.sh STORE.apk` runs the packaging rows on every store build.

| Check | State | Where |
|---|---|---|
| Release signing, APK Signature Scheme v2 | Ready: `STORE_KEYSTORE`, `STORE_KEY_ALIAS`, `STORE_KS_PASS` sign the store build; storecheck fails a store APK signed with the debug key or without v2 | quest/tools/build-apk.sh, storecheck.sh |
| minSdk >= 29, targetSdk >= 32 | Pass (29 / 32) | build-apk.sh aapt2 link |
| ARM64 only | Pass (lib/arm64-v8a only; storecheck fails any other ABI) | storecheck.sh |
| VR intent category | Pass (com.oculus.intent.category.VR on the launch activity) | quest/android/AndroidManifest.xml |
| Permissions | Pass: OpenXR and INTERNET (the in-game bug and idea reporter, P480; co-op and its Wi-Fi permissions are gone, P479). RECORD_AUDIO is deleted from the store build. storecheck fails any prohibited permission | storecheck.sh |
| Focus awareness: pause when the headset comes off or the system menu opens | Pass: the game pauses and saves when the session leaves FOCUSED; hands and controllers are dropped and input ignored (XRSession.pollInput), haptics stop | quest/src/app/QuestApp.swift, quest/src/xr/XRSession.swift |
| Entitlement within 10 s | Code ready (QuestEntitlement, asked at launch, answered offline by the platform); the store app ID is 1396130500248132: build the store APK with `QUEST_APP_ID=1396130500248132 STORE=1` and add the platform loader library | quest/src/common/QuestEntitlement.swift |
| No crash in a 30 min soak | Needs the headset: run `questcheck --questsim` for 30 minutes on device | |
| 72 Hz sustained, no thermal throttling in 5 min, interactive in 15 s | Needs the headset (with P339's performance work) | |
| Store assets | Plan in art-plan.md; captured on device | docs/store/art-plan.md |
| Privacy policy, age rating, comfort | Drafts in this folder | |
| Data use answers | The bug and idea reporter (P480) sends, on the player's Send only: their words, a random per-install report ID, the game version and game details (position, biome, held item, frame rate). Data types: "user-generated content" and "app diagnostics / crash and performance data"; purpose "app functionality / developer communications"; not linked to identity; deletion on request by report ID (privacy-policy.md). | Reporter.swift |
